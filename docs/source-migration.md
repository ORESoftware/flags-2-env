# Source repository migration

`https://github.com/flags-2-env/flags-2-env` is the canonical source
repository. `https://github.com/ORESoftware/flags-2-env` is a supported,
commit-identical compatibility mirror through 2026-08-19.

The machine-readable contract is `source-migration.json`; its JSON Schema is
`source-migration.schema.json`. Validate the repository metadata and transition
window with:

```sh
python3 scripts/verify-source-migration.py
```

After both repositories exist and have been published, also compare their
supported refs over the network:

```sh
python3 scripts/verify-source-migration.py --check-remotes
```

## Identity boundary

The canonical Zed package identity is `flags-2-env/flags-2-env@0.3.0`. Current
Zed manifests and registry metadata have no package alias or redirect field.
The compatibility identity `oresoftware/flags-2-env@0.3.0` must therefore be a
separate publication, not an alias.

The root `.zpkg.toml` is always the canonical manifest. The compatibility
publisher creates a disposable local clone at the reviewed `v0.3.0` commit,
changes only `[package].org` to `oresoftware`, and invokes `zed publish
--allow-dirty`. Zed still verifies that `v0.3.0` resolves to the clone's `HEAD`,
so both registry coordinates record the same immutable source commit. The
artifacts have different digests because the embedded package identity differs;
their remaining files must be identical.

The Go module path also remains
`github.com/oresoftware/flags-2-env/clients/golang`. Changing that path would be
a separate module-identity migration and would break existing import paths.

## Publication order

1. Create `flags-2-env/flags-2-env` without transferring, renaming, archiving,
   or deleting `ORESoftware/flags-2-env`.
2. Push the reviewed main history and every existing tag to the canonical
   repository without force.
3. Verify a clean canonical clone, the formal-methods workflow, the custom
   borrow checker, the Zed package round trip, and package metadata.
4. Tag the reviewed release commit as `v0.3.0`, then publish
   `flags-2-env/flags-2-env@0.3.0` from its clean canonical manifest.
5. Run `scripts/publish-zed-compatibility.sh --release` before the compatibility
   cutoff. This publishes `oresoftware/flags-2-env@0.3.0` from the same tagged
   commit with only the package-org field overlaid.
6. Fast-forward the compatibility repository to the exact canonical `main`
   object and publish the exact same tag objects. Do not create a compatibility
   merge commit.
7. Run `verify-source-migration.py --check-remotes`; it requires canonical and
   compatibility `main` plus every tag to resolve to identical object IDs.
8. During the support window, publish fixes, tags, and release assets to the
   canonical repository first and the compatibility repository second. A
   publication is incomplete until parity is verified.

The compatibility repository keeps its existing pull-request and issue history.
New changes are reviewed against the canonical repository; open legacy work is
rebased or replayed as an ordinary reviewed commit, never by rewriting either
repository's public history.

## Cutoff and rollback

Do not remove compatibility support before the end of 2026-08-19. After the
cutoff, the original repository may remain as a read-only historical source and
redirect notice; it need not be deleted or transferred.

If the two repositories diverge, stop publication. Repair the canonical branch
with a new reviewed commit, then fast-forward the compatibility branch. Never
force-push, delete refs, or reset either public history to manufacture parity.
