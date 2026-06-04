# flags2env Bash

Source `flags2env.bash` from a Bash function or script, then call
`flags2env_apply "$@"` to export values in the current shell.

```bash
#!/usr/bin/env bash
source "/path/to/flags2env.bash"

my_program() {
  FLAGS2ENV_CONFIG="${FLAGS2ENV_CONFIG:-.cli-flags.toml}" flags2env_apply "$@"
  command my_program_impl "$@"
}
```

Set `FLAGS2ENV_BIN` when the native `flags2env` CLI is not on `PATH`.

