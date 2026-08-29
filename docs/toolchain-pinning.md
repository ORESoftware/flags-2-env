# Release toolchain pinning

Tracking: Linear DEN-2846

The Linux prebuilt-artifact harness uses an exact Zig release as its cross compiler. Release-producing jobs do not use Zig `master`, a floating package-manager channel, or an unpinned setup-action input.

## Current release pin

- Zig version: `0.16.0`
- Release date: `2026-04-13`
- Machine-readable pins: `toolchains/zig-0.16.0-linux.json`
- Official download metadata: `https://ziglang.org/download/index.json`
- Official minisign public key: recorded in the pin file

The initial host archives cover Linux x86_64 and Linux aarch64. Those hosts produce the Tier 1 GNU and musl Linux target artifacts declared in `prebuilt/targets.json`.

## Required acquisition sequence

A later installer/build-harness slice must:

1. select a host entry from the checked-in allowlist;
2. download the archive and its `.minisig` to temporary files;
3. compute SHA-256 and compare it with the checked-in digest;
4. verify the minisign signature with the checked-in Zig release public key;
5. inspect the archive before extraction and reject absolute paths, `..`, links escaping the destination, device nodes, and duplicate paths;
6. extract into a content-addressed tool cache only after both cryptographic checks pass;
7. execute `zig version` and require exact output `0.16.0`; and
8. record the host pin, archive digest, compiler path, and target in build evidence.

Community mirrors may be tried before the Zig origin, but mirror bytes must satisfy the same digest and signature. Redirects never change the accepted archive identity.

## Platform boundary

Zig is the reviewed Linux cross-build tool. Darwin release artifacts remain native Xcode/clang output on matching macOS runners until a separate ADR proves SDK provenance, legal redistribution, linker behavior, signing, deployment-floor behavior, and native loadability for a Darwin cross-toolchain.

## This slice

This phase pins and validates metadata only. It does not download Zig, compile C, certify an artifact, remove the legacy `build/` directory, or change the package's runtime/build behavior. Network acquisition, safe extraction, target Make rules, and reproducibility jobs remain independently reviewable follow-up work.

Validate the pins without network access:

```sh
python3 scripts/validate-toolchain-pins.py
```
