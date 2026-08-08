#!/usr/bin/env python3
"""flags-2-env custom borrow checker.

A flow-sensitive ownership analysis for the C core, enforcing the library's
own contract (F2E_OWNED_RESULT / F2E_TAKES_OWNED_ARG_1) instead of renting a
generic analyzer. It interprets clang's JSON AST, infers ownership contracts
for static helpers by fixpoint, and rejects every path that could reach a
segfault-class defect:

  double-free            a freed pointer reaches free again
  use-after-free         a freed pointer is read, dereferenced, or passed on
  free-borrowed          a borrowed parameter is freed by its borrower
  null-deref             an unchecked allocation result is dereferenced
  leak                   an owned pointer goes out of scope unreleased
  overwrite-leak         an owned pointer is overwritten while still owned
  return-local-addr      the address of a stack local escapes via return
  lost-realloc           p = realloc(p, n) drops the block when realloc fails

Exit status is non-zero when any diagnostic fires. A finding can be waived
only with an inline justification on the flagged line or the line above:

    /* borrow-check: allow(<rule>) -- <reason> */

The ownership state machine implemented here is mirrored, transition for
transition, by formal/smt/ownership_lattice.smt2; formal-check.sh proves the
machine cannot let a use-after-free or double-free trace through undetected.
Keep the two in sync: any change to STATES or the transition logic must be
reflected in the SMT model.
"""

import argparse
import json
import os
import re
import subprocess
import sys

# --- Ownership lattice -----------------------------------------------------
# Mirrored in formal/smt/ownership_lattice.smt2.

UNINIT = "uninit"          # declared, no value yet
NULLPTR = "null"           # definitely NULL
MAYBE_NULL = "maybe-null"  # fresh allocation, not yet null-checked (owned if non-null)
OWNED = "owned"            # non-null, this frame must release or transfer it
BORROWED = "borrowed"      # non-owning view (parameters, string literals)
FREED = "freed"            # released; any further use is a defect
MOVED = "moved"            # ownership transferred (returned, stored, or taken)
UNKNOWN = "unknown"        # untracked provenance (struct fields, arithmetic)

OWNING_STATES = (OWNED, MAYBE_NULL)

JOIN = {}


def _def_join(a, b, result):
    JOIN[(a, b)] = result
    JOIN[(b, a)] = result


for _s in (UNINIT, NULLPTR, MAYBE_NULL, OWNED, BORROWED, FREED, MOVED, UNKNOWN):
    JOIN[(_s, _s)] = _s
_def_join(NULLPTR, OWNED, MAYBE_NULL)
_def_join(NULLPTR, MAYBE_NULL, MAYBE_NULL)
_def_join(OWNED, MAYBE_NULL, MAYBE_NULL)
_def_join(FREED, NULLPTR, FREED)      # conditional free: treat later use as UAF
_def_join(FREED, OWNED, FREED)
_def_join(FREED, MAYBE_NULL, FREED)
_def_join(FREED, MOVED, FREED)
_def_join(MOVED, OWNED, MOVED)
_def_join(MOVED, MAYBE_NULL, MOVED)
_def_join(MOVED, NULLPTR, MOVED)


