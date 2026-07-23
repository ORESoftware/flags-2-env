# Homebrew

`Formula/flags2env.rb` is the tap formula for the native `flags2env` CLI. It
builds the C executable and library with `make all`, installs the bash/zsh shell
helpers, and tests both JSON parsing and `shell-env` export output.
The formula targets Homebrew on macOS and Linux/WSL. On Linux it declares
Homebrew `gcc` as a build dependency; on macOS Homebrew uses the system developer
toolchain compiler. The compiler is needed only while Homebrew builds the native
artifacts; end users do not need a compiler to run the installed CLI.

The installed Cellar payload is allowlisted to the CLI, native header and
libraries, and bash/zsh helpers. The repository's `tests/` directory, including
the Docker generated-code matrix, is not installed, and the formula test asserts
that boundary.

Before publishing a stable formula, create and push the matching git tag
(`v0.1.0` for the current formula), then run:

```sh
scripts/publish-homebrew.sh --dry-run
scripts/publish-homebrew.sh --release
```

For a tap or Homebrew core pull request, copy `Formula/flags2env.rb` into the
tap's `Formula/` directory and run the formula install, audit, and test commands
there before opening the pull request. Homebrew's style/audit commands may
reject formulae that are not inside a tap checkout. The publish helper defaults
audit to the formula token `flags2env` because current Homebrew rejects path
arguments for `brew audit`; set `FLAGS2ENV_HOMEBREW_AUDIT_TARGET` if your tap
uses a qualified name such as `oresoftware/tap/flags2env`.
