# flags2env Rust

Rust bindings for flags2env. The crate includes package-local C parser sources
under `native/` so `cargo package` and downstream builds do not need the
monorepo root.

