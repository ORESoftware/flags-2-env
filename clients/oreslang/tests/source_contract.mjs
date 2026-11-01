import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../src/flags2env.ores", import.meta.url), "utf8");
const scalar = await readFile(new URL("./abi-status-scalar.ores", import.meta.url), "utf8");
const header = await readFile(new URL("../native/flags2env_ores_bridge.h", import.meta.url), "utf8");

for (const token of ["status_ok", "status_name", "host_parse_blocking_with", "host_coerce_blocking_with", "HostReply"]) {
  assert.match(source, new RegExp("\\b" + token + "\\b"));
}
assert.doesNotMatch(source, /\bnull\b/);
assert.doesNotMatch(source, /\basync\b/);
assert.doesNotMatch(source, /(?:^|\s)[*&][A-Za-z_]/m);
assert.match(scalar, /pub fnc main\(\): int/);
assert.match(scalar, /return[\s\S]*- 1192;/);

for (const [name, value] of [
  ["F2E_ORES_OK", 0],
  ["F2E_ORES_INVALID_INPUT", 1],
  ["F2E_ORES_NATIVE_FAILURE", 2],
  ["F2E_ORES_INPUT_TOO_LARGE", 3],
  ["F2E_ORES_OUTPUT_TOO_LARGE", 4],
  ["F2E_ORES_RELEASED", 5],
]) {
  assert.match(header, new RegExp(name + "\\s*=\\s*" + value + "\\b"));
}
console.log("ORES-FLAGS2ENV-SOURCE-CONTRACT-PASS|cases=17");
