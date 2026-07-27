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

Secrets should remain environment-only and be listed under `[env].ignore` in
`.cli-flags.toml`; do not declare secret-bearing flags or defaults.

## Dynamic runtime

`Flags2Env::load(path)` remains available for applications that intentionally
load a separately installed shared library. These callers are responsible for
shipping the matching native library in every release artifact and runtime
image. Do not silently count a source dependency as complete integration if the
shared library is absent in production.
