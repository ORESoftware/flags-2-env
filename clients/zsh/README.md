# flags2env Zsh

Source `flags2env.zsh` from a Zsh function or script, then call
`flags2env_apply "$@"` to export values in the current shell.

```zsh
#!/usr/bin/env zsh
source "/path/to/flags2env.zsh"

my_program() {
  FLAGS2ENV_CONFIG="${FLAGS2ENV_CONFIG:-.cli-flags.toml}" flags2env_apply "$@"
  command my_program_impl "$@"
}
```

Set `FLAGS2ENV_BIN` when the native `flags2env` CLI is not on `PATH`.

