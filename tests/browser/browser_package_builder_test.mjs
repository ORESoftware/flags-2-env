import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  buildBrowserPackage,
  parseArguments,
} from "../../scripts/build-browser-npm-package.mjs";

const generatedFiles = [
  "flags2env.mjs",
  "flags2env.wasm",
  "lib.d.ts",
  "lib.mjs",
  "lifecycle.mjs",
  "worker-client.d.ts",
  "worker-client.mjs",
  "worker.mjs",
];

async function withGeneratedDist(callback) {
  const root = await mkdtemp(join(tmpdir(), "flags2env-browser-package-"));
  const dist = join(root, "dist");
  const tarDir = join(root, "tarballs");
  try {
    await import("node:fs/promises").then(({ mkdir }) => mkdir(dist));
    for (const file of generatedFiles) {
      const content = file.endsWith(".wasm")
        ? Buffer.from([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00])
        : `// ${file}\n`;
      await writeFile(join(dist, file), content);
    }
    await callback({ root, dist, tarDir });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("builder emits an exact dependency-free browser package", async () => {
  await withGeneratedDist(async ({ dist, tarDir }) => {
    const result = await buildBrowserPackage({ dist, tarDir });
    assert.equal(result.metadata.name, "@oresoftware/f2e-browser");
    assert.equal(result.metadata.type, "module");
    assert.equal(result.metadata.sideEffects, false);
    assert.equal(result.metadata.exports["."].import, "./lib.mjs");
    assert.equal(
      result.metadata.exports["./worker"].import,
      "./worker-client.mjs",
    );
    assert.equal("scripts" in result.metadata, false);
    assert.equal("dependencies" in result.metadata, false);
    assert.ok(result.record.integrity.startsWith("sha512-"));
    assert.ok(result.record.size > 0);
    assert.ok(result.tarball.endsWith(".tgz"));

    const packageJson = JSON.parse(await readFile(join(dist, "package.json"), "utf8"));
    assert.deepEqual(packageJson, result.metadata);
  });
});

test("builder rejects extra files before packing", async () => {
  await withGeneratedDist(async ({ dist, tarDir }) => {
    await writeFile(join(dist, "secret.txt"), "must not ship");
    await assert.rejects(
      buildBrowserPackage({ dist, tarDir }),
      /browser package directory mismatch/,
    );
  });
});

test("builder CLI parsing is strict", () => {
  assert.deepEqual(
    parseArguments(["--dist", "d", "--tar-dir", "t"]),
    { dist: "d", tarDir: "t" },
  );
  assert.throws(() => parseArguments(["--dist"]), /requires a value/);
  assert.throws(() => parseArguments(["--wat"]), /unknown argument/);
  assert.throws(() => parseArguments(["--dist", "d"]), /--tar-dir is required/);
});
