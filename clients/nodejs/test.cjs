"use strict";

const assert = require("node:assert/strict");
const { chdir } = require("node:process");
const { parse } = require("./lib.cjs");

chdir("../../tests/fixtures/nested/deeper");

const parsed = parse(["app", "--debug=t", "--port", "8181"]);
assert.equal(parsed.DEBUG, "true");
assert.equal(parsed.PORT, "8181");
assert.equal(parsed.COLOR, "true");
