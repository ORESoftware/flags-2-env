#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { access, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const manifestPath = resolve(root, "formal/application-surfaces.json");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const knownMachines = new Set([
  "demo",
  "main-thread",
  "worker-client",
  "worker-host",
]);
const knownKinds = new Set(["browser-app", "browser-runtime", "desktop-app"]);

function assertRepositoryPath(path) {
  assert.equal(typeof path, "string");
  assert.ok(path.length > 0 && path.length <= 240);
  assert.equal(path.startsWith("/"), false);
  assert.equal(path.includes("\\"), false);
  assert.equal(path.split("/").some((part) => part === ".."), false);
  return resolve(root, path);
}

assert.equal(manifest.$schema, "./application-surfaces.schema.json");
assert.equal(manifest.schemaVersion, "flags2env.application-surfaces.v1");
assert.ok(Array.isArray(manifest.surfaces) && manifest.surfaces.length > 0);
await access(assertRepositoryPath("formal/application-surfaces.schema.json"));

const ids = new Set();
const entrypoints = new Set();
const scopePaths = [];
for (const surface of manifest.surfaces) {
  assert.match(surface.id, /^[a-z][a-z0-9-]{0,63}$/);
  assert.equal(ids.has(surface.id), false, `duplicate surface id: ${surface.id}`);
  ids.add(surface.id);
  assert.ok(knownKinds.has(surface.kind), `unknown surface kind: ${surface.kind}`);
  assert.ok(knownMachines.has(surface.machine), `unknown machine: ${surface.machine}`);
  assert.equal(entrypoints.has(surface.entrypoint), false, `duplicate entrypoint: ${surface.entrypoint}`);
  entrypoints.add(surface.entrypoint);
  scopePaths.push(surface.scopePath);
  await access(assertRepositoryPath(surface.scopePath));

  assert.ok(Array.isArray(surface.runtimePaths) && surface.runtimePaths.length >= 2);
  assert.ok(Array.isArray(surface.proofPaths) && surface.proofPaths.length >= 2);
  const paths = [surface.entrypoint, ...surface.runtimePaths, ...surface.proofPaths];
  assert.equal(new Set(surface.runtimePaths).size, surface.runtimePaths.length);
  assert.equal(new Set(surface.proofPaths).size, surface.proofPaths.length);
  assert.ok(surface.runtimePaths.includes(surface.entrypoint));
  assert.ok(surface.runtimePaths.includes("clients/browser/lifecycle.mjs"));
  assert.ok(surface.proofPaths.some((path) => path.endsWith(".mjs")));
  assert.ok(surface.proofPaths.some((path) => path.endsWith(".smt2")));
  for (const path of paths) await access(assertRepositoryPath(path));

  const source = await readFile(assertRepositoryPath(surface.entrypoint), "utf8");
  assert.match(
    source,
    /lifecycle\.mjs/,
    `${surface.entrypoint} does not execute the declared lifecycle machine`,
  );
}

assert.equal(
  manifest.desktopBoundary.standaloneAppPresent,
  manifest.surfaces.some((surface) => surface.kind === "desktop-app"),
);
await access(assertRepositoryPath(manifest.desktopBoundary.sharedRuntime));
await access(assertRepositoryPath(manifest.desktopBoundary.scopeGate));
assert.ok(
  Array.isArray(manifest.nonApplicationBoundaries) &&
    manifest.nonApplicationBoundaries.length > 0,
);
for (const boundary of manifest.nonApplicationBoundaries) {
  assertRepositoryPath(boundary.scopePath);
  assert.equal(typeof boundary.reason, "string");
  assert.ok(boundary.reason.length > 0);
  if (boundary.except !== undefined) {
    assert.ok(Array.isArray(boundary.except));
    assert.equal(new Set(boundary.except).size, boundary.except.length);
    for (const path of boundary.except) assertRepositoryPath(path);
  }
}

const listed = spawnSync("git", ["ls-files", "-z"], {
  cwd: root,
  encoding: "utf8",
});
if (listed.status !== 0) {
  throw new Error(`git ls-files failed: ${listed.stderr || listed.stdout}`);
}
const tracked = listed.stdout.split("\0").filter(Boolean);

function isCovered(path) {
  return scopePaths.some((scopePath) =>
    scopePath.endsWith("/") ? path.startsWith(scopePath) : path === scopePath,
  );
}

const discovered = new Set();
for (const path of tracked) {
  if (
    path.startsWith("apps/") ||
    path.includes("/src-tauri/") ||
    /(^|\/)(tauri\.conf\.(?:json|json5)|electron-builder\.(?:json|ya?ml)|[^/]+\.desktop)$/.test(path) ||
    /^clients\/browser\/demo\//.test(path)
  ) {
    discovered.add(path);
  }

  const isPotentialManifest =
    path.endsWith("package.json") ||
    path.endsWith("Cargo.toml") ||
    path.endsWith("pubspec.yaml") ||
    path.endsWith(".csproj") ||
    path.endsWith(".swift") ||
    path.endsWith(".dart") ||
    path.endsWith(".rs") ||
    /\.(?:[cm]?[jt]sx?)$/.test(path);
  if (!isPotentialManifest) continue;

  const source = await readFile(resolve(root, path), "utf8");
  if (
    /["'](?:electron|@tauri-apps\/api|@neutralinojs\/lib)["']/.test(source) ||
    /^\s*(?:tauri|eframe|iced|slint|dioxus-desktop)\s*=/m.test(source) ||
    /\bsdk:\s*flutter\b|^\s*flutter:\s*$/m.test(source) ||
    /<(?:UseWPF|UseWindowsForms)>|Avalonia|Microsoft\.UI\.Xaml/.test(source) ||
    /\bimport\s+SwiftUI\b|\brunApp\s*\(|tauri::Builder|eframe::run_native|iced::application/.test(source)
  ) {
    discovered.add(path);
  }
}

const uncovered = [...discovered].filter((path) => !isCovered(path)).sort();
assert.deepEqual(
  uncovered,
  [],
  `application or desktop paths are missing formal surface declarations: ${uncovered.join(", ")}`,
);

process.stdout.write(
  `application scope audit passed: ${manifest.surfaces.length} declared surfaces, ${discovered.size} discovered app paths\n`,
);
