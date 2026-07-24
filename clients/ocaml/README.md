# Flags2Env OCaml

OCaml bindings for the `flags2env` native parser.

The opam package exposes `Flags2env.parse` over the C ABI via `ctypes` and uses
the project-local `.cli-flags.toml` format shared by the other clients.

Subcommand-aware APIs mirror the C core: `parse` returns the resolved
`[commands.*]` path under `parse.command_env` (default `FLAGS2ENV_COMMAND`),
`is_help_requested argv` detects `--help`, `help_table ~command argv` renders
the help menu for the subcommand selected by argv, `coerce values` types
declared env keys (including command marker envs), and
`generate_types language` emits importable interfaces.
