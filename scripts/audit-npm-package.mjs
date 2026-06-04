#!/usr/bin/env node
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const allowedClientPrefixes = new Set([
  "clients/bun/",
  "clients/deno/",
  "clients/nodejs/",
]);
const allowedClientFiles = new Set([
  "clients/README.md",
]);

const cache = mkdtempSync(join(tmpdir(), "flags2env-npm-pack-"));
const result = spawnSync("npm", ["pack", "--dry-run", "--json"], {
  cwd: new URL("..", import.meta.url),
  env: { ...process.env, npm_config_cache: join(cache, "npm-cache") },
  encoding: "utf8",
});

if (result.status !== 0) {
  process.stderr.write(result.stderr || result.stdout);
  process.exit(result.status ?? 1);
}

const pack = JSON.parse(result.stdout)[0];
const files = pack.files.map((file) => file.path);
const disallowed = files.filter((path) => {
  if (!path.startsWith("clients/")) {
    return false;
  }
  if (allowedClientFiles.has(path)) {
    return false;
  }
  return ![...allowedClientPrefixes].some((prefix) => path.startsWith(prefix));
});

if (disallowed.length > 0) {
  process.stderr.write(`npm package includes non-JS clients:\n${disallowed.join("\n")}\n`);
  process.exit(1);
}

for (const required of ["clients/nodejs/lib.mjs", "clients/bun/lib.mjs", "clients/deno/mod.ts", "src/parser.c"]) {
  if (!files.includes(required)) {
    process.stderr.write(`npm package is missing required file: ${required}\n`);
    process.exit(1);
  }
}

console.log(`npm package audit passed (${files.length} files)`);

