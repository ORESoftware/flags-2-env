<!-- generated-policy: frozen -->

# Generated files — read-only

Do **not** hand-edit files in this directory. Typical outputs:

- `generated/dart/env.dart` — Dart types from [flags-2-env](https://github.com/flags-2-env/flags-2-env)
- `generated/json-schema/*.schema.json` — Draft 2020-12 schema used as a **runtime cross-check**
- language types from the same `.cli-flags.toml` (TypeScript, Python, Go, Rust, …)

Primary generator input is `.cli-flags.toml`, not JSON Schema. Schema is emitted so unit tests and runtime validators can prove the contract, not only compile-time types.

## Disk permissions

`--output` (and this repo's generators) freeze files with `chmod a-w`. Directories and this `README.md` stay writable.

Git does **not** persist the write bit. After clone or checkout:

```sh
python3 scripts/check-generated-contract.py --freeze --require-readonly
```

To regenerate, the generator thaws, writes, then freezes again. If you redirected stdout yourself:

```sh
chmod u+w generated/dart/env.dart
f2e generate dart .cli-flags.toml --name Env --output generated/dart/env.dart
```
