#!/usr/bin/env python3
"""DEN-2847: prebuilt manifest generator and deep verifier (stdlib only).

    manifest.py generate --staging <dir> [--out <path>]
    manifest.py verify   --manifest <path> --artifact-root <dir> [--rebuild]

`generate` turns a staging tree produced by `scripts/prebuilt/build.sh` into the
manifest defined by `prebuilt/manifest.schema.json`. Artifact `path` values are
always the canonical committed locations (`prebuilt/<triple>/lib...`), even when
the bytes still live in staging — committing them is DEN-2848.

`verify` re-derives every claim from the bytes rather than trusting the
manifest: size, SHA-256, exported-symbol digest, binary format/architecture,
platform floor (Mach-O `LC_BUILD_VERSION`/`LC_VERSION_MIN_MACOSX` minos and ELF
`GLIBC_x.y` version references are read out of the file), SONAME/install name,
and the source-input digest. `--rebuild` additionally rebuilds through the
pinned toolchain and compares digests before any signing step.

Deliberately stdlib-only and offline, matching `validate-prebuilt-contract.py`:
no llvm-readelf/otool dependency, so it runs identically on a laptop and a
minimal CI image.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import struct
import subprocess
import sys
from typing import Any, Iterable

ROOT = pathlib.Path(__file__).resolve().parents[2]
PREBUILT_ROOT = ROOT / "prebuilt"
TARGETS_PATH = PREBUILT_ROOT / "targets.json"
SCHEMA_VERSION = 1

# Inputs covered by source_input_sha256 (ADR: C sources, public/private headers,
# build scripts, target configuration, export maps, manifest-generation logic).
SOURCE_INPUT_GLOBS = (
    "src/*.c",
    "src/*.h",
    "Makefile",
    "prebuilt/targets.json",
    "prebuilt/manifest.schema.json",
    "scripts/prebuilt/build.sh",
    "scripts/prebuilt/toolchains.json",
    "scripts/prebuilt/manifest.py",
)

ELF_MACHINES = {0x3E: "x86_64", 0xB7: "aarch64", 0x28: "arm"}
MACHO_CPUTYPES = {0x0100000C: "aarch64", 0x01000007: "x86_64"}
TRIPLE_ARCH = {
    "aarch64-apple-darwin": "aarch64",
    "x86_64-apple-darwin": "x86_64",
    "x86_64-unknown-linux-gnu": "x86_64",
    "aarch64-unknown-linux-gnu": "aarch64",
    "x86_64-unknown-linux-musl": "x86_64",
    "aarch64-unknown-linux-musl": "aarch64",
    "armv7-unknown-linux-gnueabihf": "arm",
}

errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)
    print(f"  FAIL: {msg}")


def ok(msg: str) -> None:
    print(f"  ok: {msg}")


def sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_json(obj: Any) -> bytes:
    """Deterministic serialization: sorted keys, fixed separators, trailing LF."""
    return (json.dumps(obj, indent=2, sort_keys=True) + "\n").encode()


# --------------------------------------------------------------------------
# binary inspection (pure stdlib)
# --------------------------------------------------------------------------

def read_macho(data: bytes) -> dict[str, Any]:
    """64-bit little-endian Mach-O: arch, install name, minos, LC_UUID presence."""
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != 0xFEEDFACF:
        return {"format": None}
    cputype, _cpusub, _ft, ncmds = struct.unpack_from("<iiII", data, 4)
    info: dict[str, Any] = {
        "format": "macho",
        "arch": MACHO_CPUTYPES.get(cputype & 0xFFFFFFFF, f"cpu:{cputype}"),
        "install_name": None,
        "minos": None,
        "has_uuid": False,
    }
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x0D:  # LC_ID_DYLIB
            name_off = struct.unpack_from("<I", data, off + 8)[0]
            raw = data[off + name_off : off + cmdsize]
            info["install_name"] = raw.split(b"\x00", 1)[0].decode(errors="replace")
        elif cmd == 0x32:  # LC_BUILD_VERSION
            minos = struct.unpack_from("<I", data, off + 12)[0]
            info["minos"] = f"{(minos >> 16) & 0xFFFF}.{(minos >> 8) & 0xFF}"
        elif cmd == 0x24 and info["minos"] is None:  # LC_VERSION_MIN_MACOSX
            v = struct.unpack_from("<I", data, off + 8)[0]
            info["minos"] = f"{(v >> 16) & 0xFFFF}.{(v >> 8) & 0xFF}"
        elif cmd == 0x1B:  # LC_UUID
            info["has_uuid"] = True
        off += cmdsize
    return info


def read_elf(data: bytes) -> dict[str, Any]:
    """64/32-bit little-endian ELF: arch, SONAME, referenced GLIBC_x.y versions."""
    if data[:4] != b"\x7fELF":
        return {"format": None}
    is64 = data[4] == 2
    e_machine = struct.unpack_from("<H", data, 18)[0]
    info: dict[str, Any] = {
        "format": "elf",
        "arch": ELF_MACHINES.get(e_machine, f"machine:{e_machine}"),
        "soname": None,
        "glibc_max": None,
    }
    if is64:
        e_shoff, = struct.unpack_from("<Q", data, 40)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 58)
    else:
        e_shoff, = struct.unpack_from("<I", data, 32)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 46)
    if not e_shoff or not e_shnum:
        return info

    sections = []
    for i in range(e_shnum):
        base = e_shoff + i * e_shentsize
        if is64:
            name, stype = struct.unpack_from("<II", data, base)
            offset, size = struct.unpack_from("<QQ", data, base + 24)
            link, = struct.unpack_from("<I", data, base + 40)
        else:
            name, stype = struct.unpack_from("<II", data, base)
            offset, size = struct.unpack_from("<II", data, base + 16)
            link, = struct.unpack_from("<I", data, base + 24)
        sections.append({"name": name, "type": stype, "offset": offset, "size": size, "link": link})

    shstr = sections[e_shstrndx]
    strtab = data[shstr["offset"] : shstr["offset"] + shstr["size"]]

    def sname(sec: dict[str, Any]) -> str:
        end = strtab.find(b"\x00", sec["name"])
        return strtab[sec["name"] : end].decode(errors="replace")

    by_name = {sname(s): s for s in sections}

    # GLIBC_x.y version references live as plain strings in .dynstr.
    dynstr = by_name.get(".dynstr")
    if dynstr:
        blob = data[dynstr["offset"] : dynstr["offset"] + dynstr["size"]]
        versions = [
            tuple(int(p) for p in m.split(b".")[:3])
            for m in re.findall(rb"GLIBC_(\d+\.\d+(?:\.\d+)?)", blob)
        ]
        if versions:
            info["glibc_max"] = ".".join(str(p) for p in max(versions))

        # SONAME: DT_SONAME (14) indexes into .dynstr.
        dyn = by_name.get(".dynamic")
        if dyn:
            step = 16 if is64 else 8
            fmt = "<qQ" if is64 else "<iI"
            for pos in range(dyn["offset"], dyn["offset"] + dyn["size"], step):
                tag, val = struct.unpack_from(fmt, data, pos)
                if tag == 0:
                    break
                if tag == 14:
                    end = blob.find(b"\x00", val)
                    info["soname"] = blob[val:end].decode(errors="replace")
    return info


def inspect(path: pathlib.Path) -> dict[str, Any]:
    data = path.read_bytes()
    if data[:8] == b"!<arch>\n":
        # Static archive: classify by its first ELF/Mach-O member.
        for probe in (b"\x7fELF", b"\xcf\xfa\xed\xfe"):
            idx = data.find(probe)
            if idx != -1:
                member = data[idx:]
                inner = read_elf(member) if probe == b"\x7fELF" else read_macho(member)
                return {"format": "archive", "member": inner}
        return {"format": "archive", "member": {"format": None}}
    if data[:4] == b"\x7fELF":
        return read_elf(data)
    return read_macho(data)


# --------------------------------------------------------------------------
# generate
# --------------------------------------------------------------------------

def source_input_digest() -> tuple[str, list[str]]:
    """sha256 over 'relpath sha256\\n' lines for every covered input, sorted."""
    covered: list[pathlib.Path] = []
    for pattern in SOURCE_INPUT_GLOBS:
        covered.extend(sorted(ROOT.glob(pattern)))
    lines, names = [], []
    for path in sorted(set(covered)):
        rel = path.relative_to(ROOT).as_posix()
        lines.append(f"{rel} {sha256_file(path)}\n")
        names.append(rel)
    return hashlib.sha256("".join(lines).encode()).hexdigest(), names


def git(*args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=True
    ).stdout.strip()


def load_targets() -> dict[str, dict[str, Any]]:
    return {t["triple"]: t for t in json.loads(TARGETS_PATH.read_text())["targets"]}


def generate(staging: pathlib.Path, out: pathlib.Path | None, abi_version: int) -> int:
    targets = load_targets()
    package_version = json.loads((ROOT / "package.json").read_text())["version"]
    digest, covered = source_input_digest()

    artifacts: list[dict[str, Any]] = []
    for triple_dir in sorted(p for p in staging.iterdir() if p.is_dir() and not p.name.startswith(".")):
        triple = triple_dir.name
        if triple not in targets:
            fail(f"staging directory is not a declared target: {triple}")
            continue
        for artifact in sorted(triple_dir.iterdir()):
            if artifact.name.startswith("lib") and artifact.suffix in {".a", ".so", ".dylib"}:
                kind = "static" if artifact.suffix == ".a" else "shared"
                symbols = artifact.with_name(artifact.name + ".symbols.txt")
                buildinfo = artifact.with_name(artifact.name + ".buildinfo.json")
                if not symbols.exists() or not buildinfo.exists():
                    fail(f"{triple}/{artifact.name}: missing harness byproducts (rebuild with build.sh)")
                    continue
                info = json.loads(buildinfo.read_text())
                record: dict[str, Any] = {
                    "target": triple,
                    "kind": kind,
                    "path": f"prebuilt/{triple}/{artifact.name}",
                    "size": artifact.stat().st_size,
                    "sha256": sha256_file(artifact),
                    "exported_symbols_sha256": sha256_file(symbols),
                    "minimum_runtime": targets[triple]["minimum_runtime"],
                    "compiler": info["compiler"],
                    "linker": info["linker"],
                    "archiver": info["archiver"],
                    "sdk_or_sysroot": info["sdk_or_sysroot"],
                    "compile_flags": sorted(set(info["compile_flags"])),
                }
                if kind == "shared":
                    probed = inspect(artifact)
                    name = probed.get("soname") or probed.get("install_name")
                    if not name:
                        fail(f"{triple}/{artifact.name}: no SONAME / install name in the binary")
                        continue
                    record["soname_or_install_name"] = name
                artifacts.append(record)

    if errors:
        return 1

    artifacts.sort(key=lambda a: (a["target"], a["kind"]))
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "package_version": package_version,
        "abi_version": abi_version,
        "source_commit": git("rev-parse", "HEAD"),
        "source_input_sha256": digest,
        "source_date_epoch": int(git("log", "-1", "--format=%ct")),
        "artifacts": artifacts,
    }
    payload = canonical_json(manifest)
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(payload)
        print(
            f"wrote {out} — {len(artifacts)} artifacts, "
            f"source-input digest {digest[:12]}… over {len(covered)} inputs"
        )
    else:
        sys.stdout.write(payload.decode())
    return 0


# --------------------------------------------------------------------------
# verify
# --------------------------------------------------------------------------

def verify(manifest_path: pathlib.Path, artifact_root: pathlib.Path, rebuild: bool) -> int:
    manifest = json.loads(manifest_path.read_text())
    targets = load_targets()

    print("[1] deterministic serialization")
    if canonical_json(manifest) != manifest_path.read_bytes():
        fail("manifest is not in canonical form (regenerate; do not hand-edit)")
    else:
        ok("byte-stable canonical JSON")

    print("[2] source-input digest")
    digest, covered = source_input_digest()
    if digest != manifest["source_input_sha256"]:
        fail(
            "source_input_sha256 mismatch — a covered source/build input changed "
            "without regenerating artifacts"
        )
    else:
        ok(f"{len(covered)} covered inputs match {digest[:12]}…")

    print("[3] per-artifact bytes, format, floor, ABI")
    seen: set[tuple[str, str]] = set()
    for record in manifest["artifacts"]:
        label = f"{record['target']}/{record['kind']}"
        key = (record["target"], record["kind"])
        if key in seen:
            fail(f"{label}: duplicate target/kind record")
            continue
        seen.add(key)

        rel = record["path"]
        if rel.startswith("/") or ".." in rel.split("/"):
            fail(f"{label}: unsafe path {rel!r}")
            continue
        if rel != f"prebuilt/{record['target']}/{pathlib.PurePosixPath(rel).name}":
            fail(f"{label}: path does not match its target directory: {rel}")
            continue

        path = artifact_root / record["target"] / pathlib.PurePosixPath(rel).name
        if not path.exists():
            fail(f"{label}: artifact missing at {path}")
            continue
        if path.is_symlink():
            fail(f"{label}: artifact is a symlink")
            continue

        if path.stat().st_size != record["size"] or sha256_file(path) != record["sha256"]:
            fail(f"{label}: size/sha256 does not match the bytes on disk")
            continue

        symbols = path.with_name(path.name + ".symbols.txt")
        if symbols.exists() and sha256_file(symbols) != record["exported_symbols_sha256"]:
            fail(f"{label}: exported-symbol digest changed (ABI drift without a bump?)")

        probed = inspect(path)
        expect_arch = TRIPLE_ARCH[record["target"]]
        actual = probed.get("member", probed) if probed.get("format") == "archive" else probed
        if actual.get("arch") != expect_arch:
            fail(f"{label}: architecture {actual.get('arch')} != {expect_arch} for its triple")
            continue

        is_darwin = record["target"].endswith("apple-darwin")
        if is_darwin and record["kind"] == "shared":
            floor = record["minimum_runtime"].replace("macOS ", "")
            minos = probed.get("minos")
            if minos and not floor.startswith(minos) and not minos.startswith(floor.split(".")[0]):
                fail(f"{label}: Mach-O minos {minos} does not match declared floor {floor}")
            if not probed.get("has_uuid"):
                fail(f"{label}: Mach-O has no LC_UUID — dyld will refuse to load it")
        if not is_darwin and record["kind"] == "shared" and "-gnu" in record["target"]:
            want = record["minimum_runtime"].replace("glibc ", "")
            got = probed.get("glibc_max")
            if got and tuple(int(x) for x in got.split(".")) > tuple(int(x) for x in want.split(".")):
                fail(f"{label}: references GLIBC_{got}, above the declared floor {want}")

        if record["kind"] == "shared":
            declared = record["soname_or_install_name"]
            embedded = probed.get("soname") or probed.get("install_name")
            if declared != embedded:
                fail(f"{label}: declared {declared!r} != embedded {embedded!r}")
        elif "soname_or_install_name" in record:
            fail(f"{label}: static artifacts must not declare a SONAME/install name")

        if record["minimum_runtime"] != targets[record["target"]]["minimum_runtime"]:
            fail(f"{label}: minimum_runtime disagrees with prebuilt/targets.json")

    tier1 = {t for t, e in targets.items() if e["tier"] == 1}
    covered_targets = {r["target"] for r in manifest["artifacts"]}
    if not tier1 <= covered_targets:
        fail(f"incomplete Tier-1 matrix; missing {sorted(tier1 - covered_targets)}")
    else:
        ok(f"Tier-1 matrix complete ({len(tier1)} targets, {len(manifest['artifacts'])} artifacts)")

    if rebuild and not errors:
        print("[4] independent rebuild through the pinned toolchain")
        out = artifact_root.parent / ".verify-rebuild"
        subprocess.run(
            [str(ROOT / "scripts/prebuilt/build.sh"), "build", "tier1"],
            env={**__import__("os").environ, "PREBUILT_OUT": str(out), "F2E_SIGN": "off"},
            check=True,
            stdout=subprocess.DEVNULL,
        )
        for record in manifest["artifacts"]:
            name = pathlib.PurePosixPath(record["path"]).name
            fresh = out / record["target"] / name
            if not fresh.exists() or sha256_file(fresh) != record["sha256"]:
                fail(f"{record['target']}/{record['kind']}: independent rebuild digest differs")
        if not errors:
            ok("every artifact reproduced bit-for-bit before signing")

    print(f"== {'PASS' if not errors else f'FAIL ({len(errors)})'}")
    return 1 if errors else 0


# --------------------------------------------------------------------------
# self-test: every assertion must be reachable in the failing direction
# --------------------------------------------------------------------------

def _load(p: pathlib.Path) -> dict[str, Any]:
    return json.loads(p.read_text())


def _save(p: pathlib.Path, m: dict[str, Any]) -> None:
    p.write_bytes(canonical_json(m))


def _first(m: dict[str, Any], kind: str) -> dict[str, Any]:
    return next(a for a in m["artifacts"] if a["kind"] == kind)


def _mutate_bytes(_m: pathlib.Path, root: pathlib.Path) -> None:
    target = next(root.rglob("libflags2env.a"))
    blob = bytearray(target.read_bytes())
    blob[len(blob) // 2] ^= 0xFF
    target.write_bytes(bytes(blob))


def _mutate_source(_m: pathlib.Path, _root: pathlib.Path) -> None:
    src = ROOT / "src/parser.c"
    src.write_bytes(src.read_bytes() + b"\n/* mutation */\n")


def _mutate_noncanonical(man: pathlib.Path, _root: pathlib.Path) -> None:
    man.write_text(json.dumps(_load(man)))  # compact, unsorted -> not canonical


def _mutate_path_target(man: pathlib.Path, _root: pathlib.Path) -> None:
    m = _load(man)
    a = _first(m, "static")
    other = next(x["target"] for x in m["artifacts"] if x["target"] != a["target"])
    a["path"] = f"prebuilt/{other}/{pathlib.PurePosixPath(a['path']).name}"
    _save(man, m)


def _mutate_traversal(man: pathlib.Path, _root: pathlib.Path) -> None:
    m = _load(man)
    _first(m, "static")["path"] = "prebuilt/../../etc/passwd"
    _save(man, m)


def _mutate_floor(man: pathlib.Path, _root: pathlib.Path) -> None:
    m = _load(man)
    _first(m, "static")["minimum_runtime"] = "glibc 9.9"
    _save(man, m)


def _mutate_abi(man: pathlib.Path, _root: pathlib.Path) -> None:
    m = _load(man)
    _first(m, "static")["exported_symbols_sha256"] = "0" * 64
    _save(man, m)


def _mutate_static_soname(man: pathlib.Path, _root: pathlib.Path) -> None:
    m = _load(man)
    _first(m, "static")["soname_or_install_name"] = "libflags2env.so"
    _save(man, m)


def _mutate_install_name(man: pathlib.Path, _root: pathlib.Path) -> None:
    m = _load(man)
    _first(m, "shared")["soname_or_install_name"] = "@rpath/libevil.dylib"
    _save(man, m)


def _mutate_drop_target(man: pathlib.Path, _root: pathlib.Path) -> None:
    m = _load(man)
    victim = m["artifacts"][0]["target"]
    m["artifacts"] = [a for a in m["artifacts"] if a["target"] != victim]
    _save(man, m)


MUTATIONS = {
    "tampered-artifact-bytes": _mutate_bytes,
    "changed-source-without-regen": _mutate_source,
    "hand-edited-noncanonical-manifest": _mutate_noncanonical,
    "path-target-directory-mismatch": _mutate_path_target,
    "path-traversal-escape": _mutate_traversal,
    "wrong-platform-floor": _mutate_floor,
    "abi-export-digest-drift": _mutate_abi,
    "static-declaring-soname": _mutate_static_soname,
    "install-name-substitution": _mutate_install_name,
    "incomplete-tier1-matrix": _mutate_drop_target,
}


def self_test(manifest: pathlib.Path, artifact_root: pathlib.Path) -> int:
    """Copy manifest+artifacts, apply one mutation each, require a red verify."""
    import shutil
    import tempfile

    print("== red tests: each mutation MUST make verify fail")
    source_backup = (ROOT / "src/parser.c").read_bytes()
    stayed_green: list[str] = []
    try:
        for name, mutate in MUTATIONS.items():
            with tempfile.TemporaryDirectory() as td:
                tmp = pathlib.Path(td)
                man = tmp / "manifest.json"
                root = tmp / "artifacts"
                shutil.copy2(manifest, man)
                shutil.copytree(artifact_root, root)
                mutate(man, root)
                proc = subprocess.run(
                    [sys.executable, __file__, "verify", "--manifest", str(man), "--artifact-root", str(root)],
                    capture_output=True,
                    text=True,
                )
                (ROOT / "src/parser.c").write_bytes(source_backup)
                verdict = "red as required" if proc.returncode != 0 else "STAYED GREEN — assertion is vacuous"
                print(f"  {name}: {verdict}")
                if proc.returncode == 0:
                    stayed_green.append(name)
    finally:
        (ROOT / "src/parser.c").write_bytes(source_backup)

    print(f"== self-test {'PASS' if not stayed_green else 'FAIL: ' + ', '.join(stayed_green)}")
    return 1 if stayed_green else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("self-test", help="prove every verify assertion can fail")
    s.add_argument("--manifest", type=pathlib.Path, required=True)
    s.add_argument("--artifact-root", type=pathlib.Path, required=True)

    g = sub.add_parser("generate", help="build a manifest from a staging tree")
    g.add_argument("--staging", type=pathlib.Path, required=True)
    g.add_argument("--out", type=pathlib.Path)
    g.add_argument("--abi-version", type=int, default=1)

    v = sub.add_parser("verify", help="re-derive every manifest claim from the bytes")
    v.add_argument("--manifest", type=pathlib.Path, required=True)
    v.add_argument("--artifact-root", type=pathlib.Path, required=True)
    v.add_argument("--rebuild", action="store_true")

    args = ap.parse_args()
    if args.cmd == "generate":
        return generate(args.staging, args.out, args.abi_version)
    if args.cmd == "self-test":
        return self_test(args.manifest, args.artifact_root)
    return verify(args.manifest, args.artifact_root, args.rebuild)


if __name__ == "__main__":
    raise SystemExit(main())
