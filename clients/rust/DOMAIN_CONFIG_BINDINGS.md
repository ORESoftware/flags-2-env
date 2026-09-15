# Domain config bindings

Domain config files such as `.ores-chat.toml`, `.ores-forms.toml`, `.opto-sync.toml`, `.ores-mw.toml`, `.ores-rl.toml`, `.ores-lru.toml`, `.ores-lock.toml`, `.auth-shared.toml`, `.ores-rpc.toml`, and `.ores-legal.toml` are not flags-2-env schemas.

Each domain owns its independent TypeSpec and hand-authored JSON Schema contract and admits its TOML before runtime binding. After admission, the domain adapter passes only its symbolic field -> environment-key declarations to `flags2env::env_map::resolve_bindings` together with the final immutable `EnvMap` produced after CLI overrides.

This preserves one precedence path:

1. copy process environment;
2. parse `.cli-flags.toml` through flags-2-env;
3. merge CLI overrides into an immutable `EnvMap`;
4. parse and validate the domain TOML in the domain package;
5. resolve its declared environment-key bindings with `resolve_bindings`;
6. build the server/CLI runtime from the resolved values.

`resolve_bindings` does not parse argv, read `std::env`, read TOML, perform network I/O, or display resolved values in errors. Missing or empty declared values, malformed portable env-key names, and one env key silently controlling multiple semantic fields fail closed.

The domain package remains responsible for semantic checks such as URL/callback identity, server/client role, admin/customer separation, rate-limit bounds, middleware ordering, RPC contract selection, offline synchronization policy, lock-provider selection and lease/wait timing, or chat/legal/forms domain rules. Those semantics must not be duplicated in flags-2-env.

For `.ores-lock.toml` specifically, flags-2-env resolves only declared names such as `ORES_LOCK_ROOT`, `FIDUCIA_BASE_URL`, `FIDUCIA_AUTH_TOKEN`, and `DATABASE_URL`. `ORESoftware/ores-locks-and-leases` remains the authority for profile selection, provider enablement, PostgreSQL lock scope, wait/retry/TTL/renewal invariants, fencing behavior, and local-file safety rules. Package mechanics remain in `.zpkg.toml` and are not part of this binding path.
