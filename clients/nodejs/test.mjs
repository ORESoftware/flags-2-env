import assert from "node:assert/strict";
import { chdir } from "node:process";

import { apply, auditConfig, auditConfigStatus, auditEnv, auditEnvStatus, completionScript, helpTable, parse } from "./lib.mjs";

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

const help = parse(["app", "--help"], { configPath: "../../.cli-flags.toml" });
assert.equal(help.isHelpMenu, true);
assert.equal(Object.keys(help).includes("isHelpMenu"), false);
assert.equal(Object.keys(help).includes("printTable"), false);
let printed = "";
const narrowTable = help.printTable({
  columns: 70,
  write(chunk) {
    printed += chunk;
  },
});
assert.equal(printed, narrowTable);
assert.match(narrowTable, /\| Details/);
assert.match(narrowTable, /More help: https:\/\/example\.com\/flags2env\/help/);
assert.doesNotMatch(narrowTable, /\| Description/);
assert.throws(() => help.printTable(null), /write\(chunk\)/);

const wideTable = helpTable("app", { configPath: "../../.cli-flags.toml", terminalColumns: 132 });
assert.match(wideTable, /\| Description/);
assert.match(wideTable, /TCP port for the app listener\./);

const bashCompletion = completionScript("bash", "mycli", { configPath: "../../.cli-flags.toml" });
assert.match(bashCompletion, /_flags2env_complete_mycli/);
assert.match(bashCompletion, /--listen-port=/);
assert.match(completionScript("zsh", "/usr/local/bin/mycli/", { configPath: "../../.cli-flags.toml" }), /#compdef mycli/);
assert.throws(() => completionScript("bash", "/", { configPath: "../../.cli-flags.toml" }), /completion script/);
assert.throws(() => completionScript("bash", "bad;name", { configPath: "../../.cli-flags.toml" }), /completion script/);

const invalidConfigPath = "../../../audit-invalid-env-only/.cli-flags.toml";
const invalidConfigAudit = auditConfig({ configPath: invalidConfigPath });
assert.equal(invalidConfigAudit.ok, false);
assert.equal(invalidConfigAudit.errors[0], 'flags.bad env "BAD-NAME" is not a valid env var name');
assert.equal(auditConfigStatus({ configPath: invalidConfigPath }), 1);
assert.throws(() => completionScript("bash", "mycli", { configPath: invalidConfigPath }), /completion script/);

const cleanAudit = auditEnv({
  configPath: "../../../env-audit-clean/.cli-flags.toml",
  envPath: "../../../env-audit-clean/.env",
});
assert.equal(cleanAudit.ok, true);
assert.equal(auditEnvStatus({
  configPath: "../../../env-audit-clean/.cli-flags.toml",
  envPath: "../../../env-audit-clean/.env",
}), 0);
