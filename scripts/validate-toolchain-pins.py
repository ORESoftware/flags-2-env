#!/usr/bin/env python3
"""Validate release-producing compiler/toolchain pins without network access."""

from __future__ import annotations

import json
import pathlib
import re
import sys
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parents[1]
PIN_PATH = ROOT / "toolchains" / "zig-0.16.0-linux.json"
TARGETS_PATH = ROOT / "prebuilt" / "targets.json"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MINISIGN_PUBLIC_KEY = re.compile(r"^RW[A-Za-z0-9+/]{48,}={0,2}$")
EXPECTED_HOSTS = {
    "x86_64-unknown-linux-gnu": (
        "zig-x86_64-linux-0.16.0.tar.xz",
        "70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00",
    ),
    "aarch64-unknown-linux-gnu": (
        "zig-aarch64-linux-0.16.0.tar.xz",
        "ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17",
    ),
}
EXPECTED_TARGETS = {
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
    "x86_64-unknown-linux-musl",
    "aarch64-unknown-linux-musl",
}


def fail(message: str) -> "NoReturn":
    print(f"toolchain pin error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load(path: pathlib.Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot parse {path.relative_to(ROOT)}: {exc}")
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} must contain an object")
    return value


def require_https_ziglang(field: str, value: object) -> str:
    if not isinstance(value, str):
        fail(f"{field} must be a string")
    parsed = urlparse(value)
    if (
        parsed.scheme != "https"
        or parsed.hostname != "ziglang.org"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        fail(f"{field} must be an uncredentialed ziglang.org HTTPS URL")
    return value


def main() -> None:
    pin = load(PIN_PATH)
    target_policy = load(TARGETS_PATH)

    if pin.get("schema_version") != 1:
        fail("schema_version must be 1")
    if pin.get("tool") != "zig" or pin.get("version") != "0.16.0":
        fail("release tool must remain exactly Zig 0.16.0")
    if pin.get("release_date") != "2026-04-13":
        fail("unexpected Zig 0.16.0 release date")
    require_https_ziglang("release_index", pin.get("release_index"))

    public_key = pin.get("minisign_public_key")
    if not isinstance(public_key, str) or not MINISIGN_PUBLIC_KEY.fullmatch(public_key):
        fail("invalid Zig minisign public key shape")

    hosts = pin.get("hosts")
    if not isinstance(hosts, list) or len(hosts) != len(EXPECTED_HOSTS):
        fail("hosts must contain exactly the reviewed Linux x86_64 and aarch64 pins")

    seen: set[str] = set()
    for entry in hosts:
        if not isinstance(entry, dict):
            fail("host entry must be an object")
        host = entry.get("host")
        if host not in EXPECTED_HOSTS or host in seen:
            fail(f"unexpected or duplicate host: {host!r}")
        seen.add(host)
        archive, digest = EXPECTED_HOSTS[host]
        if entry.get("archive") != archive or entry.get("sha256") != digest:
            fail(f"{host} archive or digest drifted")
        if not SHA256.fullmatch(str(entry.get("sha256", ""))):
            fail(f"{host} has invalid SHA-256")
        url = require_https_ziglang(f"hosts[{host}].url", entry.get("url"))
        signature = require_https_ziglang(
            f"hosts[{host}].minisig_url", entry.get("minisig_url")
        )
        expected_url = f"https://ziglang.org/download/0.16.0/{archive}"
        if url != expected_url or signature != expected_url + ".minisig":
            fail(f"{host} URL or signature URL is not canonical")

    release_targets = set(pin.get("release_targets", []))
    if release_targets != EXPECTED_TARGETS:
        fail(f"release target set drifted: {sorted(release_targets)}")

    tier_one = {
        item.get("triple")
        for item in target_policy.get("targets", [])
        if isinstance(item, dict) and item.get("tier") == 1
    }
    if not EXPECTED_TARGETS.issubset(tier_one):
        fail("toolchain release targets must be Tier 1 in prebuilt/targets.json")

    expected_policy = {
        "require_sha256": True,
        "require_minisign": True,
        "allow_floating_version": False,
        "allow_package_manager_install_for_release": False,
        "extract_only_after_verification": True,
        "darwin_release_artifacts_use_native_xcode_clang": True,
    }
    if pin.get("policy") != expected_policy:
        fail("release verification policy drifted")

    print(
        "validated Zig 0.16.0 pins: 2 Linux hosts, 4 release targets, "
        "SHA-256 + minisign required"
    )


if __name__ == "__main__":
    main()
