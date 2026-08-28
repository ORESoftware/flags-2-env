# Short-bundle fuzz corpus

Seeds for `tests/fuzz_parser.c`, wired in by `scripts/fuzz-smoke.sh` alongside
`tests/fuzz-parser.dict`. They exist because combined single-character flags
were otherwise unreachable by fuzzing: libFuzzer starting from an empty corpus
would have to synthesize a multi-character `-xy` token by mutation alone, which
does not happen inside a CI-sized budget. Without these, the bundle functions
measured 0% line coverage; with them, 82-94%.

## Two things that look like mistakes and are not

**Every seed starts with a newline.** The harness dispatches on `data[0] % 5`,
and `10 % 5 == 0` selects the JSON-argv branch — the only one that parses argv.
The JSON reader skips leading whitespace, so the prefix costs nothing and is
the cheapest way to pin a seed to that branch. Strip it and the seed silently
routes to a different branch, still "passing" while testing nothing here.

**Some seeds differ only in a trailing token.** `bundle-fault-out-of-scope` and
its `-bare` sibling take the same token down different paths (a separated value
is available, or is not). They add no new *lines*, but they do add branch
outcomes — 10 to 12 in `f2e_short_token_fault` — and libFuzzer's coverage is
edge-based, so the distinction is real. Judge a seed's worth with `gcov -b`,
not line percentages.

## Not reachable from this corpus, by design

`f2e_short_token_fault` classifies four faults. Seeds here reach *undeclared*
and *out-of-scope*. *Ambiguous* needs a short declared in two or more scopes
that are not the active one, and *no-env* needs a flag with an empty env
target; `tests/subcommands-deep/.cli-flags.toml` — the fixture these seeds are
scored against — expresses neither, and changing it would re-route every other
seed. Those two branches are instead reached through `case 1` of the harness,
which parses bundle-shaped argv against a *fuzzed* config, so a mutated config
supplies the shapes this fixture cannot.

Regenerate expectations for the parse contract with
`scripts/verify-bundle-contract.py --write`; this corpus needs no regeneration.
