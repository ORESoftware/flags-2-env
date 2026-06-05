# Flags2Env OCaml

OCaml bindings for the `flags2env` native parser.

The opam package exposes `Flags2env.parse` over the C ABI via `ctypes` and uses
the project-local `.cli-flags.toml` format shared by the other clients.
