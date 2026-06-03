import { strict as assert } from "node:assert";

import { parse } from "./lib.ts";

process.chdir("../../tests/fixtures/nested/deeper");

const parsed = parse(["app", "--debug=t", "--port", "8181"]);
assert.equal(parsed.DEBUG, "true");
assert.equal(parsed.PORT, "8181");
assert.equal(parsed.COLOR, "true");
