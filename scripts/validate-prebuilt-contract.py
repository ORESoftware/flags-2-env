#!/usr/bin/env python3
"""Validate the committed prebuilt target policy without third-party modules."""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGETS_PATH = ROOT / "prebuilt" / "targets.json"
SCHEMA_PATH = ROOT / "prebuilt" / "manifest.schema.json"
TRIPLE = re.compile(r"^[a-z0-9_]+(?:-[a-z0-9_]+){2,3}$")
EXPECTED_TIER_ONE = {
    "aarch64-apple-darwin",
    "x86_64-apple-darwin",
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
    "x86_64-unknown-linux-musl",
    "aarch64-unknown-linux-musl",
}
EXPECTED_EXPERIMENTAL = {"armv7-unknown-linux-gnueabihf"}


def fail(message: str) -> None:
    print(f"prebuilt contract error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load(path: pathlib.Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot parse {path.relative_to(ROOT)}: {exc}")
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def main() -> None:
    policy = load(TARGETS_PATH)
    schema = load(SCHEMA_PATH)

    if policy.get("schema_version") != 1:
        fail("targets.json schema_version must be 1")
    if schema.get("properties", {}).get("schema_version", {}).get("const") != 1:
        fail("manifest schema must pin schema_version to 1")
    if policy.get("artifact_kinds") != ["static", "shared"]:
        fail("Tier 1 must initially publish static and shared artifacts")

    budgets = policy.get("budgets")
    expected_budgets = {
        "max_file_bytes": 1_048_576,
        "max_tree_bytes": 10_485_760,
        "max_history_growth_per_release_bytes": 5_242_880,
    }
    if budgets != expected_budgets:
        fail(f"budgets must remain the reviewed starting values: {expected_budgets}")

    targets = policy.get("targets")
    if not isinstance(targets, list):
        fail("targets must be an array")

    seen: set[str] = set()
    tier_one: set[str] = set()
    experimental: set[str] = set()
    for entry in targets:
        if not isinstance(entry, dict):
            fail("every target entry must be an object")
        triple = entry.get("triple")
        if not isinstance(triple, str) or not TRIPLE.fullmatch(triple):
            fail(f"invalid canonical target triple: {triple!r}")
        if triple in seen:
            fail(f"duplicate target triple: {triple}")
        seen.add(triple)

        tier = entry.get("tier")
        minimum_runtime = entry.get("minimum_runtime")
        if not isinstance(minimum_runtime, str) or not minimum_runtime.strip():
            fail(f"{triple} must declare a minimum runtime")
        if tier == 1:
            owner = entry.get("fixture_owner")
            if not isinstance(owner, str) or not owner.strip():
                fail(f"Tier 1 target {triple} must name a runtime fixture owner")
            tier_one.add(triple)
        elif tier == 2:
            experimental.add(triple)
        else:
            fail(f"{triple} has unsupported tier {tier!r}")

    if tier_one != EXPECTED_TIER_ONE:
        fail(f"Tier 1 target set drifted: {sorted(tier_one)}")
    if experimental != EXPECTED_EXPERIMENTAL:
        fail(f"experimental target set drifted: {sorted(experimental)}")

    deferred = policy.get("deferred_targets")
    if not isinstance(deferred, list) or not all(
        isinstance(item, str) for item in deferred
    ):
        fail("deferred_targets must be an array of canonical target strings")
    overlap = seen.intersection(deferred)
    if overlap:
        fail(f"targets cannot be both active and deferred: {sorted(overlap)}")

    artifact = schema.get("$defs", {}).get("artifact", {})
    required = set(artifact.get("required", []))
    required_fields = {
        "target",
        "kind",
        "path",
        "size",
        "sha256",
        "exported_symbols_sha256",
        "minimum_runtime",
        "compiler",
        "linker",
        "archiver",
        "compile_flags",
    }
    if not required_fields.issubset(required):
        fail(
            "manifest artifact schema lacks required fields: "
            f"{sorted(required_fields - required)}"
        )

    print(
        "validated prebuilt contract: "
        f"{len(tier_one)} Tier 1 targets, "
        f"{len(experimental)} experimental target, "
        "static+shared artifacts, reviewed size/history budgets"
    )


if __name__ == "__main__":
    main()
