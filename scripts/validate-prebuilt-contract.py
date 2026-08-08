#!/usr/bin/env python3
"""Validate the prebuilt target policy, schema, and any generated manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
PREBUILT_ROOT = ROOT / "prebuilt"
TARGETS_PATH = PREBUILT_ROOT / "targets.json"
SCHEMA_PATH = PREBUILT_ROOT / "manifest.schema.json"
DEFAULT_MANIFEST_PATH = PREBUILT_ROOT / "manifest.json"
TRIPLE = re.compile(r"^[a-z0-9_]+(?:-[a-z0-9_]+){2,3}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
EXPECTED_TIER_ONE = {
    "aarch64-apple-darwin",
    "x86_64-apple-darwin",
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
    "x86_64-unknown-linux-musl",
    "aarch64-unknown-linux-musl",
}
EXPECTED_EXPERIMENTAL = {"armv7-unknown-linux-gnueabihf"}
EXPECTED_ARTIFACT_KINDS = ("static", "shared")


def fail(message: str) -> None:
    print(f"prebuilt contract error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        display = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
        fail(f"cannot parse {display}: {exc}")
    if not isinstance(value, dict):
        display = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
        fail(f"{display} must contain a JSON object")
    return value


def require_nonempty_string(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{field} must be a nonempty string")
    return value


def require_sha256(value: object, field: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        fail(f"{field} must be 64 lowercase hexadecimal characters")
    return value


def expected_filename(target: str, kind: str) -> str:
    if kind == "static":
        return "libflags2env.a"
    if "apple-darwin" in target:
        return "libflags2env.dylib"
    return "libflags2env.so"


def validate_policy_and_schema() -> tuple[
    dict[str, Any], dict[str, Any], dict[str, dict[str, Any]]
]:
    policy = load(TARGETS_PATH)
    schema = load(SCHEMA_PATH)

    if policy.get("schema_version") != 1:
        fail("targets.json schema_version must be 1")
    if schema.get("properties", {}).get("schema_version", {}).get("const") != 1:
        fail("manifest schema must pin schema_version to 1")
    if policy.get("artifact_kinds") != list(EXPECTED_ARTIFACT_KINDS):
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

    target_by_triple: dict[str, dict[str, Any]] = {}
    tier_one: set[str] = set()
    experimental: set[str] = set()
    for entry in targets:
        if not isinstance(entry, dict):
            fail("every target entry must be an object")
        triple = entry.get("triple")
        if not isinstance(triple, str) or not TRIPLE.fullmatch(triple):
            fail(f"invalid canonical target triple: {triple!r}")
        if triple in target_by_triple:
            fail(f"duplicate target triple: {triple}")
        target_by_triple[triple] = entry

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
        isinstance(item, str) and TRIPLE.fullmatch(item) for item in deferred
    ):
        fail("deferred_targets must be an array of canonical target strings")
    if len(set(deferred)) != len(deferred):
        fail("deferred_targets must not contain duplicates")
    overlap = set(target_by_triple).intersection(deferred)
    if overlap:
        fail(f"targets cannot be both active and deferred: {sorted(overlap)}")

    top_required = set(schema.get("required", []))
    required_top_fields = {
        "schema_version",
        "package_version",
        "abi_version",
        "source_commit",
        "source_input_sha256",
        "source_date_epoch",
        "artifacts",
    }
    if not required_top_fields.issubset(top_required):
        fail(
            "manifest schema lacks required top-level fields: "
            f"{sorted(required_top_fields - top_required)}"
        )

    artifacts_schema = schema.get("properties", {}).get("artifacts", {})
    expected_minimum = len(EXPECTED_TIER_ONE) * len(EXPECTED_ARTIFACT_KINDS)
    if artifacts_schema.get("minItems") != expected_minimum:
        fail(f"manifest schema artifacts.minItems must be {expected_minimum}")
    if artifacts_schema.get("uniqueItems") is not True:
        fail("manifest schema artifacts must enable uniqueItems")

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
        "sdk_or_sysroot",
        "compile_flags",
    }
    if not required_fields.issubset(required):
        fail(
            "manifest artifact schema lacks required fields: "
            f"{sorted(required_fields - required)}"
        )

    artifact_properties = artifact.get("properties", {})
    for optional_string in ("soname_or_install_name", "provenance", "signature"):
        if artifact_properties.get(optional_string, {}).get("type") != "string":
            fail(f"{optional_string} must be omitted when absent, never encoded as null")
    if artifact_properties.get("sdk_or_sysroot", {}).get("type") != "string":
        fail("sdk_or_sysroot must be a non-null string")
    if not artifact.get("allOf"):
        fail("artifact schema must conditionally require shared-library identity")

    return policy, schema, target_by_triple


def validate_manifest(
    manifest_path: pathlib.Path,
    policy: dict[str, Any],
    schema: dict[str, Any],
    target_by_triple: dict[str, dict[str, Any]],
) -> None:
    manifest = load(manifest_path)
    allowed_top = set(schema.get("properties", {}))
    unknown_top = set(manifest) - allowed_top
    if unknown_top:
        fail(f"manifest has unknown top-level fields: {sorted(unknown_top)}")

    if manifest.get("schema_version") != 1:
        fail("manifest schema_version must be 1")
    require_nonempty_string(manifest.get("package_version"), "package_version")
    abi_version = manifest.get("abi_version")
    if not isinstance(abi_version, int) or isinstance(abi_version, bool) or abi_version < 1:
        fail("abi_version must be a positive integer")
    source_commit = manifest.get("source_commit")
    if not isinstance(source_commit, str) or not COMMIT.fullmatch(source_commit):
        fail("source_commit must be 40 lowercase hexadecimal characters")
    require_sha256(manifest.get("source_input_sha256"), "source_input_sha256")
    source_date_epoch = manifest.get("source_date_epoch")
    if (
        not isinstance(source_date_epoch, int)
        or isinstance(source_date_epoch, bool)
        or source_date_epoch < 0
    ):
        fail("source_date_epoch must be a nonnegative integer")

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        fail("artifacts must be an array")

    artifact_schema = schema["$defs"]["artifact"]
    required_artifact_fields = set(artifact_schema["required"])
    allowed_artifact_fields = set(artifact_schema["properties"])
    max_file_bytes = policy["budgets"]["max_file_bytes"]
    seen: set[tuple[str, str]] = set()
    total_bytes = 0

    for index, artifact in enumerate(artifacts):
        label = f"artifacts[{index}]"
        if not isinstance(artifact, dict):
            fail(f"{label} must be an object")
        missing = required_artifact_fields - set(artifact)
        if missing:
            fail(f"{label} lacks required fields: {sorted(missing)}")
        unknown = set(artifact) - allowed_artifact_fields
        if unknown:
            fail(f"{label} has unknown fields: {sorted(unknown)}")
        for field in ("soname_or_install_name", "provenance", "signature"):
            if field in artifact:
                require_nonempty_string(artifact[field], f"{label}.{field}")

        target = require_nonempty_string(artifact.get("target"), f"{label}.target")
        if target not in target_by_triple:
            fail(f"{label}.target is not active in targets.json: {target}")
        kind = artifact.get("kind")
        if kind not in EXPECTED_ARTIFACT_KINDS:
            fail(f"{label}.kind must be static or shared")
        identity = (target, kind)
        if identity in seen:
            fail(f"duplicate artifact identity: {target}/{kind}")
        seen.add(identity)

        expected_path = f"prebuilt/{target}/{expected_filename(target, kind)}"
        if artifact.get("path") != expected_path:
            fail(f"{label}.path must be {expected_path!r}")
        if artifact.get("minimum_runtime") != target_by_triple[target]["minimum_runtime"]:
            fail(
                f"{label}.minimum_runtime must match targets.json for {target}: "
                f"{target_by_triple[target]['minimum_runtime']!r}"
            )

        size = artifact.get("size")
        if (
            not isinstance(size, int)
            or isinstance(size, bool)
            or size < 1
            or size > max_file_bytes
        ):
            fail(f"{label}.size must be between 1 and {max_file_bytes}")
        total_bytes += size
        require_sha256(artifact.get("sha256"), f"{label}.sha256")
        require_sha256(
            artifact.get("exported_symbols_sha256"),
            f"{label}.exported_symbols_sha256",
        )

        for field in ("compiler", "linker", "archiver", "sdk_or_sysroot"):
            require_nonempty_string(artifact.get(field), f"{label}.{field}")
        compile_flags = artifact.get("compile_flags")
        if not isinstance(compile_flags, list) or not all(
            isinstance(flag, str) for flag in compile_flags
        ):
            fail(f"{label}.compile_flags must be an array of strings")
        if len(set(compile_flags)) != len(compile_flags):
            fail(f"{label}.compile_flags must not contain duplicates")

        if kind == "shared":
            require_nonempty_string(
                artifact.get("soname_or_install_name"),
                f"{label}.soname_or_install_name",
            )
        elif "soname_or_install_name" in artifact:
            fail(f"{label}.soname_or_install_name is invalid for a static library")

        artifact_path = (ROOT / expected_path).resolve()
        prebuilt_root = PREBUILT_ROOT.resolve()
        if not artifact_path.is_relative_to(prebuilt_root):
            fail(f"{label}.path escapes prebuilt/")
        if artifact_path.is_symlink():
            fail(f"{label}.path must not be a symlink")
        if not artifact_path.is_file():
            fail(f"{label}.path does not exist: {expected_path}")
        payload = artifact_path.read_bytes()
        if len(payload) != size:
            fail(f"{label}.size does not match {expected_path}")
        actual_sha256 = hashlib.sha256(payload).hexdigest()
        if actual_sha256 != artifact["sha256"]:
            fail(f"{label}.sha256 does not match {expected_path}")

    required_matrix = {
        (target, kind)
        for target in EXPECTED_TIER_ONE
        for kind in EXPECTED_ARTIFACT_KINDS
    }
    missing_matrix = required_matrix - seen
    if missing_matrix:
        fail(
            "manifest lacks Tier 1 artifacts: "
            + ", ".join(f"{target}/{kind}" for target, kind in sorted(missing_matrix))
        )
    if total_bytes > policy["budgets"]["max_tree_bytes"]:
        fail(
            f"manifest artifact bytes exceed max_tree_bytes: {total_bytes} > "
            f"{policy['budgets']['max_tree_bytes']}"
        )

    print(
        "validated prebuilt manifest: "
        f"{len(artifacts)} artifacts, {total_bytes} bytes, "
        f"ABI {abi_version}, source {source_commit[:12]}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=pathlib.Path,
        default=DEFAULT_MANIFEST_PATH,
        help="manifest to validate (default: prebuilt/manifest.json)",
    )
    parser.add_argument(
        "--require-manifest",
        action="store_true",
        help="fail when the selected manifest does not exist",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    policy, schema, target_by_triple = validate_policy_and_schema()
    tier_one_count = sum(entry["tier"] == 1 for entry in target_by_triple.values())
    experimental_count = sum(entry["tier"] == 2 for entry in target_by_triple.values())
    print(
        "validated prebuilt contract: "
        f"{tier_one_count} Tier 1 targets, "
        f"{experimental_count} experimental target, "
        "static+shared artifacts, reviewed size/history budgets"
    )

    manifest_path = args.manifest
    if not manifest_path.is_absolute():
        manifest_path = ROOT / manifest_path
    if manifest_path.exists():
        validate_manifest(manifest_path, policy, schema, target_by_triple)
    elif args.require_manifest:
        fail(f"required manifest does not exist: {manifest_path}")


if __name__ == "__main__":
    main()
