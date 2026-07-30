# flags2env Rust

Rust bindings for flags2env. The crate includes package-local C parser sources
under `native/` so `cargo package` and downstream builds do not need the
monorepo root.

## Bundled runtime — recommended for CLIs and servers

`BundledFlags2Env` compiles the C parser into the Rust artifact. The resulting
binary is self-contained and does not need `libflags2env.so`,
`libflags2env.dylib`, or `flags2env.dll` in the runtime image.

```rust
use flags2env::BundledFlags2Env;

fn apply_flags() -> Result<(), Box<dyn std::error::Error>> {
    let parser = BundledFlags2Env::new();
    parser.audit_config(Some(".cli-flags.toml"))?;
    let argv = std::env::args().collect::<Vec<_>>();
    let parsed = parser.parse_structured(&argv, Some(".cli-flags.toml"))?;
    if !parsed.unknown_options.is_empty() || !parsed.errors.is_empty() {
        return Err(format!(
            "invalid CLI arguments: unknown={:?}, errors={:?}",
            parsed.unknown_options, parsed.errors
        )
        .into());
    }
    for (key, value) in parsed.flags {
        // Apply once at process startup, before threads and typed config reads.
        unsafe { std::env::set_var(key, value) };
    }
    Ok(())
}
```

## Typed coercion and generated interfaces

Generate the Rust shape from the same schema used at runtime:

```sh
f2e generate rust .cli-flags.toml --name CliConfig > src/cli_config.rs
```

The generated module derives `serde::Serialize` and `serde::Deserialize`, so
the application must include `serde` with its `derive` feature. Then merge the
environment and parsed flags and cross the typed boundary once:

```rust
mod cli_config;

use cli_config::CliConfig;
use flags2env::BundledFlags2Env;
use std::collections::HashMap;

fn load_config() -> Result<CliConfig, Box<dyn std::error::Error>> {
    let parser = BundledFlags2Env::new();
    let argv = std::env::args().collect::<Vec<_>>();
    let parsed = parser.parse_structured(&argv, Some(".cli-flags.toml"))?;
    if !parsed.unknown_options.is_empty() || !parsed.errors.is_empty() {
        return Err("invalid CLI arguments".into());
    }

    let mut values: HashMap<String, String> = std::env::vars().collect();
    values.extend(parsed.flags);
    Ok(parser.coerce(&values, Some(".cli-flags.toml"))?)
}
```

`coerce<T, V>()` accepts any serializable object and deserializes the validated
result into `T`. It keeps declared env keys, applies active defaults, and
converts the schema's integers, doubles, booleans, JSON values, arrays, and
maps. Invalid values return `CoercionError::Validation`; use
`validation_errors()` to inspect all conversion failures at once. A
`CoercionError::Deserialize` means the requested Rust type does not agree with
the generated schema. The same method is available on the dynamically loaded
`Flags2Env` client.

Secrets should remain environment-only and be listed under `[env].ignore` in
`.cli-flags.toml`; do not declare secret-bearing flags or defaults.

## Dynamic runtime

`Flags2Env::load(path)` remains available for applications that intentionally
load a separately installed shared library. These callers are responsible for
shipping the matching native library in every release artifact and runtime
image. Do not silently count a source dependency as complete integration if the
shared library is absent in production.
