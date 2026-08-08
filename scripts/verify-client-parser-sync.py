#!/usr/bin/env python3
"""Verify that every in-repo vendored parser copy is byte-identical to src/.

`scripts/verify-vendored-parser.py` answers a different question: it checks that
an *external* consumer compiled the same bytes as an immutable `parser_ref`.
Nothing checked the copies this repository ships to itself.

Those copies are load-bearing. `clients/cpp`, `clients/golang`, `clients/java`,
`clients/erlang` and the rest do not link `src/parser.c`; they compile their own
committed copy. When `src/parser.c` moves and a copy does not, the clients keep
building and keep passing, while two languages quietly parse by different rules.
That is invisible to every argv-level test, because a divergence only shows up on
the inputs the tests do not happen to cover.

The rule enforced here is the one already documented in
`docs/vendored-parser-identity.md`, applied inward: one parser, byte for byte.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

CANONICAL = ("src/parser.c", "src/parser.h")

# tests/fuzz_parser.c is a harness that wraps the parser, not a vendored copy of
# it, so it is deliberately out of scope. Anything else named parser.{c,h}
# outside src/ is in scope by default -- a new client should be caught by this
# check on the day it is added, not whenever someone remembers to list it.
EXCLUDED = frozenset({"tests/fuzz_parser.c", "tests/fuzz_parser.h"})


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def vendored_copies(root: Path, suffix: str) -> list[Path]:
    found = [
        path
        for path in sorted(root.rglob(f"parser{suffix}"))
        if path.is_file()
        and not path.is_symlink()
        and path.relative_to(root).parts[0] != "src"
        and str(path.relative_to(root)) not in EXCLUDED
        # Build trees and dependency checkouts are not ours to police.
        and not any(
            part in {".git", "build", "target", "node_modules", ".vendor", ".zed"}
            for part in path.relative_to(root).parts
        )
    ]
    return found


def check(root: Path, suffix: str) -> tuple[int, list[str]]:
    canonical = root / f"src/parser{suffix}"
    if not canonical.is_file():
        return 0, [f"canonical src/parser{suffix} is missing"]

    want = digest(canonical)
    problems: list[str] = []
    copies = vendored_copies(root, suffix)

    for copy in copies:
        got = digest(copy)
        rel = copy.relative_to(root)
        if got == want:
            print(f"  ok       {rel}")
            continue
        problems.append(
            f"{rel} differs from src/parser{suffix}\n"
            f"      canonical {want[:16]}\n"
            f"      vendored  {got[:16]}"
        )
        print(f"  DIFFERS  {rel}")

    return len(copies), problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=".",
        help="repository root to check (default: current directory)",
    )
    parser.add_argument(
        "--min-copies",
        type=int,
        default=1,
        help=(
            "fail if fewer than this many vendored copies were found. Guards "
            "against a glob that silently matches nothing and reports success."
        ),
    )
    args = parser.parse_args()

    root = Path(args.root).resolve(strict=True)
    problems: list[str] = []
    total = 0

    for suffix in (".c", ".h"):
        canonical = root / f"src/parser{suffix}"
        print(f"canonical src/parser{suffix} = {digest(canonical)[:16] if canonical.is_file() else 'MISSING'}")
        count, found = check(root, suffix)
        total += count
        problems.extend(found)
        print()

    # A check that inspects nothing must not pass. If the layout changes so that
    # no copies are discovered, that is a failure of this script, and saying so
    # is more useful than a green tick over an empty set.
    if total < args.min_copies:
        problems.append(
            f"found only {total} vendored parser files (expected at least "
            f"{args.min_copies}); the discovery glob has probably gone stale"
        )

    if problems:
        print("vendored parser copies are out of sync with src/:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nRegenerate the copies from src/ rather than editing them in place.\n"
            "See docs/vendored-parser-identity.md.",
            file=sys.stderr,
        )
        return 1

    print(f"all {total} vendored parser files match src/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
