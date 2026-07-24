# flags2env Python

Python bindings for the native `flags2env` shared library.

Set `FLAGS2ENV_NATIVE_LIB` or pass a library path to `Flags2Env(...)` when the
native library is not on the platform loader path.

Subcommand-aware APIs mirror the C core: `parse` returns the resolved
`[commands.*]` path under `parse.command_env` (default `FLAGS2ENV_COMMAND`),
`is_help_requested(argv)` detects `--help`, `help_table(command, argv)` renders
the help menu for the subcommand selected by argv, `coerce(values)` types
declared env keys (including command marker envs), and
`generate_types(language)` emits importable interfaces.
