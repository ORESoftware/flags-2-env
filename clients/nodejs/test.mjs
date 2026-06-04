import assert from "node:assert/strict";
import { chdir } from "node:process";

import { apply, auditEnv, auditEnvStatus, completionScript, parse } from "./lib.mjs";

chdir("../../tests/fixtures/nested/deeper");

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

const bashCompletion = completionScript("bash", "mycli", { configPath: "../../.cli-flags.toml" });
assert.match(bashCompletion, /_flags2env_complete_mycli/);
assert.match(bashCompletion, /--listen-port=/);

const cleanAudit = auditEnv({
  configPath: "../../../env-audit-clean/.cli-flags.toml",
  envPath: "../../../env-audit-clean/.env",
});
assert.equal(cleanAudit.ok, true);
assert.equal(auditEnvStatus({
  configPath: "../../../env-audit-clean/.cli-flags.toml",
  envPath: "../../../env-audit-clean/.env",
}), 0);
