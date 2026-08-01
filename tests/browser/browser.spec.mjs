import { expect, test } from "@playwright/test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  auditConfig as nativeAuditConfig,
  coerce as nativeCoerce,
  parseStructured as nativeParseStructured,
  resolveCommands as nativeResolveCommands,
} from "../../clients/nodejs/lib.mjs";
import { createFlags2EnvBrowser } from "../../clients/browser/index.mjs";

const contract = `[parse]
command_env = "APP_COMMAND"
unknown_options_env = "APP_UNKNOWN"
errors_env = "APP_ERRORS"
allow_unknown = false

[flags.verbose]
env = "APP_VERBOSE"
aliases = ["verbose"]
type = "bool"
default = "false"
help = "Enable verbose output."

[commands.develop]
aliases = ["dev"]
help = "Open <safe> development tools."

[commands.develop.flags.profile]
env = "APP_PROFILE"
aliases = ["profile"]
type = "string"
default = "default"
help = "Development profile."

[commands.develop.flags.workers]
env = "APP_WORKERS"
aliases = ["workers"]
type = "int"
default = "2"
help = "Worker count."
`;

const argv = ["zed", "dev", "--profile", "ai", "--workers", "4", "workspace"];
let tempDirectory;
let configPath;

test.beforeAll(async () => {
  tempDirectory = await mkdtemp(join(tmpdir(), "flags2env-browser-"));
  configPath = join(tempDirectory, ".cli-flags.toml");
  await writeFile(configPath, contract, "utf8");
});

test.afterAll(async () => {
  await rm(tempDirectory, { recursive: true, force: true });
});

async function loadDemo(page) {
  const errors = [];
  const externalRequests = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", (request) => {
    const url = new URL(request.url());
    if (url.origin !== "http://127.0.0.1:4173") externalRequests.push(request.url());
  });
  await page.goto("/");
  await page.locator("#contract").fill(contract);
  await page.locator("#argv").fill(JSON.stringify(argv));
  return { errors, externalRequests };
}

async function runOperation(page, name) {
  await page.getByRole("button", { name }).click();
  await expect(page.locator("#status")).toHaveText("Complete");
  return page.locator("#result").textContent();
}

test("structured parsing and canonical aliases match the native client", async ({ page }) => {
  const telemetry = await loadDemo(page);
  const raw = await runOperation(page, "Structured parse");
  const browserResult = JSON.parse(raw);
  const nativeResult = nativeParseStructured(argv, { configPath });

  expect(browserResult).toEqual(nativeResult);
  expect(browserResult.subcommands).toEqual(["develop"]);
  expect(browserResult.command).toBe("develop");
  expect(browserResult.flags.APP_PROFILE).toBe("ai");
  expect(browserResult.flags.APP_WORKERS).toBe("4");
  expect(browserResult.extras).toEqual(["workspace"]);
  expect(nativeResolveCommands(argv, { configPath })).toEqual({ path: ["develop"], label: "develop" });
  expect(telemetry.errors).toEqual([]);
  expect(telemetry.externalRequests).toEqual([]);
});

test("audit and coercion execute the same C core in WebAssembly", async ({ page }) => {
  const telemetry = await loadDemo(page);
  const auditRaw = await runOperation(page, "Audit");
  expect(JSON.parse(auditRaw)).toEqual(nativeAuditConfig({ configPath }));

  const values = { APP_VERBOSE: "yes", APP_WORKERS: "4" };
  await page.locator("#values").fill(JSON.stringify(values));
  const coercionRaw = await runOperation(page, "Coerce");
  expect(JSON.parse(coercionRaw)).toEqual(nativeCoerce(values, { configPath }));
  expect(telemetry.errors).toEqual([]);
  expect(telemetry.externalRequests).toEqual([]);
});

test("help is rendered as inert text under a restrictive CSP", async ({ page }) => {
  const telemetry = await loadDemo(page);
  const help = await runOperation(page, "Help");
  expect(help).toContain("develop");
  expect(help).toContain("Open <safe> development tools.");
  expect(await page.locator("#result img").count()).toBe(0);
  expect(await page.locator("#result script").count()).toBe(0);
  expect(telemetry.errors).toEqual([]);
  expect(telemetry.externalRequests).toEqual([]);
});

test("invalid contracts and hostile input fail visibly without crashing the page", async ({ page }) => {
  const telemetry = await loadDemo(page);
  await page.locator("#contract").fill('[flags.bad]\nenv = "BROKEN"\ntype = "wat"');
  await page.getByRole("button", { name: "Audit" }).click();
  const output = await page.locator("#result").textContent();
  expect(output.length).toBeGreaterThan(0);

  await page.locator("#argv").fill("not-json");
  await page.getByRole("button", { name: "Structured parse" }).click();
  await expect(page.locator("#status")).toHaveText("Failed");
  await expect(page.locator("#result")).toContainText("argv is not valid JSON");
  expect(telemetry.errors).toEqual([]);
  expect(telemetry.externalRequests).toEqual([]);
});

test("the demo remains keyboard-usable and contained on a narrow viewport", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 740 });
  await loadDemo(page);
  await page.keyboard.press("Tab");
  const width = await page.evaluate(() => ({
    scroll: document.documentElement.scrollWidth,
    client: document.documentElement.clientWidth,
  }));
  expect(width.scroll).toBeLessThanOrEqual(width.client);
  await expect(page.getByRole("heading", { name: "flags-2-env in the browser" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Structured parse" })).toBeVisible();
});

test("owned C strings are copied and freed on every wrapper call", async () => {
  let freeCount = 0;
  const outputs = new Map([[101, '{"ok":true}']]);
  const fakeFs = {
    mkdir() {},
    writeFile() {},
  };
  const client = await createFlags2EnvBrowser("[parse]\nallow_unknown = true\n", {
    moduleFactory: async () => ({
      FS: fakeFs,
      ccall() {
        return 101;
      },
      UTF8ToString(pointer) {
        return outputs.get(pointer);
      },
      _f2e_free(pointer) {
        expect(pointer).toBe(101);
        freeCount += 1;
      },
    }),
  });

  expect(client.auditConfig()).toEqual({ ok: true });
  expect(freeCount).toBe(1);
});
