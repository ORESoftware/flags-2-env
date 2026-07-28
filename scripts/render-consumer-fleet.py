#!/usr/bin/env python3
"""Validate consumer-fleet.json and render a GitHub Actions matrix.

The fleet file is intentionally data-only.  This script fails closed on unsafe
repository names, paths, command basenames, duplicate contracts, unsorted
entries, unsupported kinds, and mutable tooling references before any dynamic
checkout occurs.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
COMMAND = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
KINDS = {"cli", "server", "worker", "mcp"}
REQUIRED_FIELDS = {"repository", "contract", "command", "kind"}


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"consumer fleet: {message}")


def read_document(path: Path) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing fleet file: {path}")
    except json.JSONDecodeError as error:
        fail(f"invalid JSON in {path}: {error}")
    if not isinstance(document, dict):
        fail("root must be a JSON object")
    return document


def validate_contract_path(value: str, index: int) -> None:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or value.endswith("/"):
        fail(f"entry {index}: contract must be a non-empty relative file path")
    if any(part in {"", ".", ".."} for part in path.parts):
        fail(f"entry {index}: unsafe contract path {value!r}")
    if path.name != ".cli-flags.toml":
        fail(f"entry {index}: contract must name .cli-flags.toml, got {value!r}")


def validate(path: Path) -> tuple[str, list[dict[str, str]]]:
    document = read_document(path)
    if document.get("schema_version") != 1:
        fail("schema_version must be 1")

    tooling_ref = document.get("tooling_ref")
    if not isinstance(tooling_ref, str) or not FULL_SHA.fullmatch(tooling_ref):
        fail("tooling_ref must be one full lowercase commit SHA")

    raw_consumers = document.get("consumers")
    if not isinstance(raw_consumers, list) or not raw_consumers:
        fail("consumers must be a non-empty array")

    consumers: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for index, raw in enumerate(raw_consumers):
        if not isinstance(raw, dict):
            fail(f"entry {index}: expected an object")
        if set(raw) != REQUIRED_FIELDS:
            missing = sorted(REQUIRED_FIELDS - set(raw))
            extra = sorted(set(raw) - REQUIRED_FIELDS)
            fail(f"entry {index}: fields mismatch; missing={missing}, extra={extra}")
        if not all(isinstance(raw[field], str) for field in REQUIRED_FIELDS):
            fail(f"entry {index}: every field must be a string")

        repository = raw["repository"]
        contract = raw["contract"]
        command = raw["command"]
        kind = raw["kind"]
        if not REPOSITORY.fullmatch(repository):
            fail(f"entry {index}: unsafe repository {repository!r}")
        validate_contract_path(contract, index)
        if not COMMAND.fullmatch(command):
            fail(f"entry {index}: unsafe command basename {command!r}")
        if kind not in KINDS:
            fail(f"entry {index}: unsupported kind {kind!r}")

        key = (repository.casefold(), contract)
        if key in seen:
            fail(f"entry {index}: duplicate consumer {repository}:{contract}")
        seen.add(key)
        consumers.append(
            {
                "repository": repository,
                "contract": contract,
                "command": command,
                "kind": kind,
                "label": f"{repository}:{contract}",
            }
        )

    expected = sorted(consumers, key=lambda item: (item["repository"], item["contract"]))
    if consumers != expected:
        fail("consumers must be sorted by repository and contract")
    return tooling_ref, consumers


def append_output(path: Path, name: str, value: str) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"{name}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fleet", default="consumer-fleet.json", type=Path)
    parser.add_argument(
        "--github-output",
        type=Path,
        default=Path(os.environ["GITHUB_OUTPUT"]) if "GITHUB_OUTPUT" in os.environ else None,
    )
    parser.add_argument("--print", action="store_true", dest="print_matrix")
    args = parser.parse_args()

    tooling_ref, consumers = validate(args.fleet)
    matrix = json.dumps({"include": consumers}, separators=(",", ":"), sort_keys=True)
    if args.github_output:
        append_output(args.github_output, "matrix", matrix)
        append_output(args.github_output, "tooling_ref", tooling_ref)
        append_output(args.github_output, "consumer_count", str(len(consumers)))
    if args.print_matrix or not args.github_output:
        print(matrix)
    print(
        f"validated {len(consumers)} flags2env consumer contracts at tooling {tooling_ref}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
