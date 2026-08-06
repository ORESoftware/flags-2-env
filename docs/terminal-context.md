# Terminal and shell context API

flags2env exposes terminal context as an additive, opt-in C API. Existing parse results, generated types, shell exports, help output, and CLI behavior are unchanged.

Include `src/terminal_context.h` and link the normal flags2env static or shared library:

```c
char *context = f2e_terminal_context_json();
if (context != NULL) {
  /* inspect or decode the JSON report */
  f2e_free(context);
}
```

`f2e_terminal_context_json()` returns:

```json
{
  "version": 1,
  "stdinTty": true,
  "stdoutTty": false,
  "stderrTty": true,
  "interactive": true,
  "canPrompt": true,
  "ci": false,
  "dumb": false,
  "nested": false,
  "outputMode": "plain",
  "shell": "zsh",
  "shellSource": "shell-env",
  "terminal": "iterm",
  "colorStdout": false,
  "colorStderr": true,
  "unicode": true,
  "hyperlinks": true,
  "columns": 132
}
```

`f2e_terminal_context_env_json()` returns the same facts as string values under reserved `F2E_CONTEXT_*` keys. It does not mutate the process environment; callers decide whether and where to export them. `f2e_terminal_shell_family()` provides the stable shell family directly.

## Conservative behavior

`canPrompt` requires terminal stdin and stderr and is false in CI or when `TERM=dumb`. Stdout may be redirected because data can be piped while diagnostics remain interactive on stderr.

`outputMode` is a hint only:

- `human`: stdout is a terminal outside CI and not dumb
- `plain`: at least one output stream is a terminal, but rich human output is unsafe
- `machine`: stdout and stderr are both redirected

The API never chooses JSON, colors, progress bars, prompts, or line wrapping on behalf of an application.

## Shell detection

Portable shell detection is necessarily best effort. The report includes `shellSource` so consumers can assess confidence. Precedence is:

1. `F2E_SHELL`
2. `SHELL`
3. PowerShell environment markers
4. `COMSPEC`
5. inherited `F2E_CONTEXT_SHELL`
6. `unknown`

Supported families are `bash`, `zsh`, `fish`, `nushell`, `powershell`, `cmd`, `sh`, and `unknown`. Syntax-generating commands should still accept an explicit shell argument.

## Deterministic overrides

Tests and controlled wrappers may set:

- `F2E_FORCE_STDIN_TTY`
- `F2E_FORCE_STDOUT_TTY`
- `F2E_FORCE_STDERR_TTY`
- `F2E_FORCE_CI`
- `F2E_FORCE_COLOR`
- `F2E_FORCE_UNICODE`

Values such as `1`, `true`, `yes`, and `on` enable; `0`, `false`, `no`, `off`, and `never` disable; `auto` restores detection. `NO_COLOR` disables color unless `F2E_FORCE_COLOR` is explicitly set.
