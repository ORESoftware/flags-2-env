import assert from "node:assert/strict";
import { chdir } from "node:process";

import { parse } from "./lib.ts";

chdir("../../tests/fixtures/nested/deeper");

const parsed = parse(["app", "--debug=t", "--port", "8181"]);
assert.equal(parsed.DEBUG, "true");
assert.equal(parsed.PORT, "8181");
assert.equal(parsed.COLOR, "true");
