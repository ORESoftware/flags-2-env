# Custom borrow checker

A flow-sensitive ownership analysis for the flags-2-env C core. Instead of
renting a generic analyzer, it enforces the library's own contract — the
`F2E_OWNED_RESULT` and `F2E_TAKES_OWNED_ARG_1` macros in `src/parser.h` —
across every function, and infers the same contracts for file-local static
helpers by fixpoint, so internal destructors and allocators are checked
without annotation.

## What it rejects

| rule | defect |
| --- | --- |
| `double-free` | a freed pointer reaches `free`/`f2e_free`/a taking callee again |
| `use-after-free` | a freed pointer is read, dereferenced, passed on, or returned |
| `free-borrowed` | a public (non-`static`) function frees a parameter without declaring `F2E_TAKES_OWNED_ARG_1` |
| `null-deref` | an unchecked allocation result (or definitely-NULL pointer) is dereferenced, handed to null-strict libc, or passed to a local function that dereferences that parameter without guarding it |
| `leak` | an owned pointer goes out of scope or crosses a `return` unreleased |
| `overwrite-leak` | an owned pointer is overwritten while it still owns its block |
| `return-local-addr` | the address of a stack local (or a decayed stack array) escapes via `return` |
| `lost-realloc` | `p = realloc(p, n)` drops the only reference when realloc fails |

## How it works

1. `clang -Xclang -ast-dump=json -fsyntax-only` supplies the AST; the checker
   has no parser of its own and no third-party dependencies.
2. Declared contracts are read textually from headers passed via
   `--header-contract`; static-helper contracts are inferred by iterating
   the analysis to a fixpoint: returns-owned (returns an allocation),
   takes-ownership (frees a parameter), and may-take (stores a parameter
   into non-local memory — a conditional transfer, treated like realloc's
   argument: the caller may legally free on the callee's failure path or
   hand off on success).
3. Each function body is abstractly interpreted over the ownership lattice
   `uninit / null / maybe-null / owned / borrowed / freed / moved / unknown`,
   with branch-state merging, loop widening (two-pass), switch arms restarted
   from the switch entry state, and `if (!p)`-style null-check refinement.
4. A collection audit cross-checks the AST against a textual scan of the
   `static` function definitions and hard-fails on any mismatch, so a
   clang-version difference in location serialization can never silently
   shrink the analyzed surface (Apple clang 21 and Ubuntu clang 18 disagreed
   by 95 functions before this guard existed).

## What is proved, and what is not

This distinction matters, because "a Z3 proof backs this tool" is easy to
over-read. The proof covers **one component**, not the pipeline.

**Proved** (`formal/smt/ownership_lattice.smt2`, run by
`scripts/formal-check.sh`): the abstract ownership state machine. Given a
sequence of abstract events, Z3 shows no bounded trace reaches a
use-after-free or double-free unflagged, the canonical
allocate/check/use/free contract never flags, and the branch-merge join is
commutative and never forgets a conditional free. The SMT model mirrors
`STATES` and the transition logic transition-for-transition; change them
together.

**Not proved — trusted, and covered only by tests:**

- *AST collection* — that clang's JSON gives us every function. Guarded by
  the `audit_collection` cross-check, not by proof; a clang-version
  serialization difference once hid 95 functions.
- *Control-flow lowering* — that abstract interpretation of the AST
  (loop widening, switch arms, short-circuit operands) emits the event
  sequence the proved machine reasons about.
- *Summary inference* — the fixpoint deriving returns-owned, takes,
  may-take, and requires-nonnull facts for local functions.
- *Nullability tracking* — `Frame.nonnull` is a side-channel fact, not a
  lattice state, and is outside the proved machine entirely.
- *Waiver parsing* — which findings get suppressed.

A defect in any unproved component is a false negative the proof cannot
see. Two such defects were found by adversarial review (DEN-3096) after
the first release: a helper that dereferenced an unguarded parameter was
missed, and a string literal quoting the waiver syntax suppressed a real
leak. Both are now fixture-covered; treat this list as the map of where
to look next.

## Running

```sh
python3 tools/borrow-checker/borrow_check.py --self-test
python3 tools/borrow-checker/borrow_check.py \
  -I. -Isrc --header-contract src/parser.h \
  src/parser.c src/main.c src/terminal_context.c
```

`scripts/borrow-check.sh` (and therefore `make borrow-check`, `make test`,
and the sanitizers workflow) runs the self-test first and then the real
sources; the clang static analyzer stays on afterwards as an independent
second opinion.

## Waivers

A finding is silenced only by an inline justification on the flagged line or
the line above:

```c
/* borrow-check: allow(leak) -- handed to the OS at process exit */
```

The waiver names one rule and must carry a reason after `--`.

## Fixtures

`fixtures/bad/*.c` each declare the diagnostics they must produce via
`// EXPECT: <rule>`; `fixtures/good/*.c` must stay clean. The self-test
fails if either direction drifts, in the same spirit as the
expect-a-warning fixtures in `scripts/borrow-check.sh`.
