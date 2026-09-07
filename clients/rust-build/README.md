# flags2env-build

Cargo build-time generation backed by the canonical bundled flags2env C core.
Related: flags-2-env/flags-2-env#10 and ORESoftware/ores-cli#1.

In `build.rs`, call `flags2env_build::generate_cargo(".cli-flags.toml", "CliConfig")?`.
Include `OUT_DIR/cli_config.rs` in a private module and deserialize the runtime
`BundledFlags2Env::coerce()` result into that generated type. Access the generated
fields directly. Removing or renaming a referenced env declaration then breaks
compilation rather than silently falling back to a hand-maintained default.
The crate also emits `cli_config.schema.json` and an exact `cli-flags.toml` input
copy for `include_str!`. Runtime environment *values* still require runtime
validation: compilation cannot prove that an external process sets a variable.

The generated JSON Schema is a disposable projection for checking. It must not
replace independently authored JSON Schema or TypeSpec authorities in application
interface repositories. Feed those through typespec-json-schema-validator's
separate parity workflow.

Use `--no-json` for boolean negation; it already belongs to the canonical parser.
`--json=false` is also explicit. This build helper does not add a second argv
parser or reinterpret bang aliases. Last occurrence and invalid-input behavior
are tested against the real bundled parser.

Test: `cargo test --manifest-path clients/rust-build/Cargo.toml`.
See `examples/rust-typed` and the `rust-build-contract` workflow for an executable
consumer and a negative compile test after renaming a declaration.

The crate currently consumes its sibling Rust binding by path inside the source
repository. Git consumers should pin an immutable repository commit; crates.io
publication requires publishing a versioned flags2env dependency first.
