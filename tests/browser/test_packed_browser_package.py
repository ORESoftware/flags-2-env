#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path

from playwright.sync_api import sync_playwright

from test_browser import RESULTS, ROOT, server

PACKAGE_ROOT = ROOT / "build" / "browser-package-consumer" / "package"


def main() -> None:
    engine = os.environ.get("PLAYWRIGHT_BROWSER", "chromium")
    if engine not in {"chromium", "firefox", "webkit"}:
        raise SystemExit(f"unsupported PLAYWRIGHT_BROWSER: {engine}")
    required = {
        "package.json",
        "flags2env.mjs",
        "flags2env.wasm",
        "lib.mjs",
        "lib.d.ts",
        "worker-client.mjs",
        "worker-client.d.ts",
        "worker.mjs",
        "README.md",
        "LICENSE",
    }
    if not PACKAGE_ROOT.is_dir():
        raise SystemExit(f"packed package is not extracted: {PACKAGE_ROOT}")
    actual = {path.name for path in PACKAGE_ROOT.iterdir()}
    if actual != required:
        raise SystemExit(f"packed package file mismatch: {sorted(actual)}")

    os.chdir(ROOT)
    with server() as base_url, sync_playwright() as playwright:
        browser = getattr(playwright, engine).launch()
        context = browser.new_context(viewport={"width": 1024, "height": 768})
        context.tracing.start(screenshots=True, snapshots=True, sources=True)
        page = context.new_page()
        errors: list[str] = []
        external_requests: list[str] = []
        page.on(
            "console",
            lambda message: errors.append(f"console: {message.text}")
            if message.type == "error"
            else None,
        )
        page.on("pageerror", lambda error: errors.append(f"pageerror: {error}"))
        page.on(
            "request",
            lambda request: external_requests.append(request.url)
            if not request.url.startswith(base_url)
            else None,
        )

        try:
            page.goto(f"{base_url}/tests/browser/package-host.html", wait_until="load")
            result = page.evaluate(
                """async ({baseUrl}) => {
                  const packageBase = `${baseUrl}/build/browser-package-consumer/package`;
                  const metadata = await fetch(`${packageBase}/package.json`).then((response) => response.json());
                  const configText = await fetch(
                    `${baseUrl}/clients/browser/demo/config.toml`
                  ).then((response) => response.text());

                  const mainModule = await import(`${packageBase}/lib.mjs`);
                  const main = await mainModule.createFlags2Env({configText});
                  const parsed = main.parse([
                    "tool", "serve", "worker", "--name", "packed", "--verbose"
                  ]);
                  const resolved = main.resolveCommands(["tool", "serve", "worker"]);

                  const workerModule = await import(`${packageBase}/worker-client.mjs`);
                  const worker = await workerModule.createFlags2EnvWorker({
                    configText,
                    maxPendingRequests: 4,
                  });
                  const workerParsed = await worker.parse([
                    "tool", "serve", "--port", "9123", "--debug"
                  ]);
                  await worker.close();

                  return {
                    metadata,
                    parsed,
                    resolved,
                    workerParsed,
                    workerClosed: worker.closed,
                  };
                }""",
                {"baseUrl": base_url},
            )

            metadata = result["metadata"]
            assert metadata["name"] == "@oresoftware/f2e-browser"
            assert metadata["type"] == "module"
            assert metadata["sideEffects"] is False
            assert "scripts" not in metadata
            assert "dependencies" not in metadata
            assert metadata["exports"]["."]["import"] == "./lib.mjs"
            assert metadata["exports"]["./worker"]["import"] == "./worker-client.mjs"
            assert result["parsed"]["WORKER_NAME"] == "packed"
            assert result["parsed"]["TOOL_VERBOSE"] == "true"
            assert result["resolved"] == {
                "path": ["serve", "worker"],
                "label": "serve worker",
            }
            assert result["workerParsed"]["PORT"] == "9123"
            assert result["workerParsed"]["DEBUG"] == "true"
            assert result["workerClosed"] is True
            assert not external_requests, external_requests
            assert not errors, errors
            context.tracing.stop()
        except BaseException:
            RESULTS.mkdir(parents=True, exist_ok=True)
            page.screenshot(
                path=RESULTS / f"{engine}-packed-package-failure.png",
                full_page=True,
            )
            context.tracing.stop(
                path=RESULTS / f"{engine}-packed-package-trace.zip"
            )
            raise
        finally:
            context.close()
            browser.close()

    print(f"flags2env packed browser package passed in {engine}")


if __name__ == "__main__":
    main()
