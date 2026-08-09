#!/usr/bin/env python3
"""Validate the dual-GitHub source contract without changing either remote."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tomllib
from datetime import date
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "docs" / "source-migration.json"
SCHEMA_PATH = ROOT / "docs" / "source-migration.schema.json"

CANONICAL_GIT = "https://github.com/flags-2-env/flags-2-env.git"
CANONICAL_WEB = "https://github.com/flags-2-env/flags-2-env"
COMPATIBILITY_GIT = "https://github.com/ORESoftware/flags-2-env.git"
COMPATIBILITY_WEB = "https://github.com/ORESoftware/flags-2-env"

EXPECTED_TOP_LEVEL_KEYS = {
    "$schema",
    "schemaVersion",
    "canonical",
    "compatibility",
    "zedPackage",
    "publicationOrder",
}
LEGACY_REFERENCE_ALLOWLIST = {
    "README.md",
    "docs/source-migration.json",
    "docs/source-migration.md",
    "docs/source-migration.schema.json",
    "docs/consumer-compliance.md",
    "scripts/verify-consumer-compliance.py",
    "scripts/verify-source-migration.py",
    "tests/compliance/run.sh",
    "tests/test_consumer_fleet.py",
    "tests/test_consumer_compliance_policy.py",
}


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def expect_object(
    value: Any, name: str, expected_keys: set[str], errors: list[str]
) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{name} must be an object")
        return {}
    actual_keys = set(value)
    if actual_keys != expected_keys:
        missing = sorted(expected_keys - actual_keys)
        extra = sorted(actual_keys - expected_keys)
        errors.append(f"{name} keys differ: missing={missing} extra={extra}")
    return value


def tracked_files() -> list[Path]:
    completed = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [ROOT / item.decode() for item in completed.stdout.split(b"\0") if item]


def validate_metadata() -> list[str]:
    errors: list[str] = []
    manifest = load_json(MANIFEST_PATH)
    schema = load_json(SCHEMA_PATH)

    if set(manifest) != EXPECTED_TOP_LEVEL_KEYS:
        errors.append("source-migration.json has missing or unsupported top-level keys")
    if manifest.get("$schema") != SCHEMA_PATH.name:
        errors.append("source-migration.json must reference its repository-local schema")
    if manifest.get("schemaVersion") != "flags-2-env.source-migration.v1":
        errors.append("unsupported source migration schema version")
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        errors.append("source-migration.schema.json must use JSON Schema 2020-12")
    if schema.get("$id") != f"{CANONICAL_WEB}/blob/main/docs/{SCHEMA_PATH.name}":
        errors.append("source migration schema $id must use the canonical repository")

    canonical = expect_object(
        manifest.get("canonical"), "canonical", {"repository", "web"}, errors
    )
    if canonical.get("repository") != CANONICAL_GIT:
        errors.append("canonical.repository is not the canonical Git URL")
    if canonical.get("web") != CANONICAL_WEB:
        errors.append("canonical.web is not the canonical web URL")

    compatibility = expect_object(
        manifest.get("compatibility"),
        "compatibility",
        {
            "repository",
            "web",
            "supportStartsOn",
            "supportEndsOn",
            "mode",
            "mirroredRefs",
        },
        errors,
    )
    if compatibility.get("repository") != COMPATIBILITY_GIT:
        errors.append("compatibility.repository is not the original Git URL")
    if compatibility.get("web") != COMPATIBILITY_WEB:
        errors.append("compatibility.web is not the original web URL")
    if compatibility.get("mode") != "commit-identical-mirror":
        errors.append("compatibility.mode must require a commit-identical mirror")
    if compatibility.get("mirroredRefs") != ["refs/heads/main", "refs/tags/*"]:
        errors.append("compatibility.mirroredRefs must cover main and every tag")
    try:
        start = date.fromisoformat(str(compatibility.get("supportStartsOn")))
        end = date.fromisoformat(str(compatibility.get("supportEndsOn")))
    except ValueError:
        errors.append("compatibility support dates must use YYYY-MM-DD")
    else:
        if start.isoformat() != "2026-08-09" or end.isoformat() != "2026-08-19":
            errors.append("compatibility support window must be 2026-08-09 through 2026-08-19")
        if (end - start).days != 10:
            errors.append("compatibility support boundary must be exactly ten days")

    zed_package = expect_object(
        manifest.get("zedPackage"),
        "zedPackage",
        {
            "version",
            "canonicalIdentity",
            "compatibilityIdentity",
            "aliasSupport",
            "compatibilityPublishMode",
            "repositoryAuthority",
        },
        errors,
    )
    if zed_package != {
        "version": "0.3.0",
        "canonicalIdentity": "flags-2-env/flags-2-env",
        "compatibilityIdentity": "oresoftware/flags-2-env",
        "aliasSupport": "unavailable",
        "compatibilityPublishMode": "single-field-manifest-overlay",
        "repositoryAuthority": "canonical",
    }:
        errors.append("Zed dual-publication policy differs from the reviewed contract")
    if manifest.get("publicationOrder") != ["canonical", "compatibility"]:
        errors.append("publication order must be canonical then compatibility")

    with (ROOT / ".zpkg.toml").open("rb") as handle:
        zpkg = tomllib.load(handle)
    package = zpkg.get("package", {})
    repository = package.get("repository", {}) if isinstance(package, dict) else {}
    if package.get("org") != "flags-2-env" or package.get("name") != "flags-2-env":
        errors.append(".zpkg.toml must declare canonical flags-2-env/flags-2-env")
    if package.get("version") != "0.3.0":
        errors.append(".zpkg.toml must release the hardened tip as 0.3.0")
    if repository.get("url") != CANONICAL_WEB:
        errors.append(".zpkg.toml repository URL must use the canonical source")

    with (ROOT / ".cli-flags.toml").open("rb") as handle:
        cli_flags = tomllib.load(handle)
    if cli_flags.get("help", {}).get("url") != CANONICAL_WEB:
        errors.append(".cli-flags.toml help URL must use the canonical source")
    formal = load_json(ROOT / "formal" / "fmctl.json")
    if formal.get("repoUrl") != CANONICAL_GIT:
        errors.append("formal/fmctl.json must use the canonical source")

    for path in tracked_files():
        relative = path.relative_to(ROOT).as_posix()
        try:
            contents = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if COMPATIBILITY_WEB in contents and relative not in LEGACY_REFERENCE_ALLOWLIST:
            errors.append(
                f"{relative} retains the compatibility URL outside the explicit allowlist"
            )

    return errors


def remote_refs(url: str) -> dict[str, str]:
    completed = subprocess.run(
        ["git", "ls-remote", "--refs", url, "refs/heads/main", "refs/tags/*"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if completed.returncode:
        detail = completed.stderr.strip() or f"git ls-remote exited {completed.returncode}"
        raise RuntimeError(f"cannot inspect {url}: {detail}")
    refs: dict[str, str] = {}
    for line in completed.stdout.splitlines():
        object_id, ref = line.split("\t", 1)
        refs[ref] = object_id
    return refs


def validate_remote_parity() -> list[str]:
    errors: list[str] = []
    try:
        canonical = remote_refs(CANONICAL_GIT)
        compatibility = remote_refs(COMPATIBILITY_GIT)
    except RuntimeError as error:
        return [str(error)]
    if "refs/heads/main" not in canonical:
        errors.append("canonical repository has no main branch")
    if "refs/heads/main" not in compatibility:
        errors.append("compatibility repository has no main branch")
    if canonical != compatibility:
        missing_compatibility = sorted(set(canonical) - set(compatibility))
        extra_compatibility = sorted(set(compatibility) - set(canonical))
        mismatched = sorted(
            ref
            for ref in set(canonical) & set(compatibility)
            if canonical[ref] != compatibility[ref]
        )
        errors.append(
            "remote ref parity failed: "
            f"missing_compatibility={missing_compatibility} "
            f"extra_compatibility={extra_compatibility} mismatched={mismatched}"
        )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check-remotes",
        action="store_true",
        help="compare canonical and compatibility main/tag object IDs",
    )
    args = parser.parse_args()

    try:
        errors = validate_metadata()
    except (OSError, ValueError, json.JSONDecodeError, tomllib.TOMLDecodeError) as error:
        errors = [str(error)]
    if args.check_remotes:
        errors.extend(validate_remote_parity())
    if errors:
        for error in errors:
            print(f"source migration: {error}", file=sys.stderr)
        return 1
    suffix = " + remote parity" if args.check_remotes else ""
    print(f"source migration: metadata valid{suffix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
