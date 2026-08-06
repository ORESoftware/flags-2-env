# Formal verification

`flags-2-env` keeps its executable specifications beside the native and Rust
implementations:

- `cbmc/parser_harness.c` model-checks bounded calls into the real C parser.
- `smt/parser_invariants.smt2` proves parser dispatch invariants with Z3.
- `../clients/rust/src/formal_model.rs` expresses the same dispatch rules in
  Rust and proves them with Kani.
- `fmctl.json` is the repository analysis manifest. It uses the
  `formal-methods.v1` request shape accepted by `dd-formal-methods-server`.

Run the C and SMT proofs in the Nix development shell:

```sh
nix develop -c ./scripts/formal-check.sh
```

Run the Rust proofs with Kani:

```sh
cd clients/rust
cargo kani
```

The CBMC harness includes `src/parser.c` directly. This is intentional: it
allows the proof harness to reach file-local parser helpers without creating a
second implementation that could drift.

The `formal-methods.yml` GitHub workflow validates the manifest and runs the
local CBMC, Z3, and Kani proofs. It is repository-local because the currently
deployed webhook service is configured for a different fixed Cargo manifest.

Until an independent `fmctl` schema or executable is published in the
organization, `fmctl.json` deliberately stays wire-compatible with the
deployed `formal-methods.v1` service rather than introducing a second,
unverifiable manifest format.
