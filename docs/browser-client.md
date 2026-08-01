# Browser WebAssembly client

The browser client runs the same `src/parser.c` core used by the native clients. It does not reimplement TOML parsing or flag resolution in JavaScript.

## Build

Install Emscripten, install the Node development dependencies, and build the self-contained ES module:

```bash
npm ci
npm run build:browser
```

The output is `clients/browser/dist/flags2env.mjs`. `-sSINGLE_FILE=1` embeds the WebAssembly payload in that local ES module, so loading the client does not fetch a separate `.wasm` file.

## Usage

```js
import { createFlags2EnvBrowser } from "@oresoftware/f2e/browser";

const client = await createFlags2EnvBrowser(`
[flags.verbose]
env = "APP_VERBOSE"
aliases = ["verbose"]
type = "bool"
default = "false"
`);

const parsed = client.parseStructured(["app", "--verbose"]);
console.log(parsed.flags.APP_VERBOSE); // "true"
```

A client is bound to one immutable contract. Create a second client instance when the contract changes. Each instance has its own Emscripten virtual filesystem.

## Exposed operations

* `parse(argv)`
* `parseStructured(argv)`
* `resolveCommands(argv)`
* `auditConfig()`
* `helpTableForArgv(command, argv, terminalColumns)`
* `completionScript(shell, command)`
* `coerce(values)`

## Security boundary

* The configuration is written only to the instance-local Emscripten MEMFS.
* The generated module is a self-contained local ES module. The build rejects `fetch`, XHR, WebSocket, `eval`, and `new Function` primitives.
* Runtime arguments, configuration size, item count, and individual argument size are bounded before crossing the WebAssembly boundary.
* NUL bytes are rejected before C string conversion.
* Every owned C string is copied with `UTF8ToString` and released with `f2e_free` in a `finally` block.
* Calls are fail-closed and non-reentrant. Workers should use one client instance per worker.
* The demo uses a restrictive Content Security Policy and renders parser output with `textContent`; contract help text is never interpreted as HTML.

The browser client does not expose process argument discovery, upward filesystem discovery, environment mutation, or terminal printing because those concepts do not exist safely in a browser runtime.

## Browser tests

```bash
npx playwright install chromium firefox webkit
npm run test:browser
```

The Playwright suite compares browser output with the native Node addon, exercises aliases, structured parsing, audits, coercion, help rendering, invalid input, memory ownership, keyboard navigation, CSP behavior, and narrow-screen layout.
