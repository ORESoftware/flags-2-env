# flags2env Rust

Rust bindings for flags2env. The crate includes package-local C parser sources
under `native/` so `cargo package` and downstream builds do not need the
monorepo root.

## Bundled runtime — recommended for CLIs and servers

`BundledFlags2Env` compiles the C parser into the Rust artifact. The resulting
binary is self-contained and does not need `libflags2env.so`,
`libflags2env.dylib`, or `flags2env.dll` in the runtime image.

Treat the flags contract as reviewed executable policy, not ambient working-
directory input. A source example can bind the path to its crate at compile
time. Production installers should instead place the reviewed contract under an
executable-owned prefix such as `/usr/local/share/<app>/.cli-flags.toml` and
resolve that location from `std::env::current_exe()`. If an operator override is
supported, require an absolute regular-file path. Do not accept a bare
`.cli-flags.toml` from the process working directory in production.

```rust
use flags2env::BundledFlags2Env;

const CONTRACT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/.cli-flags.toml");

fn apply_flags() -> Result<(), Box<dyn std::error::Error>> {
    let parser = BundledFlags2Env::new();
    parser
        .audit_config(Some(CONTRACT))
        .map_err(|_| "reviewed flags contract audit failed")?;
    let argv = std::env::args().collect::<Vec<_>>();
    let parsed = parser
        .parse_structured(&argv, Some(CONTRACT))
        .map_err(|_| "flags parsing failed")?;
    if !parsed.unknown_options.is_empty()
        || !parsed.errors.is_empty()
        || !parsed.extras.is_empty()
    {
        return Err(format!(
            "invalid CLI arguments: unknown={}, errors={}, positionals={}",
            parsed.unknown_options.len(),
            parsed.errors.len(),
            parsed.extras.len()
        )
        .into());
    }
    for (key, value) in parsed.provided_flags {
        // Apply once at process startup, before threads and typed config reads.
        unsafe { std::env::set_var(key, value) };
    }
    Ok(())
}
```

Do not render parser error payloads, unknown option values, or positional
contents directly into application logs. Summarize failures by count and, when
needed, include only bounded/sanitized option names.

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

const CONTRACT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/.cli-flags.toml");

fn load_config() -> Result<CliConfig, Box<dyn std::error::Error>> {
    let parser = BundledFlags2Env::new();
    let argv = std::env::args().collect::<Vec<_>>();
    let parsed = parser
        .parse_structured(&argv, Some(CONTRACT))
        .map_err(|_| "flags parsing failed")?;
    if !parsed.unknown_options.is_empty()
        || !parsed.errors.is_empty()
        || !parsed.extras.is_empty()
    {
        return Err("invalid CLI arguments".into());
    }

    let mut values: HashMap<String, String> = std::env::vars().collect();
    values.extend(parsed.provided_flags);
    parser
        .coerce(&values, Some(CONTRACT))
        .map_err(|_| "typed flags configuration is invalid".into())
}
```

`coerce<T, V>()` accepts any serializable object and deserializes the validated
result into `T`. It keeps declared env keys, applies active defaults, and
converts the schema's integers, doubles, booleans, JSON values, arrays, and
maps. Invalid values return `CoercionError::Validation`; use
`validation_errors()` only in trusted test/development tooling when the values
are known non-secret. A `CoercionError::Deserialize` means the requested Rust
type does not agree with the generated schema. The same method is available on
the dynamically loaded `Flags2Env` client. Use `provided_flags`, not the
default-bearing `flags`, when merging over `std::env::vars()`; this preserves
the precedence `CLI > environment > schema default`.

Secrets should remain environment-only and be listed under `[env].ignore` in
`.cli-flags.toml`; do not declare secret-bearing flags or defaults.

## Dynamic runtime

`Flags2Env::load(path)` remains available for applications that intentionally
load a separately installed shared library. These callers are responsible for
shipping the matching native library in every release artifact and runtime
image. Do not silently count a source dependency as complete integration if the
shared library is absent in production.
