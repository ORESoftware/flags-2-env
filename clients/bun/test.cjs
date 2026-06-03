"use strict";

const assert = require("node:assert").strict;
const { apply, parse } = require("./lib.cjs");

process.chdir("../../tests/fixtures/nested/deeper");

const parsed = parse(["app", "--debug=t", "--port", "8181"]);
assert.equal(parsed.DEBUG, "true");
assert.equal(parsed.PORT, "8181");
assert.equal(parsed.COLOR, "true");

const explicit = parse(["app", "--debug=f"], { configPath: "../../.cli-flags.toml" });
assert.equal(explicit.DEBUG, "false");
assert.equal(explicit.PORT, "3000");

const combined = apply({ PORT: "env", KEEP: "1" }, ["app", "--port", "8181"]);
assert.equal(combined.PORT, "8181");
assert.equal(combined.KEEP, "1");
assert.equal(combined.COLOR, "true");
