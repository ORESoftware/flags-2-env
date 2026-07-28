#!/usr/bin/env python3
"""Validate consumer-fleet.json and render a GitHub Actions matrix.

The fleet file is intentionally data-only. This script fails closed on unsafe
repository names, paths, command basenames, duplicate contracts, unsorted
entries, unsupported kinds, mutable tooling references, and malformed in-repo
evidence before any dynamic checkout occurs.

Public/reachable contracts are rendered into the central read-only matrix.
Private contracts remain explicit fleet members but must point at a dedicated
in-repository workflow and pull request where the repository's own token can
perform the checkout and execute the immutable reusable compliance workflow.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any, NoReturn

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
COMMAND = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
PULL_REQUEST = re.compile(
    r"^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)$"
)
KINDS = {"cli", "server", "worker", "mcp"}
VERIFICATION_MODES = {"central", "in-repo"}
CORE_FIELDS = {"repository", "contract", "command", "kind"}
IN_REPO_FIELDS = CORE_FIELDS | {"verification", "workflow", "evidence_pr"}


def fail(message: str) -> NoReturn:
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


def validate_relative_path(value: str, index: int, label: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or value.endswith("/"):
        fail(f"entry {index}: {label} must be a non-empty relative file path")
    if any(part in {"", ".", ".."} for part in path.parts):
        fail(f"entry {index}: unsafe {label} path {value!r}")
    return path


def validate_contract_path(value: str, index: int) -> None:
    path = validate_relative_path(value, index, "contract")
    if path.name != ".cli-flags.toml":
        fail(f"entry {index}: contract must name .cli-flags.toml, got {value!r}")


def validate_workflow_path(value: str, index: int) -> None:
    path = validate_relative_path(value, index, "workflow")
    if len(path.parts) < 3 or path.parts[:2] != (".github", "workflows"):
        fail(
            f"entry {index}: in-repo workflow must be under .github/workflows, "
            f"got {value!r}"
        )
    if path.suffix not in {".yml", ".yaml"}:
        fail(f"entry {index}: in-repo workflow must be YAML, got {value!r}")


def validate_evidence_pr(value: str, repository: str, index: int) -> None:
    match = PULL_REQUEST.fullmatch(value)
    if not match:
        fail(f"entry {index}: evidence_pr must be a canonical GitHub pull request URL")
    evidence_repository = f"{match.group(1)}/{match.group(2)}"
    if evidence_repository.casefold() != repository.casefold():
        fail(
            f"entry {index}: evidence_pr repository {evidence_repository!r} does not "
            f"match consumer {repository!r}"
        )


def validate(
    path: Path,
) -> tuple[str, list[dict[str, str]], list[dict[str, str]]]:
    document = read_document(path)
    if document.get("schema_version") != 1:
        fail("schema_version must be 1")

    tooling_ref = document.get("tooling_ref")
    if not isinstance(tooling_ref, str) or not FULL_SHA.fullmatch(tooling_ref):
        fail("tooling_ref must be one full lowercase commit SHA")

    raw_consumers = document.get("consumers")
    if not isinstance(raw_consumers, list) or not raw_consumers:
        fail("consumers must be a non-empty array")

    central_consumers: list[dict[str, str]] = []
    in_repo_consumers: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    observed_order: list[tuple[str, str]] = []

    for index, raw in enumerate(raw_consumers):
        if not isinstance(raw, dict):
            fail(f"entry {index}: expected an object")

        verification = raw.get("verification", "central")
        if not isinstance(verification, str) or verification not in VERIFICATION_MODES:
            fail(f"entry {index}: unsupported verification mode {verification!r}")

        required = IN_REPO_FIELDS if verification == "in-repo" else CORE_FIELDS
        allowed = required if verification == "in-repo" else CORE_FIELDS | {"verification"}
        missing = sorted(required - set(raw))
        extra = sorted(set(raw) - allowed)
        if missing or extra:
            fail(f"entry {index}: fields mismatch; missing={missing}, extra={extra}")
        if not all(isinstance(raw[field], str) for field in required):
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
        observed_order.append((repository, contract))

        consumer = {
            "repository": repository,
            "contract": contract,
            "command": command,
            "kind": kind,
            "label": f"{repository}:{contract}",
        }
        if verification == "in-repo":
            workflow = raw["workflow"]
            evidence_pr = raw["evidence_pr"]
            validate_workflow_path(workflow, index)
            validate_evidence_pr(evidence_pr, repository, index)
            in_repo_consumers.append(
                {
                    **consumer,
                    "verification": verification,
                    "workflow": workflow,
                    "evidence_pr": evidence_pr,
                }
            )
        else:
            central_consumers.append(consumer)

    if observed_order != sorted(observed_order):
        fail("consumers must be sorted by repository and contract")
    if not central_consumers:
        fail("at least one centrally verifiable consumer is required")
    return tooling_ref, central_consumers, in_repo_consumers


def append_output(path: Path, name: str, value: str) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"{name}={value}\n")


def compact_json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


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

    tooling_ref, central_consumers, in_repo_consumers = validate(args.fleet)
    matrix = compact_json({"include": central_consumers})
    total = len(central_consumers) + len(in_repo_consumers)
    if args.github_output:
        append_output(args.github_output, "matrix", matrix)
        append_output(args.github_output, "tooling_ref", tooling_ref)
        append_output(args.github_output, "consumer_count", str(total))
        append_output(args.github_output, "central_count", str(len(central_consumers)))
        append_output(args.github_output, "in_repo_count", str(len(in_repo_consumers)))
        append_output(
            args.github_output,
            "in_repo_evidence",
            compact_json(in_repo_consumers),
        )
    if args.print_matrix or not args.github_output:
        print(matrix)
    print(
        f"validated {total} flags2env consumer contracts at tooling {tooling_ref} "
        f"({len(central_consumers)} central, {len(in_repo_consumers)} in-repo)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
