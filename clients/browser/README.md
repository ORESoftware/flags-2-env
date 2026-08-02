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

const flags2env = await createFlags2EnvWorker({
  configText,
  timeoutMs: 15_000,
});

await flags2env.parse(["tool", "serve", "--port", "8080"]);
await flags2env.parseStructured(["tool", "serve", "worker", "--name", "alpha"]);
await flags2env.setConfig(nextConfigText);
flags2env.terminate();
```

Each worker owns a separate WebAssembly instance and MEMFS configuration. Use separate workers for independent configurations or parallel parsing. Requests carry numeric IDs, are bounded before transfer, and reject deterministically on timeout, worker failure, or termination. Call `terminate()` when the client is no longer needed; later requests fail with a closed-state error.

A custom `workerUrl` may be supplied when bundlers or Content Security Policy require a different deployment path. The default is `new URL("./worker.mjs", import.meta.url)`.

## Security boundary

- The build disables Emscripten dynamic code execution.
- The demo uses a restrictive Content Security Policy and no remote scripts, styles, fonts, analytics, or network services.
- Config and argv values are copied into WebAssembly memory as UTF-8 strings.
- NUL bytes are rejected before C-string conversion.
- Configuration is limited to 1 MiB; argv is limited to 4,096 items, 64 KiB per item, and 4 MiB total.
- Worker request and response envelopes are limited to 4 MiB.
- Worker errors expose only a bounded name/message pair; stacks and internal filesystem paths are not returned.
- Main-thread calls are fail-closed and non-reentrant. Worker clients serialize work through one isolated WebAssembly instance.
- Returned pointers are never exposed to application code and are always freed.
- No SharedArrayBuffer, cross-origin isolation headers, or remote service is required.
- Browser callers should still treat configuration and argv as untrusted data and render returned help/output as text, not HTML.

## Test

The GitHub Actions browser workflow builds the module and runs the same main-thread and worker contract in Chromium, Firefox, and WebKit through Playwright. The suite rejects external requests, console errors, page errors, invalid responsive layout, oversized/NUL-containing inputs, worker state leakage, timeout/termination regressions, and regressions in parsing, canonical command resolution, subcommands, help, audit, coercion, and validation errors.
