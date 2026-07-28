# Reusable consumer compliance

Repositories that ship a CLI, server, worker, gateway, proxy, or MCP server can call the reusable workflow at an immutable tooling commit while independently naming the exact parser revision the executable ships:

```yaml
permissions:
  contents: read

jobs:
  flags2env:
    uses: ORESoftware/flags-2-env/.github/workflows/reusable-consumer-compliance.yml@<tooling-full-commit-sha>
    with:
      tooling_ref: <same-tooling-full-commit-sha>
      parser_ref: <consumer-parser-full-commit-sha>
      kind: server
      command_name: example-server
      contract_path: .cli-flags.toml
      rust_manifest_path: Cargo.toml
      cargo_lock_path: Cargo.lock
      runtime_smoke_script: scripts/smoke-flags.sh
      artifact_smoke_script: scripts/smoke-runtime-image.sh
```

Pin `uses:` and `tooling_ref` to the same reviewed full commit SHA. `parser_ref` is separate on purpose: it must match the immutable parser revision in the consumer's manifest and lockfile. This lets a repository adopt newer read-only compliance tooling without silently changing the parser embedded in its production artifact.

Ordinary pull-request checks need only `contents: read`.

## What the reusable workflow proves

1. Both tooling and parser inputs are full immutable commit SHAs.
2. The exact shipped parser revision builds and audits the consumer's contract.
3. `parse.allow_unknown` is false or omitted.
4. The contract owns at least one real process-level flag.
5. Secret-bearing environment variables are not declared as flags or given defaults.
6. Rust consumers use the exact upstream Git source and full immutable `rev`, with a matching committed `Cargo.lock`.
7. The generated help menu renders successfully through wide and narrow pseudo-terminals, contains each visible option and description, and does not fall back to JSON.
8. Bash completion parses, registers for `command_name`, executes in a real Bash process, and returns a declared option or command.
9. Zsh completion parses, registers through `compinit`, autoloads in a real Zsh process, and contains declared candidates.
10. Optional runtime and artifact checks are repository-controlled script files, not arbitrary workflow input commands.
11. MCP consumers must provide a runtime/stdio smoke script so stdout protocol cleanliness is tested by the repository that owns the binary.
12. CLI consumers must provide a runtime smoke script that checks the actual executable's help surface rather than only the canonical generator's table.

The canonical C audit remains the source of truth for syntax, aliases, subcommand scoping, type validation, duplicate destinations, and generated help/completion behavior. The Python policy checker adds cross-repository security and pinning rules. The shell-contract verifier exercises the canonical output in real terminal and shell runtimes.

## Consumer smoke scripts

Smoke scripts should be deterministic and credential-free. They should:

- exercise one declared non-secret operational flag;
- prove an undeclared secret-bearing flag fails closed;
- avoid printing environment values or credentials;
- for CLIs, invoke the real binary's root and representative subcommand `--help` paths and assert the expected options/descriptions;
- for containers, inspect the final runtime image and verify `.cli-flags.toml` is packaged;
- for MCP servers, verify normal startup writes no application diagnostics to stdout;
- use test-only ports, temporary paths, and bounded timeouts.

## Scope exclusions

Do not add this workflow to browser-only, Flutter/mobile, desktop GUI, static-site, SDK-only, interface/schema, documentation, or infrastructure-only repositories unless they also ship a real process-level CLI or service.
