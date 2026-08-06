import assert from "node:assert/strict";
import { chdir } from "node:process";

import { apply, auditConfig, auditConfigStatus, auditEnv, auditEnvStatus, coerce, CoercionError, completionScript, generateTypes, helpTable, helpTableForArgv, parse, parseOverridesFromArgs, parseStructured, resolveCommands, parseFromArgs } from "./lib.ts";

chdir("../../tests/fixtures/nested/deeper");

const parsed = parse(["app", "--debug=t", "--port", "8181"]);
assert.equal(parsed.DEBUG, "true");
assert.equal(parsed.PORT, "8181");
assert.equal(parsed.COLOR, "true");

const explicit = parse(["app", "--debug=f"], { configPath: "../../.cli-flags.toml" });
assert.equal(explicit.DEBUG, "false");
assert.equal(explicit.PORT, "3000");

const fromArgs = parseFromArgs(["app", "--port", "8182"], { configPath: "../../.cli-flags.toml" });
assert.equal(fromArgs.PORT, "8182");

type CliStuff = {
  PORT: number;
  DEBUG: boolean;
  COLOR: boolean;
};
const defaultFreeOverrides = parseOverridesFromArgs(["app", "--debug=f"], { configPath: "../../.cli-flags.toml" });
const typedConfig: CliStuff = coerce({ PORT: "9191", ...defaultFreeOverrides }, { configPath: "../../.cli-flags.toml" });
assert.equal(typedConfig.PORT, 9191);
assert.equal(typedConfig.DEBUG, false);
const cliWins = parseOverridesFromArgs(["app", "--port=8182"], { configPath: "../../.cli-flags.toml" });
assert.equal(coerce<CliStuff>({ PORT: "9191", ...cliWins }, { configPath: "../../.cli-flags.toml" }).PORT, 8182);
let strictParseMessage = "";
try {
  parseOverridesFromArgs(["app", "--api-token=must-not-leak"], { configPath: "../../.cli-flags.toml" });
} catch (error: unknown) {
  assert.ok(error instanceof TypeError);
  strictParseMessage = error.message;
}
assert.match(strictParseMessage, /rejected 1 unknown option/);
assert.doesNotMatch(strictParseMessage, /must-not-leak/);

const codegenConfig = "../../../codegen/.cli-flags.toml";
const richTypes = coerce({ RATIO: "1.25", ITEMS: "[3,4]", LABELS: '{"tier":2}' }, { configPath: codegenConfig });
assert.deepEqual(richTypes, {
  PORT: 3000,
  RATIO: 1.25,
  DEBUG: false,
  ITEMS: [3, 4],
  LABELS: { tier: 2 },
  UNTYPED: "123",
});
assert.throws(
  () => coerce({ PORT: "bad", DEBUG: "maybe" }, { configPath: codegenConfig }),
  (error: unknown) => error instanceof CoercionError
    && error.errors.length === 2
    && error.errors[0].includes("flags.port.type"),
);
const invalidCli = parseFromArgs(["app", "--ratio=nan"], { configPath: codegenConfig });
assert.throws(
  () => coerce(invalidCli, { configPath: codegenConfig }),
  (error: unknown) => error instanceof CoercionError && error.errors.some((message) => message.includes("flags.ratio")),
);
const generated = generateTypes("typescript", { configPath: codegenConfig, typeName: "CliStuff" });
assert.match(generated, /export interface CliStuff/);
assert.match(generated, /LABELS: Record<string, unknown>/);
assert.match(generated, /UNTYPED: string/);

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
  write(chunk: string) {
    printed += chunk;
  },
});
assert.equal(printed, narrowTable);
assert.match(narrowTable, /\| Details/);
assert.match(narrowTable, /More help: https:\/\/example\.com\/flags2env\/help/);
assert.doesNotMatch(narrowTable, /\| Description/);
assert.throws(() => help.printTable(null as never), /write\(chunk\)/);

const wideTable = helpTable("app", { configPath: "../../.cli-flags.toml", terminalColumns: 132 });
assert.match(wideTable, /\| Description/);
assert.match(wideTable, /TCP port for the app listener\./);

const subcommandsConfig = "../../../subcommands/.cli-flags.toml";
const scopedTable = helpTableForArgv("gitish", ["gitish", "remote", "add", "--help"], {
  configPath: subcommandsConfig,
  terminalColumns: 100,
});
assert.match(scopedTable, /Command: gitish remote add \[OPTIONS\]/);
assert.match(scopedTable, /Add a remote\./);
assert.match(scopedTable, /--fetch/);
const topTable = helpTableForArgv("gitish", ["gitish", "--help"], {
  configPath: subcommandsConfig,
  terminalColumns: 100,
});
assert.match(topTable, /Commands:/);
assert.match(topTable, /remote add/);
const scopedParse = parse(["gitish", "add", "-A"], { configPath: subcommandsConfig });
assert.equal(scopedParse.GITISH_COMMAND, "add");
assert.equal(scopedParse.GITISH_ADD_ALL, "true");

const structured = parseStructured(["gitish", "remote", "add", "-f", "abc", "efg"], { configPath: subcommandsConfig });
assert.equal(structured.command, "remote add");
assert.deepEqual(structured.subcommands, ["remote", "add"]);
assert.deepEqual(structured.extras, ["abc", "efg"]);
assert.equal(structured.flags.GITISH_REMOTE_ADD_FETCH, "true");
assert.equal(structured.providedFlags.GITISH_REMOTE_ADD_FETCH, "true");
assert.equal(structured.providedFlags.GITISH_VERBOSE, undefined);
assert.deepEqual(structured.unknownOptions, []);
assert.deepEqual(structured.errors, []);
assert.equal(structured.isHelpMenu, false);

const structuredDashed = parseStructured(["gitish", "remote", "add", "--", "xyz", "-q"], { configPath: subcommandsConfig });
assert.deepEqual(structuredDashed.extras, ["xyz", "-q"]);

const structuredTypo = parseStructured(["gitish", "commit", "--wat"], { configPath: subcommandsConfig });
assert.deepEqual(structuredTypo.unknownOptions, ["--wat"]);

const resolved = resolveCommands(["gitish", "remote", "add", "-f"], { configPath: subcommandsConfig });
assert.deepEqual(resolved, { path: ["remote", "add"], label: "remote add" });
const resolvedNone = resolveCommands(["gitish", "--verbose"], { configPath: subcommandsConfig });
assert.deepEqual(resolvedNone, { path: [], label: "" });

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
