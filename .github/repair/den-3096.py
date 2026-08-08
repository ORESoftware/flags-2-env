#!/usr/bin/env python3
"""One-shot exact-blob repair for DEN-3096.

This carrier is deleted by the workflow that invokes it.  It refuses to edit an
unexpected checker blob and every textual replacement must match exactly once.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import textwrap

ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "tools" / "borrow-checker" / "borrow_check.py"
EXPECTED_GIT_BLOB = "e00047d734ffa1b43e5d3415e33d6d12425b4d06"


def git_blob_sha(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode()
    return hashlib.sha1(header + data).hexdigest()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


data = CHECKER.read_bytes()
actual = git_blob_sha(data)
if actual != EXPECTED_GIT_BLOB:
    raise SystemExit(
        f"unexpected checker blob: expected {EXPECTED_GIT_BLOB}, got {actual}"
    )
text = data.decode("utf-8")

text = replace_once(
    text,
    """A flow-sensitive ownership analysis for the C core, enforcing the library's
own contract (F2E_OWNED_RESULT / F2E_TAKES_OWNED_ARG_1) instead of renting a
generic analyzer. It interprets clang's JSON AST, infers ownership contracts
for static helpers by fixpoint, and rejects every path that could reach a
segfault-class defect:
""",
    """A flow-sensitive ownership analysis for the C core, enforcing the library's
own contract (F2E_OWNED_RESULT / F2E_TAKES_OWNED_ARG_1) instead of renting a
generic analyzer. It interprets clang's JSON AST, infers ownership and non-null
preconditions for static helpers by fixpoint, and reports the modeled
segfault-class defects:
""",
    "module claim",
)
text = replace_once(
    text,
    """The ownership state machine implemented here is mirrored, transition for
transition, by formal/smt/ownership_lattice.smt2; formal-check.sh proves the
machine cannot let a use-after-free or double-free trace through undetected.
Keep the two in sync: any change to STATES or the transition logic must be
reflected in the SMT model.
""",
    """The ownership state machine implemented here is mirrored, transition for
transition, by formal/smt/ownership_lattice.smt2. formal-check.sh proves the
bounded abstract transition model cannot admit its modeled use-after-free or
double-free traces. It does not prove clang AST collection, control-flow
lowering, helper-summary inference, or waiver parsing. Keep the ownership
lattice and SMT model in sync; those surrounding implementation layers are
covered by fixtures and independent black-box promotion tests.
""",
    "formal scope claim",
)

text = replace_once(
    text,
    """# --- Function analysis -----------------------------------------------------

class FunctionSummary(object):
""",
    r'''# --- Function analysis -----------------------------------------------------

# Nullability is a separate inference-only lattice.  It deliberately does not
# extend the formally modeled ownership lattice above: ownership answers who
# must release a value, while this lattice infers whether a local helper may
# dereference a pointer argument without first guarding it.
NULL_UNKNOWN = "null-unknown"
NULL_DEFINITE = "null-definite"
NONNULL = "non-null"


def extract_comment_lines(source_lines):
    """Return actual C comment text per source line, excluding strings/chars."""
    result = []
    in_block = False
    for line in source_lines:
        pieces = []
        i = 0
        quote = None
        escaped = False
        while i < len(line):
            if in_block:
                end = line.find("*/", i)
                if end < 0:
                    pieces.append(line[i:])
                    i = len(line)
                else:
                    pieces.append(line[i:end])
                    in_block = False
                    i = end + 2
                continue

            char = line[i]
            pair = line[i:i + 2]
            if quote is not None:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
                i += 1
                continue
            if pair == "//":
                pieces.append(line[i + 2:])
                break
            if pair == "/*":
                in_block = True
                i += 2
                continue
            if char in ('"', "'"):
                quote = char
            i += 1
        result.append(" ".join(
            piece.strip() for piece in pieces if piece.strip()))
    return result


class FunctionSummary(object):
''',
    "comment lexer and nullability lattice",
)
text = replace_once(
    text,
    """        self.may_take_params = set()


