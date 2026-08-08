# Prebuilt manifest: compatibility and evolution policy

Companion to `prebuilt/manifest.schema.json` (the wire contract) and ADR 0001.
Generator/verifier: `scripts/prebuilt/manifest.py`.

## Versioned surfaces

Three numbers move independently and mean different things:

| Field | Meaning | Bumped when |
| --- | --- | --- |
| `schema_version` | shape of the manifest document | the schema changes incompatibly (see below) |
| `package_version` | the released flags-2-env version | every release, from `package.json` |
| `abi_version` | the C ABI consumers link against | an exported symbol is removed or changes meaning |

`abi_version` is **not** derived from `package_version`. A patch release may
carry a new `abi_version` if it breaks linkage, and many releases will not
change it at all. `exported_symbols_sha256` is the evidence: it changes whenever
the exported set changes, including additions. An addition is compatible and
does not require an `abi_version` bump; a removal or signature change does, plus
consumer-migration evidence per ADR 0001.

## Compatible vs incompatible schema changes

Compatible (no `schema_version` bump):

- adding an **optional** artifact field (e.g. `provenance`, `signature`);
- adding a target to `prebuilt/targets.json`;
- widening a documented enum with a value older verifiers ignore safely.

Incompatible (bump `schema_version`, dual-publish during migration):

- adding or removing a **required** field;
- changing the meaning, units, or normalization of an existing field;
- changing the `path` grammar or the artifact naming convention;
- changing how `source_input_sha256` or `exported_symbols_sha256` is computed.

The digest-definition rule matters most: those two hashes are only comparable
across builds that computed them the same way, so any change to their inputs or
normalization is a breaking change even though the document shape is untouched.

## Normalization rules (why the manifest is portable)

- Serialization is canonical: `indent=2`, sorted keys, trailing newline. The
  verifier rejects a manifest that is not byte-identical to its canonical form,
  so hand-edits fail rather than silently persisting.
- `compile_flags` are recorded **normalized**, not verbatim: `-ffile-prefix-map`
  necessarily names the absolute checkout path, so it is recorded as
  `-ffile-prefix-map=<source-root>=.`. Recording it verbatim would make the
  manifest differ per machine and would publish a local filesystem path. The
  binaries are unaffected — the real flag is still passed to the compiler.
- `source_input_sha256` is a digest over `"<relpath> <sha256>\n"` lines, sorted
  by path, covering C sources, headers, `Makefile`, `prebuilt/targets.json`,
  `prebuilt/manifest.schema.json`, and the harness + generator themselves. The
  generator is inside its own digest on purpose: changing how artifacts are
  produced invalidates the manifest that describes them.

## What the verifier re-derives from bytes

`manifest.py verify` trusts nothing in the document it can check independently:
size, SHA-256, exported-symbol digest, binary format and architecture,
Mach-O `LC_BUILD_VERSION`/`LC_VERSION_MIN_MACOSX` minos, ELF `GLIBC_x.y`
references against the declared floor, `LC_UUID` presence (a dylib without one
is unloadable), ELF `SONAME` / Mach-O install name against the declared value,
and `minimum_runtime` against `prebuilt/targets.json`. Parsing is stdlib-only so
CI needs no llvm-readelf/otool.

`--rebuild` additionally rebuilds through the pinned toolchain and compares
digests **before** any signing step, per ADR 0001's repro-then-sign rule.

## Vacuity rule

`manifest.py self-test` mutates a copy ten ways — tampered bytes, changed source
without regeneration, hand-edited manifest, path/target mismatch, path
traversal, wrong platform floor, ABI digest drift, static declaring a SONAME,
install-name substitution, incomplete Tier-1 matrix — and requires each to turn
the verifier red. A green verify is only meaningful because red is reachable;
add a mutation whenever an assertion is added.
