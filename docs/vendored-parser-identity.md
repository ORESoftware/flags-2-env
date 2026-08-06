# Vendored parser identity

A consumer that compiles committed copies of `parser.c` and `parser.h` has two independent identities:

1. the immutable `parser_ref` named in its compliance workflow; and
2. the source bytes its build system actually compiles.

Those identities must be equal. Merely checking out and testing `parser_ref` does not prove that a consumer's vendored files came from that revision.

Call the reusable workflow with both vendored paths:

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
      vendored_parser_c_path: vendor/flags2env/parser.c
      vendored_parser_h_path: vendor/flags2env/parser.h
      runtime_smoke_script: .github/scripts/flags2env-runtime-smoke.sh
```

The two path inputs are optional only as a pair. When supplied, the workflow:

- resolves each path as a regular file inside the consumer checkout;
- rejects absolute paths, traversal components, missing files, directories, and symlink escapes;
- compares the consumer C and header bytes with `src/parser.c` and `src/parser.h` from the exact `parser_ref` checkout;
- emits bounded diagnostics without dumping source contents; and
- retains read-only permissions for ordinary pull-request checks.

Keep a repository-owned runtime smoke as well. Byte identity proves which parser implementation is compiled; the smoke proves the final executable selects a trusted contract, rejects unknown or malformed flags safely, preserves protocol stdout boundaries, and does not disclose caller-supplied secrets.

When updating a vendored parser, copy both canonical files from one reviewed full commit, update `parser_ref` to that same commit, and let the reusable gate reject any partial or stale update. Do not suppress compiler diagnostics caused by old vendored bytes locally when the producer has already fixed the underlying portability issue.