class Frame(object):
""",
    """        self.may_take_params = set()
        self.nonnull_params = set()


class Frame(object):
""",
    "summary non-null parameters",
)
text = replace_once(
    text,
    """class Frame(object):
    \"\"\"One abstract state: variable name -> lattice state.\"\"\"

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
""",
    """class Frame(object):
    \"\"\"One abstract ownership state plus inference-only nullability facts.\"\"\"

    def __init__(self, states=None, nullability=None):
        self.states = dict(states or {})
        self.nullability = dict(nullability or {})
        self.terminated = False

    def copy(self):
        frame = Frame(self.states, self.nullability)
        frame.terminated = self.terminated
        return frame

    def get(self, name):
        return self.states.get(name)

    def set(self, name, state):
        self.states[name] = state

    def get_null(self, name):
        return self.nullability.get(name)

    def set_null(self, name, state):
        self.nullability[name] = state
""",
    "frame nullability",
)
text = replace_once(
    text,
    """    for name in names:
        state = None
        for f in live:
            state = join_states(state, f.states.get(name, UNKNOWN))
        merged.states[name] = state
    return merged
""",
    """    for name in names:
        state = None
        for f in live:
            state = join_states(state, f.states.get(name, UNKNOWN))
        merged.states[name] = state
    null_names = set()
    for f in live:
        null_names.update(f.nullability)
    for name in null_names:
        values = [f.nullability.get(name, NULL_UNKNOWN) for f in live]
        merged.nullability[name] = (
            values[0] if all(value == values[0] for value in values)
            else NULL_UNKNOWN
        )
    return merged
""",
    "merge nullability",
)
text = replace_once(
    text,
    """        self.source_lines = source_lines
        self.contracts = contracts
""",
    """        self.source_lines = source_lines
        self.comment_lines = extract_comment_lines(source_lines)
        self.contracts = contracts
""",
    "comment-line initialization",
)
text = replace_once(
    text,
    """        self.stores_seen = set()
        self.param_order = []
""",
    """        self.stores_seen = set()
        self.nonnull_seen = set()
        self.param_order = []
""",
    "nonnull inference set",
)
text = replace_once(
    text,
    """        self._takes_map = None
        self._may_take_map = {}
""",
    """        self._takes_map = None
        self._may_take_map = {}
        self._nonnull_map = None
""",
    "nonnull map cache",
)
text = replace_once(
    text,
    """    def is_waived(self, rule, line):
        needle = \"borrow-check: allow(%s)\" % rule
        # line is 1-based; inspect flagged line and immediately preceding line
        for idx in (line - 1, line - 2):
            if 0 <= idx < len(self.source_lines):
                text = self.source_lines[idx]
                if needle in text:
                    suffix = text[text.index(needle) + len(needle):]
                    if \"--\" in suffix:
                        return True
        return False
""",
    r'''    def is_waived(self, rule, line):
        # line is 1-based; inspect the flagged line and immediately preceding
        # line, but only inside lexed C comments.  String literals and empty
        # justifications are never waiver authority.
        pattern = re.compile(
            r"(?:^|\s)borrow-check:\s*allow\(\s*%s\s*\)\s*--\s*(\S(?:.*\S)?)\s*$"
            % re.escape(rule))
        for idx in (line - 1, line - 2):
            if 0 <= idx < len(self.comment_lines):
                match = pattern.search(self.comment_lines[idx])
                if match is not None and match.group(1).strip():
                    return True
        return False
''',
    "comment-only waiver parser",
)
text = replace_once(
    text,
    """                    if is_pointer_type(child):
                        self.params.add(name)
                        frame.set(name, BORROWED)
""",
    """                    if is_pointer_type(child):
                        self.params.add(name)
                        frame.set(name, BORROWED)
                        if self.infer_only:
                            frame.set_null(name, NULL_UNKNOWN)
""",
    "inference parameter nullability",
)
text = replace_once(
    text,
    """        return self._takes_map

    def eval_call(self, call, frame, loc):