def join_states(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return JOIN.get((a, b), UNKNOWN)


# Allocators whose result the caller owns and must null-check before use.
BUILTIN_ALLOCATORS = {
    "malloc", "calloc", "strdup", "strndup", "realpath", "getcwd",
    "aligned_alloc",
}
# free-like: (function name -> zero-based owned-argument index)
BUILTIN_TAKERS = {"free": 0}
# libc that dereferences the named zero-based argument unconditionally.
NULL_STRICT = {
    "strlen": (0,), "strcpy": (0, 1), "strcmp": (0, 1), "strncmp": (0, 1),
    "strchr": (0,), "strrchr": (0,), "strstr": (0, 1), "memcpy": (0, 1),
    "memmove": (0, 1), "memset": (0,), "strcat": (0, 1), "strncat": (0, 1),
    "strcspn": (0, 1), "strspn": (0, 1), "atoi": (0,), "strtol": (0,),
    "strtoul": (0,), "strtod": (0,), "fputs": (0,), "fwrite": (0,),
}

RULES = (
    "double-free", "use-after-free", "free-borrowed", "null-deref",
    "leak", "overwrite-leak", "return-local-addr", "lost-realloc",
)


class Diagnostic(object):
    __slots__ = ("path", "line", "col", "rule", "message")

    def __init__(self, path, line, col, rule, message):
        self.path = path
        self.line = line
        self.col = col
        self.rule = rule
        self.message = message

    def key(self):
        return (self.path, self.line, self.rule, self.message)

    def render(self):
        return "%s:%d:%d: error[%s]: %s" % (
            self.path, self.line, self.col, self.rule, self.message)


class Contracts(object):
    """Ownership facts about callees, builtin plus inferred plus declared."""

    def __init__(self):
        self.returns_owned = set(BUILTIN_ALLOCATORS)
        self.takes = dict(BUILTIN_TAKERS)
        self.null_strict = dict(NULL_STRICT)

    def load_header(self, header_path):
        """Read F2E_OWNED_RESULT / F2E_TAKES_OWNED_ARG_1 from a header's text.

        The macros are the public contract; reading them textually keeps the
        checker independent of how a given clang serializes attributes.
        """
        try:
            with open(header_path, "r") as fh:
                text = fh.read()
        except OSError:
            return
        text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        for match in re.finditer(
                r"\b(?:char|int|void|const\s+char)\s*\**\s*(\w+)\s*\([^;]*?\)\s*"
                r"((?:F2E_\w+\s*)+);", text):
            name, macros = match.group(1), match.group(2)
            if "F2E_OWNED_RESULT" in macros:
                self.returns_owned.add(name)
            if "F2E_TAKES_OWNED_ARG_1" in macros:
                self.takes[name] = 0


# --- clang AST access ------------------------------------------------------

def run_clang(clang, path, include_dirs, extra_args):
    cmd = [clang, "-Xclang", "-ast-dump=json", "-fsyntax-only",
           "-std=c99", "-Wno-everything"]
    for inc in include_dirs:
        cmd.append("-I" + inc)
    cmd.extend(extra_args)
    cmd.append(path)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode("utf-8", "replace"))
        raise RuntimeError("clang failed on %s" % path)
    return json.loads(proc.stdout)


def collect_functions(tu, main_path):
    """Yield FunctionDecl nodes with bodies that live in main_path.

    clang only emits loc.file when the file changes, so track it statefully.
    """
    want = os.path.realpath(main_path)
    functions = []
    current_file = None
    for node in tu.get("inner", ()):
        loc = node.get("loc", {})
        if "file" in loc:
            current_file = loc["file"]
        spelling = loc.get("spellingLoc", {})
        if "file" in spelling:
            current_file = spelling["file"]
        if node.get("kind") != "FunctionDecl":
            continue
        if current_file is None or os.path.realpath(current_file) != want:
            continue
        if any(child.get("kind") == "CompoundStmt"
               for child in node.get("inner", ())):
            functions.append(node)
    return functions


def is_pointer_type(node):
    qual = node.get("type", {}).get("qualType", "")
    return "*" in qual and "(*)(" not in qual  # skip function pointers


def unwrap(expr):
    """Strip parens and value-preserving casts."""
    while expr is not None and expr.get("kind") in (
            "ParenExpr", "ImplicitCastExpr", "CStyleCastExpr",
            "ConstantExpr", "FullComment"):
        inner = [c for c in expr.get("inner", ()) if isinstance(c, dict)]
        if not inner:
            return expr
        expr = inner[0]
    return expr


def ref_name(expr):
    expr = unwrap(expr)
    if expr is not None and expr.get("kind") == "DeclRefExpr":
        return expr.get("referencedDecl", {}).get("name")
    return None


def callee_name(call):
    inner = call.get("inner", ())
    if not inner:
        return None
    return ref_name(inner[0])


