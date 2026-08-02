# Browser / WebAssembly client

This client compiles the same `src/parser.c` used by the native CLI and language bindings to WebAssembly. It does **not** reimplement TOML or argv parsing in JavaScript.

The wrapper writes `.cli-flags.toml` to Emscripten's in-memory filesystem and calls only the existing explicit-path C APIs. Every heap-owned C result is copied into JavaScript and released with `f2e_free` before returning.

## Build

Install Emscripten, then run:

```sh
clients/browser/build.sh
python3 -m http.server 8000
```

Open `http://127.0.0.1:8000/clients/browser/demo/`.

The generated `clients/browser/dist/` directory is intentionally ignored. Release automation can build it from the reviewed C source instead of committing compiler output. The build copies `lib.mjs` and `lib.d.ts` beside the generated module.

## Browser API

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

## Security boundary

- The build disables Emscripten dynamic code execution.
- The demo uses a restrictive Content Security Policy and no remote scripts, styles, fonts, analytics, or network services.
- Config and argv values are copied into WebAssembly memory as UTF-8 strings.
- NUL bytes are rejected before C-string conversion.
- Configuration is limited to 1 MiB; argv is limited to 4,096 items, 64 KiB per item, and 4 MiB total.
- Calls are fail-closed and non-reentrant. Use one client instance per worker when parallel calls are required.
- Returned pointers are never exposed to application code and are always freed.
- Browser callers should still treat configuration and argv as untrusted data and render returned help/output as text, not HTML.

## Test

The GitHub Actions browser workflow builds the module and runs Chromium through Playwright. The test rejects external requests, console errors, page errors, invalid responsive layout, oversized/NUL-containing inputs, and regressions in parsing, canonical command resolution, subcommands, help, audit, coercion, and validation errors.