""",
    """        return self._takes_map

    def nonnull_map(self):
        if self._nonnull_map is None:
            result = {
                name: set(indices)
                for name, indices in self.contracts.null_strict.items()
            }
            for summary in self.summaries.values():
                if summary.nonnull_params:
                    result.setdefault(summary.name, set()).update(
                        summary.nonnull_params)
            self._nonnull_map = result
        return self._nonnull_map

    def eval_call(self, call, frame, loc):
""",
    "nonnull map",
)
text = replace_once(
    text,
    """        takes = self.takes_map()

        for idx, arg in enumerate(args):
""",
    """        takes = self.takes_map()
        nonnull = self.nonnull_map()

        for idx, arg in enumerate(args):
""",
    "call nonnull map",
)
text = replace_once(
    text,
    """                if target is not None and target in frame.states:
                    frame.set(target, UNKNOWN)
                continue
""",
    """                if target is not None and target in frame.states:
                    frame.set(target, UNKNOWN)
                    if target in frame.nullability:
                        frame.set_null(target, NULL_UNKNOWN)
                continue
""",
    "out-parameter nullability",
)
text = replace_once(
    text,
    """            state = frame.get(arg_name)
            takes_this = name in takes and takes[name] == idx
""",
    """            state = frame.get(arg_name)
            requires_nonnull = idx in nonnull.get(name, ())
            if requires_nonnull:
                null_state = frame.get_null(arg_name)
                if self.infer_only and arg_name in self.params and \\
                        null_state in (NULL_UNKNOWN, NULL_DEFINITE):
                    self.nonnull_seen.add(
                        self.param_order.index(arg_name))
                elif state in (MAYBE_NULL, NULLPTR):
                    self.report(loc, \"null-deref\",
                                \"'%s' may be NULL when passed to %s; check \"
                                \"the allocation first\" % (arg_name, name))
            takes_this = name in takes and takes[name] == idx
""",
    "call-site nonnull enforcement",
)
text = replace_once(
    text,
    """            if name in self.contracts.null_strict and \\
                    idx in self.contracts.null_strict[name] and \\
                    state in (MAYBE_NULL, NULLPTR):
                self.report(loc, \"null-deref\",
                            \"'%s' may be NULL when passed to %s; check \"
                            \"the allocation first\" % (arg_name, name))

""",
    "",
    "remove builtin-only null check",
)
text = replace_once(
    text,
    """        state = frame.get(name)
        if state == FREED:
""",
    """        state = frame.get(name)
        null_state = frame.get_null(name)
        if self.infer_only and name in self.params and \\
                null_state in (NULL_UNKNOWN, NULL_DEFINITE):
            self.nonnull_seen.add(self.param_order.index(name))
        if state == FREED:
""",
    "deref summary inference",
)
text = replace_once(
    text,
    """    def assign(self, name, rhs, frame, loc, declaring=False):
""",
    """    def expr_nullability(self, expr, frame):
        expr = unwrap(expr)
        if expr is None:
            return NULL_UNKNOWN
        kind = expr.get(\"kind\")
        if kind == \"IntegerLiteral\":
            return (NULL_DEFINITE if expr.get(\"value\") in (\"0\", 0)
                    else NULL_UNKNOWN)
        if kind == \"StringLiteral\":
            return NONNULL
        if kind == \"UnaryOperator\" and expr.get(\"opcode\") == \"&\":
            return NONNULL
        if kind == \"DeclRefExpr\":
            source = ref_name(expr)
            tracked = frame.get_null(source)
            if tracked is not None:
                return tracked
            ownership = frame.get(source)
            if ownership in (OWNED, BORROWED):
                return NONNULL
            if ownership == NULLPTR:
                return NULL_DEFINITE
        return NULL_UNKNOWN

    def assign(self, name, rhs, frame, loc, declaring=False):
""",
    "nullability classifier",
)
text = replace_once(
    text,
    """        prev = frame.get(name)
        bare = unwrap(rhs)
        rhs_call_name = callee_name(bare) if bare is not None and \\
""",
    """        prev = frame.get(name)
        bare = unwrap(rhs)
        rhs_nullability = self.expr_nullability(bare, frame)
        rhs_call_name = callee_name(bare) if bare is not None and \\
""",
    "assignment nullability capture",
)
text = replace_once(
    text,
    """        self.eval_expr(rhs, frame, loc)

        if bare is None:
""",
    """        self.eval_expr(rhs, frame, loc)
        if name in frame.nullability:
            frame.set_null(name, rhs_nullability)

        if bare is None:
""",
    "assignment nullability update",
)
text = replace_once(
    text,
    """            state = frame.get(name)
            if state is None:
                continue
            if is_null:
""",
    """            if frame.get_null(name) is not None:
                frame.set_null(
                    name, NULL_DEFINITE if is_null else NONNULL)
            state = frame.get(name)
            if state is None:
                continue
            if is_null:
""",
    "condition nullability refinement",
)
text = replace_once(
    text,
    """            new_stores = analyzer.stores_seen - summary.may_take_params
            if new_stores:
                summary.may_take_params |= new_stores
                changed = True
""",
    """            new_stores = analyzer.stores_seen - summary.may_take_params
            if new_stores:
                summary.may_take_params |= new_stores
                changed = True
            new_nonnull = analyzer.nonnull_seen - summary.nonnull_params
            if new_nonnull:
                summary.nonnull_params |= new_nonnull
                changed = True
""",
    "nonnull summary fixpoint",
)

CHECKER.write_text(text, encoding="utf-8")

bad = ROOT / "tools" / "borrow-checker" / "fixtures" / "bad"
good = ROOT / "tools" / "borrow-checker" / "fixtures" / "good"
(bad / "interprocedural_null_deref.c").write_text(textwrap.dedent("""\
    #include <stdlib.h>

    // EXPECT: null-deref
    static void read_first(const char *p) {
      (void)*p;
    }

    int main(void) {
      char *p = (char *)malloc(4);
      read_first(p);
      free(p);
      return 0;
    }
    """), encoding="utf-8")
(bad / "waiver_string_literal.c").write_text(textwrap.dedent("""\
    #include <stdlib.h>

    // EXPECT: leak
    int main(void) {
      char *p = (char *)malloc(4);
      const char *marker = "borrow-check: allow(leak) -- not a comment";
      return p != 0;
    }
    """), encoding="utf-8")
(bad / "waiver_empty_reason.c").write_text(textwrap.dedent("""\
    #include <stdlib.h>

    // EXPECT: leak
    int main(void) {
      char *p = (char *)malloc(4);
      /* borrow-check: allow(leak) -- */
      return p != 0;
    }
    """), encoding="utf-8")
(good / "guarded_helper_nullability.c").write_text(textwrap.dedent("""\
    #include <stdlib.h>

    static void read_if_present(const char *p) {
      if (!p) {
        return;
      }
      (void)*p;
    }

    int main(void) {
      char *p = (char *)malloc(4);
      read_if_present(p);
      free(p);
      return 0;
    }
    """), encoding="utf-8")

formal = ROOT / "FORMAL_PROOF.md"
formal_text = formal.read_text(encoding="utf-8")
scope_heading = "## Proof boundary: abstract model versus analyzer implementation"
if scope_heading not in formal_text:
    formal_text = formal_text.rstrip() + "\n\n" + textwrap.dedent("""\
        ## Proof boundary: abstract model versus analyzer implementation

        The Kani, CBMC, and Z3 obligations prove properties of the bounded
        ownership transition model encoded in this repository. They do not by
        themselves prove clang AST collection, control-flow lowering,
        interprocedural summary inference, comment/waiver parsing, or that every
        concrete C execution is represented by the abstraction.

        Those implementation boundaries are enforced separately by the
        checker's good/bad fixture suite and by exact-commit black-box promotion
        tests in `flags-2-env-test`. A change to any parser, lowering rule,
        summary, waiver rule, or lattice transition must update the matching
        fixtures; ownership-state changes must also update the formal models.
        """)
    formal.write_text(formal_text, encoding="utf-8")

print("DEN-3096 exact-blob repair applied")