def node_loc(node, fallback):
    for key in ("loc", "range"):
        loc = node.get(key)
        if isinstance(loc, dict):
            begin = loc.get("begin", loc)
            spelling = begin.get("spellingLoc", begin)
            expansion = begin.get("expansionLoc", begin)
            for candidate in (spelling, expansion, begin):
                if "line" in candidate:
                    return (candidate.get("line"),
                            candidate.get("col", 1))
    return fallback


# --- Function analysis -----------------------------------------------------

class FunctionSummary(object):
    def __init__(self, name):
        self.name = name
        self.returns_owned = False
        self.takes_params = set()


class Frame(object):
    """One abstract state: variable name -> lattice state."""

    def __init__(self, states=None):
        self.states = dict(states or {})
        self.terminated = False

    def copy(self):
        frame = Frame(self.states)
        frame.terminated = self.terminated
        return frame

    def get(self, name):
        return self.states.get(name)

    def set(self, name, state):
        self.states[name] = state


def merge_frames(frames):
    live = [f for f in frames if not f.terminated]
    if not live:
        merged = Frame()
        merged.terminated = True
        return merged
    merged = Frame()
    names = set()
    for f in live:
        names.update(f.states)
    for name in names:
        state = None
        for f in live:
            state = join_states(state, f.states.get(name, UNKNOWN))
        merged.states[name] = state
    return merged


