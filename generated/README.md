<!-- generated-policy: frozen -->

# Generated files — read-only

Do **not** hand-edit files in this directory. Typical outputs:

- `generated/dart/env.dart` — Dart types from [flags-2-env](https://github.com/flags-2-env/flags-2-env)
- `generated/json-schema/*.schema.json` — Draft 2020-12 schema used as a **runtime cross-check**
- language types from the same `.cli-flags.toml` (TypeScript, Python, Go, Rust, …)

Primary generator input is `.cli-flags.toml`, not JSON Schema. Schema is emitted
so unit tests and runtime validators can prove the contract, not only compile-time
types.

## Disk permissions

`--output` (and this repo's generators) freezes files with `chmod a-w`. Directories
and this `README.md` stay writable so generators can replace files.

Git does **not** persist the write bit (only the executable bit). A fresh clone is
writable until you re-freeze:

```sh
python3 scripts/check-generated-contract.py --freeze --require-readonly
```

To regenerate, change `.cli-flags.toml` and run the generator again. The
generator thaws, writes, and freezes its output atomically:

```sh
f2e generate dart .cli-flags.toml --name Env --output generated/dart/env.dart
```

## Runtime contract (not just compile-time)

JSON Schema is a **cross-check**, not the primary generator input. The checker
validates fixtures/examples against Draft 2020-12 at runtime (valid must pass,
invalid must fail) and compares schema keys to `.cli-flags.toml` env names.

```sh
python3 scripts/check-generated-contract.py --freeze --require-readonly
```
