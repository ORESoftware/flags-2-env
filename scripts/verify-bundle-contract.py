#!/usr/bin/env python3
"""Check the shared short-bundle contract against the reference parser.

Combined single-character flags (`ls -la`, `rm -rf`, `set -eo pipefail`,
`node -pe`, `tar -xvf archive.tar`) are the parser's densest corner: the
meaning of a token depends on the type of every short in it, on whether a
suffix happens to spell a boolean value alias, and on whether the trailing
short is adjacent to the next argv element.

Every language client binds the same `src/parser.c`, so these cases are not a
test of parsing logic thirty times over - they are a contract on the *binding
surface*. A client that reaches the parser at all must reproduce every row
exactly; one that reproduces none of them is green without having exercised
the library, which is the failure mode this file exists to close.

Usage:
    verify-bundle-contract.py                 # verify (CI)
    verify-bundle-contract.py --write         # regenerate after an
                                              # intentional semantics change
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "tests/fixtures/bundle-contract.json"


def run_case(cli: Path, config_dir: Path, argv: list[str]) -> dict:
    result = subprocess.run(
        [str(cli), *argv[1:]],
        cwd=str(config_dir),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"{' '.join(argv)} exited {result.returncode}: {result.stderr.strip()}"
        )
    return json.loads(result.stdout)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--cli",
        default=str(ROOT / "build/flags2env"),
        help="reference CLI to check against (default: build/flags2env)",
    )
    ap.add_argument(
        "--write",
        action="store_true",
        help="rewrite expectations from the CLI instead of verifying them",
    )
    args = ap.parse_args()

    cli = Path(args.cli)
    if not cli.is_file():
        raise SystemExit(f"reference CLI not found: {cli} (run `make cli` first)")

    doc = json.loads(CONTRACT.read_text())
    config_dir = (ROOT / doc["config"]).parent
    if not (ROOT / doc["config"]).is_file():
        raise SystemExit(f"contract config missing: {doc['config']}")

    failures = []
    for case in doc["cases"]:
        actual = run_case(cli, config_dir, case["argv"])
        if args.write:
            case["expect"] = actual
        elif actual != case["expect"]:
            failures.append((case, actual))

    if args.write:
        CONTRACT.write_text(json.dumps(doc, indent=2) + "\n")
        print(f"rewrote {len(doc['cases'])} cases in {CONTRACT.relative_to(ROOT)}")
        return 0

    for case, actual in failures:
        print(f"  FAIL  {' '.join(case['argv'])}  ({case['name']})", file=sys.stderr)
        print(f"        expected {json.dumps(case['expect'], sort_keys=True)}", file=sys.stderr)
        print(f"        actual   {json.dumps(actual, sort_keys=True)}", file=sys.stderr)

    if failures:
        print(
            f"\n{len(failures)}/{len(doc['cases'])} bundle contract cases failed.\n"
            "If the change was intentional, re-run with --write and review the diff.",
            file=sys.stderr,
        )
        return 1

    print(f"bundle contract: {len(doc['cases'])} cases match the reference parser")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
