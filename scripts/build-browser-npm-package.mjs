#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { copyFile, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const PACKAGE_NAME = "@oresoftware/f2e-browser";
const RUNTIME_FILES = [
  "LICENSE",
  "README.md",
  "flags2env.mjs",
  "flags2env.wasm",
  "lib.d.ts",
  "lib.mjs",
  "package.json",
  "worker-client.d.ts",
  "worker-client.mjs",
  "worker.mjs",
];

function optionValue(argv, index, option) {
  if (index + 1 >= argv.length) throw new Error(`${option} requires a value`);
  return argv[index + 1];
}

export function parseArguments(argv) {
  const result = { dist: null, tarDir: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--dist") {
      result.dist = optionValue(argv, index, argument);
      index += 1;
    } else if (argument === "--tar-dir") {
      result.tarDir = optionValue(argv, index, argument);
      index += 1;
    } else if (argument === "--help" || argument === "-h") {
      return { help: true };
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  if (!result.dist) throw new Error("--dist is required");
  if (!result.tarDir) throw new Error("--tar-dir is required");
  return result;
}

function packageMetadata(version) {
  return {
    name: PACKAGE_NAME,
    version,
    description: "The flags-2-env native C parser compiled to browser WebAssembly.",
    license: "MIT",
    type: "module",
    sideEffects: false,
    exports: {
      ".": {
        types: "./lib.d.ts",
        import: "./lib.mjs",
        default: "./lib.mjs",
      },
      "./worker": {
        types: "./worker-client.d.ts",
        import: "./worker-client.mjs",
        default: "./worker-client.mjs",
      },
      "./package.json": "./package.json",
    },
    files: RUNTIME_FILES.filter((file) => file !== "package.json"),
    publishConfig: { access: "public" },
    repository: {
      type: "git",
      url: "git+https://github.com/ORESoftware/flags-2-env.git",
      directory: "clients/browser",
    },
    keywords: ["cli", "env", "flags", "wasm", "webassembly", "browser"],
    engines: { node: ">=20.17" },
  };
}

async function assertExactDirectory(path) {
  const names = (await readdir(path)).sort();
  const expected = [...RUNTIME_FILES].sort();
  if (names.join("\0") !== expected.join("\0")) {
    throw new Error(
      `browser package directory mismatch\nexpected: ${expected.join(", ")}\nactual: ${names.join(", ")}`,
    );
  }
}

function assertPackageJson(metadata, rootVersion) {
  if (metadata.name !== PACKAGE_NAME || metadata.version !== rootVersion) {
    throw new Error("browser package name/version does not match the release source");
  }
  if (metadata.scripts || metadata.dependencies || metadata.optionalDependencies) {
    throw new Error("browser package must not contain lifecycle scripts or dependencies");
  }
  if (
    metadata.exports?.["."]?.import !== "./lib.mjs" ||
    metadata.exports?.["./worker"]?.import !== "./worker-client.mjs"
  ) {
    throw new Error("browser package exports are incomplete");
  }
}

function runNpmPack(dist, tarDir) {
  const result = spawnSync(
    "npm",
    ["pack", "--json", "--pack-destination", tarDir],
    { cwd: dist, encoding: "utf8", shell: process.platform === "win32" },
  );
  if (result.status !== 0) {
    throw new Error(`npm pack failed: ${result.stderr || result.stdout}`);
  }
  let records;
  try {
    records = JSON.parse(result.stdout);
  } catch (error) {
    throw new Error(`npm pack returned invalid JSON: ${error.message}`);
  }
  if (!Array.isArray(records) || records.length !== 1) {
    throw new Error("npm pack did not return exactly one package record");
  }
  const record = records[0];
  const files = record.files.map((entry) => entry.path).sort();
  const expected = [...RUNTIME_FILES].sort();
  if (files.join("\0") !== expected.join("\0")) {
    throw new Error(
      `packed browser file mismatch\nexpected: ${expected.join(", ")}\nactual: ${files.join(", ")}`,
    );
  }
  if (!Number.isInteger(record.size) || record.size <= 0 || !record.integrity) {
    throw new Error("npm pack did not report a valid size and integrity digest");
  }
  return record;
}

export async function buildBrowserPackage({ dist, tarDir }) {
  const distPath = resolve(dist);
  const tarPath = resolve(tarDir);
  const rootPackage = JSON.parse(await readFile(resolve(ROOT, "package.json"), "utf8"));
  const metadata = packageMetadata(rootPackage.version);
  assertPackageJson(metadata, rootPackage.version);

  await Promise.all([
    copyFile(resolve(ROOT, "LICENSE"), resolve(distPath, "LICENSE")),
    copyFile(resolve(ROOT, "clients/browser/README.md"), resolve(distPath, "README.md")),
  ]);
  await writeFile(
    resolve(distPath, "package.json"),
    `${JSON.stringify(metadata, null, 2)}\n`,
    "utf8",
  );
  await assertExactDirectory(distPath);

  await rm(tarPath, { recursive: true, force: true });
  await mkdir(tarPath, { recursive: true });
  const record = runNpmPack(distPath, tarPath);
  const tarball = resolve(tarPath, record.filename);
  return { metadata, record, tarball };
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(
      "usage: node scripts/build-browser-npm-package.mjs --dist BUILD_DIR --tar-dir TARBALL_DIR\n",
    );
    return;
  }
  const result = await buildBrowserPackage(args);
  process.stdout.write(
    `built ${result.metadata.name}@${result.metadata.version} at ${result.tarball}\n`,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`browser package build failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
