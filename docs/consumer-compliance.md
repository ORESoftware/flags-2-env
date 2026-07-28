# Reusable consumer compliance

Repositories that ship a CLI, server, worker, gateway, proxy, or MCP server can call the reusable workflow at an immutable commit SHA:

```yaml
jobs:
  flags2env:
    uses: ORESoftware/flags-2-env/.github/workflows/reusable-consumer-compliance.yml@<full-commit-sha>
    with:
      parser_ref: <same-full-commit-sha>
      kind: server
      contract_path: .cli-flags.toml
      rust_manifest_path: Cargo.toml
      cargo_lock_path: Cargo.lock
      runtime_smoke_script: scripts/smoke-flags.sh
      artifact_smoke_script: scripts/smoke-runtime-image.sh
```

The caller should pin both `uses:` and `parser_ref` to the same reviewed commit. Ordinary PR checks need only `contents: read`.

## What the reusable workflow proves

1. The exact pinned parser revision builds and audits the consumer's contract.
2. `parse.allow_unknown` is false or omitted.
3. The contract owns at least one real process-level flag.
4. Secret-bearing environment variables are not declared as flags or given defaults.
5. Rust consumers use the exact upstream Git source and full immutable `rev`, with a matching committed `Cargo.lock`.
6. Optional runtime and artifact checks are repository-controlled script files, not arbitrary workflow input commands.
7. MCP consumers must provide a runtime/stdio smoke script so stdout protocol cleanliness is tested by the consumer that owns the binary.

The canonical C audit still owns syntax, aliases, subcommand scoping, type validation, duplicate destinations, and generated help behavior. The Python policy checker adds cross-repository security and pinning rules.

## Consumer smoke scripts

Smoke scripts should be deterministic and credential-free. They should:

- exercise one declared operational flag;
- prove an undeclared secret-bearing flag fails closed;
- avoid printing environment values or credentials;
- for containers, inspect the final runtime image and verify `.cli-flags.toml` is packaged;
- for MCP servers, verify normal startup writes no application diagnostics to stdout;
- use test-only ports, temporary paths, and bounded timeouts.

## Scope exclusions

Do not add this workflow to browser-only, Flutter/mobile, desktop GUI, static-site, SDK-only, interface/schema, documentation, or infrastructure-only repositories unless they also ship a real process-level CLI or service.