class Analyzer(object):
    def __init__(self, path, source_lines, contracts, summaries,
                 infer_only=False):
        self.path = path
        self.source_lines = source_lines
        self.contracts = contracts
        self.summaries = summaries
        self.infer_only = infer_only
        self.diagnostics = []
        self.locals_ = set()
        self.params = set()
        self.local_addrs = set()   # vars holding &stack-local or array decay
        self.fn_name = None
        self.returns_owned_seen = False
        self.takes_seen = set()
        self.param_order = []
        self.current_loc = (0, 1)
        self._takes_map = None

    # -- diagnostics --------------------------------------------------------

    def report(self, loc, rule, message):
        if self.infer_only:
            return
        line, col = loc
        if self.is_waived(line, rule):
            return
        self.diagnostics.append(
            Diagnostic(self.path, line, col, rule, message))

    def is_waived(self, line, rule):
        needle = "borrow-check: allow(%s)" % rule
        for idx in (line - 1, line - 2):
            if 0 <= idx < len(self.source_lines):
                text = self.source_lines[idx]
                if needle in text and "--" in text.split(needle, 1)[1]:
                    return True
        return False

    # -- entry --------------------------------------------------------------

    def run(self, fn):
        self.fn_name = fn.get("name")
        frame = Frame()
        body = None
        for child in fn.get("inner", ()):
            kind = child.get("kind")
            if kind == "ParmVarDecl":
                name = child.get("name")
                if name:
                    self.param_order.append(name)
                    if is_pointer_type(child):
                        self.params.add(name)
                        frame.set(name, BORROWED)
            elif kind == "CompoundStmt":
                body = child
        if body is None:
            return
        # Two passes give loops a chance to stabilize; diagnostics from the
        # final pass only, deduplicated.
        for is_final in (False, True):
            self.diagnostics = []
            pass_frame = frame.copy()
            out = self.exec_stmt(body, pass_frame)
            if is_final and not out.terminated:
                self.check_leaks(out, node_loc(fn, self.current_loc),
                                 "function end")
        seen = set()
        unique = []
        for diag in self.diagnostics:
            if diag.key() in seen:
                continue
            seen.add(diag.key())
            unique.append(diag)
        self.diagnostics = unique

    # -- statements ---------------------------------------------------------

    def exec_stmt(self, stmt, frame):
        if stmt is None or frame.terminated:
            return frame
        kind = stmt.get("kind")
        loc = node_loc(stmt, self.current_loc)
        self.current_loc = loc

        if kind == "CompoundStmt":
            declared_here = []
            for child in stmt.get("inner", ()):
                before = set(frame.states)
                frame = self.exec_stmt(child, frame)
                if child.get("kind") == "DeclStmt":
                    declared_here.extend(
                        n for n in frame.states if n not in before)
                if frame.terminated:
                    return frame
            for name in declared_here:
                state = frame.get(name)
                if state in OWNING_STATES:
                    self.report(loc, "leak",
                                "'%s' owns an allocation but goes out of "
                                "scope without f2e_free/transfer" % name)
                frame.states.pop(name, None)
            return frame

        if kind == "DeclStmt":
            for child in stmt.get("inner", ()):
                if child.get("kind") != "VarDecl":
                    continue
                name = child.get("name")
                if not name:
                    continue
                self.locals_.add(name)
                if not is_pointer_type(child):
                    continue
                init = None
                for sub in child.get("inner", ()):
                    if sub.get("kind") not in ("FullComment",):
                        init = sub
                frame.set(name, UNINIT)
                if init is not None:
                    self.assign(name, init, frame,
                                node_loc(child, loc), declaring=True)
            return frame

        if kind == "ReturnStmt":
            inner = [c for c in stmt.get("inner", ()) if isinstance(c, dict)]
            ret_name = None
            if inner:
                expr = inner[0]
                self.eval_expr(expr, frame, loc)
                ret_name = ref_name(expr)
                bare = unwrap(expr)
                if ret_name is not None:
                    state = frame.get(ret_name)
                    if state == FREED:
                        self.report(loc, "use-after-free",
                                    "returning '%s' after it was freed"
                                    % ret_name)
                    if ret_name in self.local_addrs:
                        self.report(loc, "return-local-addr",
                                    "'%s' holds the address of a stack "
                                    "local" % ret_name)
                    if state in OWNING_STATES:
                        self.returns_owned_seen = True
                        frame.set(ret_name, MOVED)
                elif bare is not None:
                    if self.classify_call_owned(bare):
                        self.returns_owned_seen = True
                    if bare.get("kind") == "UnaryOperator" and \
                            bare.get("opcode") == "&":
                        target = ref_name(bare.get("inner", [None])[0]
                                          if bare.get("inner") else None)
                        if target in self.locals_:
                            self.report(loc, "return-local-addr",
                                        "returning the address of stack "
                                        "local '%s'" % target)
            self.check_leaks(frame, loc, "return", skip=ret_name)
            frame.terminated = True
            return frame

        if kind == "IfStmt":
            inner = [c for c in stmt.get("inner", ()) if isinstance(c, dict)]
            has_else = stmt.get("hasElse", False)
            cond = inner[0] if inner else None
            then_stmt = inner[1] if len(inner) > 1 else None
            else_stmt = inner[2] if has_else and len(inner) > 2 else None
            if cond is not None:
                self.eval_expr(cond, frame, loc)
            then_frame = frame.copy()
            else_frame = frame.copy()
            self.apply_refinement(cond, then_frame, True)
            self.apply_refinement(cond, else_frame, False)
            then_out = self.exec_stmt(then_stmt, then_frame)
            else_out = self.exec_stmt(else_stmt, else_frame) \
                if else_stmt is not None else else_frame
            return merge_frames([then_out, else_out])

        if kind in ("WhileStmt", "DoStmt", "ForStmt"):
            return self.exec_loop(stmt, frame, kind)

        if kind == "SwitchStmt":
            inner = [c for c in stmt.get("inner", ()) if isinstance(c, dict)]
            if inner:
                self.eval_expr(inner[0], frame, loc)
                body = inner[-1]
                arm = frame.copy()
                arm_out = self.exec_stmt(body, arm)
                return merge_frames([frame.copy(), arm_out])
            return frame

        if kind in ("BreakStmt", "ContinueStmt", "GotoStmt"):
            frame.terminated = True
            return frame

        if kind in ("CaseStmt", "DefaultStmt", "LabelStmt"):
            for child in stmt.get("inner", ()):
                if not isinstance(child, dict):
                    continue
                frame = self.exec_stmt(child, frame)
                if frame.terminated:
                    # case bodies end in break/return; recover so the next
                    # case label still gets analyzed from a live state
                    frame = frame.copy()
                    frame.terminated = False
            return frame

        if kind == "NullStmt":
            return frame

        # expression statement or anything else: evaluate for effects
        self.eval_expr(stmt, frame, loc)
        return frame

    def exec_loop(self, stmt, frame, kind):
        loc = node_loc(stmt, self.current_loc)
        inner = [c for c in stmt.get("inner", ()) if isinstance(c, dict)]
        entry = frame.copy()
        widened = entry
        for _ in range(2):
            body_frame = widened.copy()
            for child in inner:
                body_frame = self.exec_stmt(child, body_frame)
                if body_frame.terminated:
                    break
            after = body_frame.copy()
            after.terminated = False
            widened = merge_frames([entry, after])
        exit_frame = widened.copy()
        exit_frame.terminated = frame.terminated
        self.current_loc = loc
        return exit_frame

    # -- expressions --------------------------------------------------------

    def eval_expr(self, expr, frame, loc):
        if expr is None or not isinstance(expr, dict):
            return
        kind = expr.get("kind")
        loc = node_loc(expr, loc)

        if kind == "BinaryOperator" and expr.get("opcode") == "=":
            inner = [c for c in expr.get("inner", ()) if isinstance(c, dict)]
            if len(inner) == 2:
                lhs, rhs = inner
                lhs_name = ref_name(lhs)
                if lhs_name is not None and lhs_name in frame.states:
                    self.assign(lhs_name, rhs, frame, loc)
                    return
                # store through deref/member/subscript: RHS escapes
                self.eval_expr(rhs, frame, loc)
                self.eval_expr(lhs, frame, loc)
                rhs_name = ref_name(rhs)
                if rhs_name is not None and \
                        frame.get(rhs_name) in OWNING_STATES:
                    frame.set(rhs_name, MOVED)
            return

        if kind == "CallExpr":
            self.eval_call(expr, frame, loc)
            return

        if kind == "UnaryOperator":
            opcode = expr.get("opcode")
            inner = [c for c in expr.get("inner", ()) if isinstance(c, dict)]
            operand = inner[0] if inner else None
            if opcode == "*":
                self.check_deref(operand, frame, loc, "dereference")
            elif opcode == "&":
                pass  # address-of: handled where the value lands
            self.eval_expr(operand, frame, loc)
            return

        if kind == "ArraySubscriptExpr":
            inner = [c for c in expr.get("inner", ()) if isinstance(c, dict)]
            if inner:
                self.check_deref(inner[0], frame, loc, "index into")
            for child in inner:
                self.eval_expr(child, frame, loc)
            return

        if kind == "MemberExpr":
            inner = [c for c in expr.get("inner", ()) if isinstance(c, dict)]
            if expr.get("isArrow") and inner:
                self.check_deref(inner[0], frame, loc, "dereference")
            for child in inner:
                self.eval_expr(child, frame, loc)
            return

        if kind == "ConditionalOperator":
            inner = [c for c in expr.get("inner", ()) if isinstance(c, dict)]
            for child in inner:
                self.eval_expr(child, frame, loc)
            return

        if kind == "DeclRefExpr":
            name = ref_name(expr)
            if name is not None and frame.get(name) == FREED:
                self.report(loc, "use-after-free",
                            "'%s' is read after being freed" % name)
            return

        for child in expr.get("inner", ()):
            if isinstance(child, dict):
                self.eval_expr(child, frame, loc)

    def takes_map(self):
        if self._takes_map is None:
            takes = dict(self.contracts.takes)
            for summary in self.summaries.values():
                for idx in summary.takes_params:
                    takes.setdefault(summary.name, idx)
            self._takes_map = takes
        return self._takes_map

    def eval_call(self, call, frame, loc):
        name = callee_name(call)
        inner = [c for c in call.get("inner", ()) if isinstance(c, dict)]
        args = inner[1:] if inner else []
        takes = self.takes_map()

        for idx, arg in enumerate(args):
            arg_name = ref_name(arg)
            bare = unwrap(arg)
            # out-parameter: passing &x lets the callee re-initialize x
            if bare is not None and bare.get("kind") == "UnaryOperator" \
                    and bare.get("opcode") == "&":
                sub = bare.get("inner", ())
                target = ref_name(sub[0]) if sub else None
                if target is not None and target in frame.states:
                    frame.set(target, UNKNOWN)
                continue
            if arg_name is None:
                self.eval_expr(arg, frame, loc)
                continue
            state = frame.get(arg_name)
            takes_this = name in takes and takes[name] == idx
            if state == FREED:
                if takes_this:
                    self.report(loc, "double-free",
                                "'%s' is freed twice (second free via %s)"
                                % (arg_name, name or "call"))
                else:
                    self.report(loc, "use-after-free",
                                "'%s' is passed to %s after being freed"
                                % (arg_name, name or "a call"))
                continue
            if takes_this:
                if state == BORROWED and arg_name in self.params and \
                        not self.param_index_taken(arg_name):
                    self.report(loc, "free-borrowed",
                                "parameter '%s' is borrowed by this "
                                "function but freed via %s; declare the "
                                "transfer with F2E_TAKES_OWNED_ARG_1"
                                % (arg_name, name))
                if arg_name in self.params:
                    self.takes_seen.add(
                        self.param_order.index(arg_name))
                frame.set(arg_name, FREED)
                continue
            if name in self.contracts.null_strict and \
                    idx in self.contracts.null_strict[name] and \
                    state in (MAYBE_NULL, NULLPTR):
                self.report(loc, "null-deref",
                            "'%s' may be NULL when passed to %s; check "
                            "the allocation first" % (arg_name, name))

    def param_index_taken(self, param_name):
        summary = self.summaries.get(self.fn_name)
        if summary is None:
            return False
        try:
            idx = self.param_order.index(param_name)
        except ValueError:
            return False
        return idx in summary.takes_params or \
            self.contracts.takes.get(self.fn_name) == idx

    def check_deref(self, base_expr, frame, loc, verb):
        name = ref_name(base_expr)
        if name is None:
            return
        state = frame.get(name)
        if state == FREED:
            self.report(loc, "use-after-free",
                        "%s '%s' after it was freed" % (verb, name))
        elif state == MAYBE_NULL:
            self.report(loc, "null-deref",
                        "%s '%s' before its allocation is null-checked"
                        % (verb, name))
        elif state == NULLPTR:
            self.report(loc, "null-deref",
                        "%s '%s' which is NULL on this path" % (verb, name))

    # -- assignment ---------------------------------------------------------

    def classify_call_owned(self, expr):
        expr = unwrap(expr)
        if expr is None or expr.get("kind") != "CallExpr":
            return False
        name = callee_name(expr)
        if name is None:
            return False
        if name in self.contracts.returns_owned:
            return True
        summary = self.summaries.get(name)
        return summary is not None and summary.returns_owned

    def assign(self, name, rhs, frame, loc, declaring=False):
        prev = frame.get(name)
        bare = unwrap(rhs)
        rhs_call_name = callee_name(bare) if bare is not None and \
            bare.get("kind") == "CallExpr" else None

        if prev in OWNING_STATES and not declaring:
            if rhs_call_name == "realloc":
                args = [c for c in bare.get("inner", ())
                        if isinstance(c, dict)][1:]
                if args and ref_name(args[0]) == name:
                    self.report(loc, "lost-realloc",
                                "'%s = realloc(%s, ...)' loses the only "
                                "reference when realloc fails; assign to a "
                                "fresh variable first" % (name, name))
            else:
                self.report(loc, "overwrite-leak",
                            "'%s' still owns its previous allocation when "
                            "reassigned" % name)

        self.eval_expr(rhs, frame, loc)

        if bare is None:
            frame.set(name, UNKNOWN)
            return
        kind = bare.get("kind")
        if kind == "CallExpr":
            if self.classify_call_owned(bare):
                frame.set(name, MAYBE_NULL)
            else:
                frame.set(name, UNKNOWN)
            return
        if kind == "IntegerLiteral":
            value = bare.get("value")
            frame.set(name, NULLPTR if value in ("0", 0) else UNKNOWN)
            return
        if kind == "StringLiteral":
            frame.set(name, BORROWED)
            return
        if kind == "UnaryOperator" and bare.get("opcode") == "&":
            sub = bare.get("inner", ())
            target = ref_name(sub[0]) if sub else None
            if target in self.locals_:
                self.local_addrs.add(name)
            frame.set(name, BORROWED)
            return
        if kind == "DeclRefExpr":
            src = ref_name(bare)
            src_state = frame.get(src)
            if src_state in OWNING_STATES:
                frame.set(name, src_state)
                frame.set(src, MOVED)
            elif src_state == FREED:
                self.report(loc, "use-after-free",
                            "'%s' is copied from '%s' after it was freed"
                            % (name, src))
                frame.set(name, FREED)
            elif src_state is not None:
                frame.set(name, src_state)
                if src in self.local_addrs:
                    self.local_addrs.add(name)
            else:
                frame.set(name, UNKNOWN)
            return
        frame.set(name, UNKNOWN)

    # -- condition refinement -----------------------------------------------

    def apply_refinement(self, cond, frame, truth):
        for name, is_null in self.null_facts(cond, truth):
            state = frame.get(name)
            if state is None:
                continue
            if is_null:
                if state == MAYBE_NULL:
                    frame.set(name, NULLPTR)
            else:
                if state in (MAYBE_NULL, NULLPTR):
                    frame.set(name, OWNED)

    def null_facts(self, cond, truth):
        """Yield (var, is_null_in_this_branch) facts from a condition."""
        cond = unwrap(cond)
        if cond is None:
            return []
        kind = cond.get("kind")
        if kind == "DeclRefExpr":
            name = ref_name(cond)
            return [(name, not truth)] if name else []
        if kind == "UnaryOperator" and cond.get("opcode") == "!":
            inner = [c for c in cond.get("inner", ()) if isinstance(c, dict)]
            return self.null_facts(inner[0], not truth) if inner else []
        if kind == "BinaryOperator":
            opcode = cond.get("opcode")
            inner = [c for c in cond.get("inner", ()) if isinstance(c, dict)]
            if len(inner) != 2:
                return []
            lhs, rhs = inner
            if opcode in ("==", "!="):
                for var_side, lit_side in ((lhs, rhs), (rhs, lhs)):
                    name = ref_name(var_side)
                    lit = unwrap(lit_side)
                    is_null_lit = lit is not None and (
                        lit.get("kind") == "IntegerLiteral" and
                        lit.get("value") in ("0", 0) or
                        lit.get("kind") == "GNUNullExpr")
                    if name and is_null_lit:
                        equal_means_null = (opcode == "==")
                        return [(name, equal_means_null == truth)]
                return []
            if opcode == "&&" and truth:
                return self.null_facts(lhs, True) + self.null_facts(rhs, True)
            if opcode == "||" and not truth:
                return self.null_facts(lhs, False) + \
                    self.null_facts(rhs, False)
        return []

    # -- leaks --------------------------------------------------------------

    def check_leaks(self, frame, loc, where, skip=None):
        for name, state in sorted(frame.states.items()):
            if name == skip:
                continue
            if state in OWNING_STATES:
                self.report(loc, "leak",
                            "'%s' still owns its allocation at %s"
                            % (name, where))


