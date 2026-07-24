# Flags2Env Ruby

Ruby bindings for the `flags2env` native parser.

Set `FLAGS2ENV_NATIVE_LIB` or pass a library path to `Flags2Env.new` when the
native shared library is not discoverable from the default platform library
path.

Subcommand-aware APIs mirror the C core: `parse` returns the resolved
`[commands.*]` path under `parse.command_env` (default `FLAGS2ENV_COMMAND`),
`help_requested?(argv)` detects `--help`, `help_table(command, argv)` renders
the help menu for the subcommand selected by argv, `coerce(values)` types
declared env keys (including command marker envs), and
`generate_types(language)` emits importable interfaces.
