# Nix development contract

The repository exposes a non-interactive C and Node development environment:

```sh
nix develop
nix develop -c agent-check
nix run .#agent-check
nix flake check --show-trace
```

`agent-check` uses the pinned Nix toolchain to:

- validate Git whitespace, Nix formatting, shell lint/format, and GitHub Actions;
- install the locked Node dependencies and compile the Node native addon from source;
- build the shared library, static library, and CLI under strict C99 warnings;
- run borrow checks, README snippets, cross-language parser parity, API-hardening, allocation-failure, and process-smoke tests;
- audit the npm package contents and dry-run the package;
- audit the multi-language release matrix.

Mutable npm, node-gyp, and XDG state stays below `.cache/nix-agent/` unless explicitly overridden. The shell does not read publishing credentials or perform a release.

## Strict C portability

The Nix environment deliberately supplies its own compiler, archive tools, Make, Node headers, Python, Ruby, and reference runtimes. Source files must request any POSIX interfaces they use before including system headers; builds must not depend on a host compiler implicitly exposing extensions.

## Docker and OCI policy

`flags-2-env` produces libraries, a CLI, and language packages. It is not a long-running OCI workload. The default agent contract therefore avoids building or publishing a production container.

Docker-only code-generation and cross-language smoke tests remain separate opt-in targets. Their images should be digest-pinned and supply-chain scanned, but a runtime OCI image should not be introduced without a concrete deployment use case.