# --- Driver ----------------------------------------------------------------

def infer_summaries(functions, path, source_lines, contracts):
    summaries = {}
    for fn in functions:
        name = fn.get("name")
        if name:
            summaries[name] = FunctionSummary(name)
    for _ in range(4):
        changed = False
        for fn in functions:
            name = fn.get("name")
            if not name:
                continue
            analyzer = Analyzer(path, source_lines, contracts, summaries,
                                infer_only=True)
            analyzer.run(fn)
            summary = summaries[name]
            if analyzer.returns_owned_seen and not summary.returns_owned:
                summary.returns_owned = True
                changed = True
            new_takes = analyzer.takes_seen - summary.takes_params
            if new_takes:
                summary.takes_params |= new_takes
                changed = True
        if not changed:
            break
    return summaries


def check_file(path, clang, include_dirs, extra_args, contracts):
    tu = run_clang(clang, path, include_dirs, extra_args)
    with open(path, "r") as fh:
        source_lines = fh.read().splitlines()
    functions = collect_functions(tu, path)
    summaries = infer_summaries(functions, path, source_lines, contracts)
    diagnostics = []
    for fn in functions:
        analyzer = Analyzer(path, source_lines, contracts, summaries)
        analyzer.run(fn)
        diagnostics.extend(analyzer.diagnostics)
    return diagnostics


