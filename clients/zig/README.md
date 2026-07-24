# flags2env Zig

Zig bindings for flags2env. The package exposes the `flags2env` module and
builds against the package-local C parser under `native/`.


Subcommand-aware APIs mirror the C core: `parseJsonArgv*` returns the resolved
`[commands.*]` path under `parse.command_env` (default `FLAGS2ENV_COMMAND`),
`isHelpRequestedJsonArgv` detects `--help`, `helpTableForJsonArgv*` renders the
help menu for the subcommand selected by argv, `coerceJson*` types declared env
keys (including command marker envs), and `generateTypes*` emits importable
interfaces. Requires Zig 0.14+.
