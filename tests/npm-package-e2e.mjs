#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const workspace = mkdtempSync(join(tmpdir(), "flags2env-npm-e2e-"));
const packageDir = join(workspace, "package");
const consumerDir = join(workspace, "consumer");
const npm = "npm";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || root,
    encoding: "utf8",
    env: { ...process.env, ...options.env },
    shell: options.shell || false,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(
      [
        `${command} ${args.join(" ")} exited with ${result.status}`,
        result.stdout,
        result.stderr,
      ]
        .filter(Boolean)
        .join("\n"),
    );
  }
  return result.stdout.trim();
}

try {
  mkdirSync(packageDir, { recursive: true });
  mkdirSync(consumerDir, { recursive: true });

  const packed = JSON.parse(
    run(npm, ["pack", "--json", "--pack-destination", packageDir], {
      shell: process.platform === "win32",
    }),
  );
  assert.equal(packed.length, 1);
  const tarball = join(packageDir, packed[0].filename);
  assert.ok(existsSync(tarball), `missing npm tarball: ${tarball}`);

  writeFileSync(
    join(consumerDir, "package.json"),
    JSON.stringify({ name: "flags2env-e2e-consumer", private: true }, null, 2),
  );
  run(
    npm,
    [
      "install",
      "--no-audit",
      "--no-fund",
      "--no-package-lock",
      "--save-exact",
      tarball,
    ],
    { cwd: consumerDir, shell: process.platform === "win32" },
  );

  const installed = join(
    consumerDir,
    "node_modules",
    "@oresoftware",
    "f2e",
  );
  const cli = join(installed, "clients", "nodejs", "cli.mjs");
  const config = join(consumerDir, ".cli-flags.toml");
  assert.ok(existsSync(cli), "installed package is missing the CLI");
  assert.ok(
    existsSync(
      join(
        installed,
        "clients",
        "nodejs",
        "build",
        "Release",
        "flags2env.node",
      ),
    ),
    "installed package did not build its native addon",
  );
  assert.ok(!existsSync(join(installed, "tests")), "npm package leaked repository tests");

  writeFileSync(
    config,
    `[parse]
command_env = "E2E_COMMAND"
unknown_options_env = "E2E_UNKNOWN"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
short = "d"
type = "bool"
default = false

[commands.run]
help = "Run the fixture."

[commands.run.flags.port]
env = "PORT"
aliases = ["port"]
short = "p"
type = "integer"
default = 3000
`,
  );

  const cliParsed = JSON.parse(
    run(
      process.execPath,
      [cli, "run", "--port", "8181", "--debug"],
      { cwd: consumerDir },
    ),
  );
  assert.deepEqual(cliParsed, {
    DEBUG: "true",
    E2E_COMMAND: "run",
    PORT: "8181",
  });

  const audit = JSON.parse(
    run(process.execPath, [cli, "audit", config], { cwd: consumerDir }),
  );
  assert.deepEqual(audit, {
    ok: true,
    errorCount: 0,
    warningCount: 0,
    errors: [],
    warnings: [],
  });

  const cjsOutput = run(
    process.execPath,
    [
      "-e",
      `const assert = require("node:assert/strict");
const f2e = require("@oresoftware/f2e");
const result = f2e.parseStructured(
  ["consumer", "run", "-p", "9191", "-d"],
  {configPath: ${JSON.stringify(config)}}
);
assert.deepEqual(result.flags, {DEBUG: "true", E2E_COMMAND: "run", PORT: "9191"});
assert.equal(result.command, "run");
assert.deepEqual(result.subcommands, ["run"]);
process.stdout.write("cjs ok");`,
    ],
    { cwd: consumerDir },
  );
  assert.equal(cjsOutput, "cjs ok");

  const esmOutput = run(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `import assert from "node:assert/strict";
import {parse, resolveCommands} from "@oresoftware/f2e";
const options = {configPath: ${JSON.stringify(config)}};
assert.deepEqual(
  parse(["consumer", "run", "--port=7171"], options),
  {DEBUG: "false", E2E_COMMAND: "run", PORT: "7171"}
);
assert.deepEqual(
  resolveCommands(["consumer", "run"], options),
  {path: ["run"], label: "run"}
);
process.stdout.write("esm ok");`,
    ],
    { cwd: consumerDir },
  );
  assert.equal(esmOutput, "esm ok");

  const installedManifest = JSON.parse(
    readFileSync(join(installed, "package.json"), "utf8"),
  );
  assert.equal(installedManifest.name, "@oresoftware/f2e");
  assert.equal(installedManifest.bin.f2e, "./clients/nodejs/cli.mjs");
  process.stdout.write("npm package e2e passed\n");
} finally {
  rmSync(workspace, { recursive: true, force: true });
}