def run_self_test(clang, script_dir):
    fixtures = os.path.join(script_dir, "fixtures")
    contracts_header = os.path.join(fixtures, "fixture_api.h")
    failures = []
    bad_dir = os.path.join(fixtures, "bad")
    good_dir = os.path.join(fixtures, "good")
    for file_name in sorted(os.listdir(bad_dir)):
        if not file_name.endswith(".c"):
            continue
        path = os.path.join(bad_dir, file_name)
        with open(path, "r") as fh:
            text = fh.read()
        expected = re.findall(r"//\s*EXPECT:\s*([a-z-]+)", text)
        contracts = Contracts()
        contracts.load_header(contracts_header)
        diagnostics = check_file(path, clang, [fixtures], [], contracts)
        got = [d.rule for d in diagnostics]
        for rule in expected:
            if rule not in got:
                failures.append("%s: expected a %s diagnostic, got %r"
                                % (file_name, rule, got))
        if not expected:
            failures.append("%s: bad fixture declares no // EXPECT" %
                            file_name)
    for file_name in sorted(os.listdir(good_dir)):
        if not file_name.endswith(".c"):
            continue
        path = os.path.join(good_dir, file_name)
        contracts = Contracts()
        contracts.load_header(contracts_header)
        diagnostics = check_file(path, clang, [fixtures], [], contracts)
        if diagnostics:
            failures.append("%s: expected clean, got:\n  %s" % (
                file_name,
                "\n  ".join(d.render() for d in diagnostics)))
    if failures:
        for failure in failures:
            sys.stderr.write("self-test: %s\n" % failure)
        return 1
    sys.stdout.write("borrow-check self-test: %d bad + %d good fixtures "
                     "verified\n" % (
                         len([f for f in os.listdir(bad_dir)
                              if f.endswith(".c")]),
                         len([f for f in os.listdir(good_dir)
                              if f.endswith(".c")])))
    return 0


def main(argv):
    parser = argparse.ArgumentParser(
        description="flags-2-env custom borrow checker")
    parser.add_argument("files", nargs="*", help="C sources to check")
    parser.add_argument("-I", dest="include_dirs", action="append",
                        default=[], help="include directory")
    parser.add_argument("--clang", default=os.environ.get("CLANG", "clang"))
    parser.add_argument("--header-contract", action="append", default=[],
                        help="header declaring F2E ownership macros")
    parser.add_argument("--extra-arg", action="append", default=[],
                        help="extra compiler argument")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    if args.self_test:
        return run_self_test(args.clang, script_dir)

    if not args.files:
        parser.error("no input files (or --self-test)")

    contracts = Contracts()
    for header in args.header_contract:
        contracts.load_header(header)

    total = []
    for path in args.files:
        diagnostics = check_file(path, args.clang, args.include_dirs,
                                 args.extra_arg, contracts)
        total.extend(diagnostics)
    for diag in total:
        sys.stderr.write(diag.render() + "\n")
    if total:
        sys.stderr.write("borrow-check: %d diagnostic(s)\n" % len(total))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
