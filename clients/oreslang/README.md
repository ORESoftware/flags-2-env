# flags2env — Oreslang client (native bridge, experimental)

This directory contains the Oreslang client source contract and an ABI-stable host adapter. The client is implemented, but **release support remains evidence-gated** until the backend PRs execute the same pinned fixture and the full String/Fnc host path is demonstrated where each backend claims it.

## Contract

- `f2e_ores_parse(config, argv_json)`: parse explicit argv JSON against a
  reviewed, absolute `.cli-flags.toml` path; return a UTF-8 JSON map.
- `f2e_ores_coerce(config, values_json)`: invoke the native typed-coercion
  boundary; return its JSON report, not a guessed map.
- Both return `f2e_ores_result { data, length, status }`. Status 0 is success,
  1 is invalid input, and 2 is native parser failure. A null pointer is never
  silently interpreted as an empty configuration.
- The caller must copy result bytes into actor-owned memory **before**
  `f2e_ores_free`. Free exactly once; the function clears the result.
- No environment mutation occurs in the bridge. A higher-level Oreslang
  adapter should return a typed Result, and any application of parsed values
  must be explicit at startup, never implicit in an actor handler.
- Use `rt borrow` for input views and `rt take` for owned result copies;
  do not expose raw C pointers or pointer syntax in public Oreslang APIs.
- The synchronous C ABI must run only on a dedicated host/CONTROL admission
  boundary, not on Oreslang actor carriers. Provide an asynchronous guest API.

## Building

Compile `native/flags2env_ores_bridge.c` with `src/parser.c` and include
`src/parser.h`. The C bridge intentionally shares the canonical parser rather
than implementing flag semantics separately for each backend.

## Required release gates

1. Bind this ABI in Oreslang Java/Graal, LLVM, WASM and .NET host runtimes;
   WASM must use an explicit host import rather than assuming C FFI.
2. Test exact JSON bytes and typed coercion against the existing C fixtures.
3. Reject relative config paths, null inputs, malformed argv JSON, unknown
   flags, schema errors, and symlinked/untrusted config files.
4. Verify byte ownership, double-free safety, bounded input/output, timeout,
   cancellation, and cross-tenant isolation.
5. Compile and execute identical native `.ores` guest fixtures on each
   backend. Unsupported backends are not passes.
6. Require exact-head stepful CI, compiler hashes, guest receipts and review.

Do not publish or advertise supported status until these gates pass.
