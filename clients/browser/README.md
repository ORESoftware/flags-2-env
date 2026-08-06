# Browser / WebAssembly client

This client compiles the same `src/parser.c` used by the native CLI and language bindings to WebAssembly. It does **not** reimplement TOML or argv parsing in JavaScript.

The wrapper writes `.cli-flags.toml` to Emscripten's in-memory filesystem and calls only the existing explicit-path C APIs. Every heap-owned C result is copied into JavaScript and released with `f2e_free` before returning.

## Build

Install Emscripten, then run:

```sh
bash clients/browser/build.sh
python3 -m http.server 8000
```

Open `http://127.0.0.1:8000/clients/browser/demo/`.

The generated `clients/browser/dist/` directory is intentionally ignored. Release automation can build it from the reviewed C source instead of committing compiler output. The build copies the main-thread and worker wrappers plus their TypeScript declarations beside the generated module.

## Installable browser package

Release automation can turn the reviewed generated output into a dependency-free npm tarball:

```sh
bash clients/browser/build.sh
mkdir -p build/browser-npm
cp clients/browser/dist/* build/browser-npm/
node scripts/build-browser-npm-package.mjs \
  --dist build/browser-npm \
  --tar-dir build/browser-tarballs
```

The generated package is named `@oresoftware/f2e-browser`. It is intentionally separate from the root `@oresoftware/f2e` package so browser consumers do not inherit `node-gyp`, native install hooks, or Node-only exports.

After installing a reviewed tarball, import the public package paths:

```js
import { createFlags2Env } from "@oresoftware/f2e-browser";
import { createFlags2EnvWorker } from "@oresoftware/f2e-browser/worker";
```

The tarball contains only `flags2env.mjs`, `flags2env.wasm`, the main-thread and worker wrappers, TypeScript declarations, package metadata, the license, and this README. The package builder rejects any extra file before `npm pack` and audits the final npm file list, package name/version, exports, integrity digest, and absence of lifecycle scripts or dependencies.

## Main-thread API

```js
import { createFlags2Env } from "./dist/lib.mjs";

const flags2env = await createFlags2Env({ configText });
flags2env.parse(["tool", "serve", "--port", "8080"]);
flags2env.parseStructured(["tool", "serve", "worker", "--name", "alpha"]);
flags2env.resolveCommands(["tool", "serve", "worker"]);
flags2env.auditConfig();
flags2env.coerce({ PORT: "8080", DEBUG: "true" });
flags2env.helpTableForArgv("tool", ["tool", "serve", "--help"], 100);
```

Main-thread calls are synchronous once the module has initialized. Use this form for small, infrequent parses where blocking the UI thread is acceptable.

## Web Worker API

```js
import { createFlags2EnvWorker } from "./dist/worker-client.mjs";

const controller = new AbortController();
const flags2env = await createFlags2EnvWorker({
  configText,
  timeoutMs: 15_000,
  closeTimeoutMs: 15_000,
  maxPendingRequests: 128,
  signal: controller.signal,
});

await flags2env.parse(["tool", "serve", "--port", "8080"]);
await flags2env.parseStructured(["tool", "serve", "worker", "--name", "alpha"]);
await flags2env.setConfig(nextConfigText);
await flags2env.drain();
await flags2env.close();
```

Each worker owns a separate WebAssembly instance and MEMFS configuration. Use separate workers for independent configurations or parallel parsing.

`maxPendingRequests` bounds accepted work before another message is posted. Requests beyond that bound reject with `BusyError`; callers can inspect `pendingRequests` to apply their own queue or shed load. `drain()` waits only for already accepted requests. `close()` rejects new work, drains accepted work, then terminates the worker. A bounded close timeout terminates the worker and rejects with `TimeoutError` if accepted work cannot finish. Existing `terminate()` behavior remains immediate and idempotent.

A creation-level `AbortSignal` closes the entire worker lifecycle. Aborting rejects pending work with `AbortError`, terminates the worker, and causes subsequent requests to fail as closed. The signal is checked before creating a worker, so an already-aborted signal does not allocate a worker or WebAssembly instance.

A custom `workerUrl` may be supplied when bundlers or Content Security Policy require a different deployment path. The default is `new URL("./worker.mjs", import.meta.url)`.

## Security boundary

- The build disables Emscripten dynamic code execution.
- The demo uses a restrictive Content Security Policy and no remote scripts, styles, fonts, analytics, or network services.
- Config and argv values are copied into WebAssembly memory as UTF-8 strings.
- NUL bytes are rejected before C-string conversion.
- Configuration is limited to 1 MiB; argv is limited to 4,096 items, 64 KiB per item, and 4 MiB total.
- Worker request and response envelopes are limited to 4 MiB.
- Pending worker requests are bounded to a configurable maximum of 4,096 and default to 128.
- Worker errors expose only a bounded name/message pair; stacks and internal filesystem paths are not returned.
- Main-thread calls are fail-closed and non-reentrant. Worker clients serialize work through one isolated WebAssembly instance.
- Graceful close, immediate termination, AbortSignal shutdown, and timeout paths clear accepted-request timers and reject every pending promise.
- Returned pointers are never exposed to application code and are always freed.
- No SharedArrayBuffer, cross-origin isolation headers, or remote service is required.
- Browser callers should still treat configuration and argv as untrusted data and render returned help/output as text, not HTML.

## Test

The core browser workflow first runs deterministic fake-worker unit tests for overload, drain, close, timeout, abort, and idempotent termination. It then builds the module and runs the main-thread, worker, and lifecycle contracts in Chromium, Firefox, and WebKit through Playwright.

The browser-package workflow runs the package builder and `npm pack` contract on Linux, macOS, and Windows. It then extracts the actual tarball and imports only its packaged main-thread and worker paths in Chromium, Firefox, and WebKit. The packed test rejects source-tree fallback, extra package files, native install hooks, dependencies, external requests, console/page errors, broken `.wasm` relative loading, incomplete exports, and worker-relative URL regressions.
