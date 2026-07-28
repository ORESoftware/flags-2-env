#!/usr/bin/env python3
"""Static policy checks for repositories consuming flags-2-env.

The canonical C audit remains the source of truth for contract syntax and parser
semantics. This companion check enforces cross-repository adoption policy:
immutable pins, strict unknown-option handling, and secret-only environment
variables staying out of the flag surface.
"""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

PIN_RE = re.compile(r"^[0-9a-f]{40}$")
ENV_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SECRET_RE = re.compile(
    r"(?:^|_)(?:TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE_KEY|SIGNING_KEY|"
    r"ENCRYPTION_KEY|API_KEY|ACCESS_KEY|CLIENT_SECRET|DATABASE_URL|DB_URL|"
    r"DSN|CREDENTIALS?|AUTH_HEADER|COOKIE|SESSION)(?:_|$)"
)
EXACT_SECRET_ENVS = {
    "OTEL_EXPORTER_OTLP_HEADERS",
    "OTEL_EXPORTER_OTLP_TRACES_HEADERS",
}
UPSTREAM_GIT = "https://github.com/ORESoftware/flags-2-env.git"


@dataclass(frozen=True)
class Flag:
    path: str
    env: str
    default_present: bool


def fail(message: str) -> None:
    print(f"flags2env compliance: {message}", file=sys.stderr)


def safe_child(root: Path, relative: str, label: str) -> Path:
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"{label} escapes the repository root") from exc
    if not candidate.is_file():
        raise ValueError(f"{label} does not exist: {relative}")
    return candidate


def iter_flag_tables(container: Any, prefix: str) -> Iterable[Flag]:
    if not isinstance(container, dict):
        return
    flags = container.get("flags", {})
    if isinstance(flags, dict):
        for name, spec in flags.items():
            if not isinstance(spec, dict):
                continue
            env = spec.get("env")
            if isinstance(env, str):
                yield Flag(f"{prefix}flags.{name}", env, "default" in spec)
    commands = container.get("commands", {})
    if isinstance(commands, dict):
        for name, command in commands.items():
            if isinstance(command, dict):
                yield from iter_flag_tables(command, f"{prefix}commands.{name}.")


def find_flags2env_dependency(manifest: dict[str, Any]) -> Any:
    locations = [
        manifest.get("dependencies", {}),
        manifest.get("build-dependencies", {}),
        manifest.get("dev-dependencies", {}),
        manifest.get("workspace", {}).get("dependencies", {})
        if isinstance(manifest.get("workspace"), dict)
        else {},
    ]
    for table in locations:
        if isinstance(table, dict) and "flags2env" in table:
            return table["flags2env"]
    return None


def check_rust_pin(root: Path, manifest_path: str, lock_path: str, parser_ref: str) -> list[str]:
    errors: list[str] = []
    try:
        manifest_file = safe_child(root, manifest_path, "Rust manifest")
        lock_file = safe_child(root, lock_path, "Cargo lockfile")
    except ValueError as error:
        return [str(error)]

    with manifest_file.open("rb") as handle:
        manifest = tomllib.load(handle)
    dependency = find_flags2env_dependency(manifest)
    if not isinstance(dependency, dict):
        errors.append("Cargo.toml must declare flags2env as a git table with an immutable rev")
    else:
        if dependency.get("git") != UPSTREAM_GIT:
            errors.append(f"flags2env git source must be {UPSTREAM_GIT}")
        if dependency.get("rev") != parser_ref:
            errors.append("flags2env Cargo rev must exactly match parser_ref")
        if any(key in dependency for key in ("branch", "tag", "version")):
            errors.append("flags2env dependency must not combine rev with branch, tag, or version")

    lock_text = lock_file.read_text(encoding="utf-8")
    if UPSTREAM_GIT not in lock_text or parser_ref not in lock_text:
        errors.append("Cargo.lock does not contain the exact flags2env git revision")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--contract", default=".cli-flags.toml")
    parser.add_argument("--parser-ref", required=True)
    parser.add_argument("--kind", choices=("server", "mcp", "cli", "worker"), required=True)
    parser.add_argument("--rust-manifest")
    parser.add_argument("--cargo-lock", default="Cargo.lock")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    errors: list[str] = []
    if not PIN_RE.fullmatch(args.parser_ref):
        errors.append("parser_ref must be a full 40-character lowercase commit SHA")

    try:
        contract_path = safe_child(root, args.contract, "contract")
    except ValueError as error:
        fail(str(error))
        return 1

    try:
        with contract_path.open("rb") as handle:
            contract = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as error:
        fail(f"cannot parse contract with Python tomllib: {error}")
        return 1

    parse = contract.get("parse", {})
    if isinstance(parse, dict) and parse.get("allow_unknown") is True:
        errors.append("parse.allow_unknown must be false or omitted for compliant executables")

    flags = list(iter_flag_tables(contract, ""))
    if not flags:
        errors.append("contract declares no process-level flags")

    seen_envs: dict[str, str] = {}
    for flag in flags:
        if not ENV_RE.fullmatch(flag.env):
            errors.append(f"{flag.path} uses invalid env name {flag.env!r}")
            continue
        previous = seen_envs.setdefault(flag.env, flag.path)
        if previous != flag.path:
            errors.append(f"{flag.path} and {previous} both map to {flag.env}")
        if flag.env in EXACT_SECRET_ENVS or SECRET_RE.search(flag.env):
            errors.append(f"{flag.path} exposes secret-bearing env {flag.env}; keep it environment-only")
        if flag.default_present and (flag.env in EXACT_SECRET_ENVS or SECRET_RE.search(flag.env)):
            errors.append(f"{flag.path} gives secret-bearing env {flag.env} a default")

    env_policy = contract.get("env", {})
    ignored = env_policy.get("ignore", []) if isinstance(env_policy, dict) else []
    if ignored and not isinstance(ignored, list):
        errors.append("env.ignore must be a TOML array")
    elif isinstance(ignored, list):
        invalid_ignored = [value for value in ignored if not isinstance(value, str) or not ENV_RE.fullmatch(value)]
        if invalid_ignored:
            errors.append("env.ignore contains non-string or invalid environment names")

    if args.rust_manifest:
        errors.extend(check_rust_pin(root, args.rust_manifest, args.cargo_lock, args.parser_ref))

    if errors:
        for error in errors:
            fail(error)
        return 1

    print(
        "flags2env compliance: ok "
        f"kind={args.kind} flags={len(flags)} parser_ref={args.parser_ref}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
