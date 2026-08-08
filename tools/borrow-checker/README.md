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
| `null-deref` | an unchecked allocation result (or definitely-NULL pointer) is dereferenced or handed to null-strict libc |
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

The state machine is mirrored, transition for transition, by
`formal/smt/ownership_lattice.smt2`; `scripts/formal-check.sh` has Z3 prove
that the machine cannot let a use-after-free or double-free trace through
unflagged within bounded traces, and that the canonical
allocate/check/use/free contract never raises a diagnostic. Change the
Python and the SMT model together.

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
