import assert from "node:assert/strict";

import * as f2e from "@oresoftware/f2e";
import type { CliStuff } from "./cli-interfaces.js";

const environmentOnly = f2e.parseOverridesFromArgs(["node", "app"]);
const environmentConfig: CliStuff = f2e.coerce({ PORT: "5151", ...environmentOnly });
assert.equal(environmentConfig.PORT, 5151);

const raw = f2e.parseOverridesFromArgs([
  "node",
  "app",
  "--port",
  "4242",
  "--ratio",
  "0.25",
  "--debug=yes",
  "--name",
  "matrix",
  "--items",
  '[1,"two"]',
  "--labels",
  '{"region":"test"}',
  "--payload",
  '{"enabled":true}',
  "--untyped",
  "456",
]);

const config = { ...process.env, ...raw };
const typedConfig: CliStuff = f2e.coerce(config);

assert.equal(typedConfig.PORT, 4242);
assert.equal(typedConfig.RATIO, 0.25);
assert.equal(typedConfig.DEBUG, true);
assert.equal(typedConfig.NAME, "matrix");
assert.deepEqual(typedConfig.ITEMS, [1, "two"]);
assert.deepEqual(typedConfig.LABELS, { region: "test" });
assert.deepEqual(typedConfig.PAYLOAD, { enabled: true });
assert.equal(typedConfig.UNTYPED, "456");

assert.throws(
  () => f2e.coerce({ ...config, PORT: "not-an-integer" }),
  (error: unknown) => error instanceof f2e.CoercionError
    && error.errors.some((message) => message.includes("flags.port"))
    && error.errors.some((message) => message.includes('type = "integer"'))
    && error.errors.some((message) => message.includes("Set PORT to an integer")),
);

console.log("nodejs generated interface and coerce runtime passed");
