#!/usr/bin/env python3
from __future__ import annotations

import os

from playwright.sync_api import Browser, sync_playwright

from test_browser import RESULTS, ROOT, run_suite, server


def run_worker_suite(browser: Browser, base_url: str, engine: str) -> None:
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
        page.goto(f"{base_url}/clients/browser/demo/", wait_until="networkidle")
        page.locator("#status[data-ready='true']").wait_for()
        result = page.evaluate(
            """async ({baseUrl}) => {
              const {createFlags2EnvWorker} = await import(
                `${baseUrl}/clients/browser/dist/worker-client.mjs`
              );
              const configText = await fetch(
                `${baseUrl}/clients/browser/demo/config.toml`
              ).then((response) => response.text());

              const client = await createFlags2EnvWorker({configText, timeoutMs: 10000});
              const parsed = await client.parse(["tool", "serve", "--port", "9090", "--debug"]);
              const structured = await client.parseStructured([
                "tool", "serve", "worker", "--name", "beta", "--verbose"
              ]);
              const resolved = await client.resolveCommands(["tool", "serve", "worker"]);
              const audit = await client.auditConfig();
              const coercion = await client.coerce({PORT: "9090", DEBUG: "true"});
              const help = await client.helpTableForArgv(
                "tool", ["tool", "serve", "worker", "--help"], 88
              );
              const burst = await Promise.all(
                Array.from({length: 64}, (_, index) =>
                  client.parse(["tool", "serve", "--port", String(7000 + index)])
                )
              );

              const configA = `
[flags.mode]
env = "MODE"
aliases = ["mode"]
type = "string"
default = "alpha"
`;
              const configB = configA.replace("alpha", "bravo");
              const first = await createFlags2EnvWorker({configText: configA});
              const second = await createFlags2EnvWorker({configText: configB});
              const [isolatedA, isolatedB] = await Promise.all([
                first.parse(["tool"]),
                second.parse(["tool"]),
              ]);
              await first.setConfig(configA.replace("alpha", "charlie"));
              const changedA = await first.parse(["tool"]);
              const unchangedB = await second.parse(["tool"]);

              const direct = new Worker(
                `${baseUrl}/clients/browser/dist/worker.mjs`, {type: "module"}
              );
              const directReply = await new Promise((resolve, reject) => {
                const timer = setTimeout(() => reject(new Error("direct worker timeout")), 5000);
                direct.addEventListener("message", (event) => {
                  if (event.data?.id !== 41) return;
                  clearTimeout(timer);
                  resolve(event.data);
                });
                direct.addEventListener("error", reject, {once: true});
                direct.postMessage({id: 41, method: "unsupported", args: []});
              });
              direct.terminate();

              const hangingUrl = `${baseUrl}/tests/browser/hanging-worker.mjs`;
              let timeout;
              try {
                await createFlags2EnvWorker({configText, timeoutMs: 100, workerUrl: hangingUrl});
                timeout = {name: "", message: "unexpected success"};
              } catch (error) {
                timeout = {name: error.name, message: error.message};
              }

              client.terminate();
              let closed;
              try {
                await client.parse(["tool"]);
                closed = "unexpected success";
              } catch (error) {
                closed = error.message;
              }
              first.terminate();
              second.terminate();

              return {
                parsed,
                structured,
                resolved,
                audit,
                coercion,
                help,
                burstFirst: burst[0].PORT,
                burstLast: burst.at(-1).PORT,
                isolatedA: isolatedA.MODE,
                isolatedB: isolatedB.MODE,
                changedA: changedA.MODE,
                unchangedB: unchangedB.MODE,
                directReply,
                timeout,
                closed,
              };
            }""",
            {"baseUrl": base_url},
        )

        assert result["parsed"]["PORT"] == "9090"
        assert result["parsed"]["DEBUG"] == "true"
        assert result["structured"]["command"] == "serve worker"
        assert result["structured"]["providedFlags"]["WORKER_NAME"] == "beta"
        assert result["resolved"] == {
            "path": ["serve", "worker"],
            "label": "serve worker",
        }
        assert not result["audit"].get("errors"), result["audit"]
        assert result["coercion"]["ok"] is True
        assert result["coercion"]["value"]["PORT"] == 9090
        assert "--name" in result["help"]
        assert result["burstFirst"] == "7000"
        assert result["burstLast"] == "7063"
        assert result["isolatedA"] == "alpha"
        assert result["isolatedB"] == "bravo"
        assert result["changedA"] == "charlie"
        assert result["unchangedB"] == "bravo"
        assert result["directReply"]["ok"] is False
        assert "not initialized" in result["directReply"]["error"]["message"]
        assert "path" not in result["directReply"]["error"]
        assert result["timeout"]["name"] == "TimeoutError"
        assert "timed out" in result["timeout"]["message"]
        assert "closed" in result["closed"]
        assert not external_requests, external_requests
        assert not errors, errors
        context.tracing.stop()
    except BaseException:
        RESULTS.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=RESULTS / f"{engine}-worker-failure.png", full_page=True)
        context.tracing.stop(path=RESULTS / f"{engine}-worker-trace.zip")
        raise
    finally:
        context.close()


def main() -> None:
    os.chdir(ROOT)
    engine = os.environ.get("PLAYWRIGHT_BROWSER", "chromium")
    if engine not in {"chromium", "firefox", "webkit"}:
        raise SystemExit(f"unsupported PLAYWRIGHT_BROWSER: {engine}")
    with server() as base_url, sync_playwright() as playwright:
        browser_type = getattr(playwright, engine)
        browser = browser_type.launch()
        try:
            run_suite(browser, base_url)
            run_worker_suite(browser, base_url, engine)
        finally:
            browser.close()
    print(f"flags2env {engine} main-thread and worker contracts passed")


if __name__ == "__main__":
    main()
