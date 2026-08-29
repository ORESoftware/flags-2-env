#!/usr/bin/env python3
from __future__ import annotations

import os

from playwright.sync_api import sync_playwright

from test_browser import RESULTS, ROOT, server


def main() -> None:
    os.chdir(ROOT)
    engine = os.environ.get("PLAYWRIGHT_BROWSER", "chromium")
    if engine not in {"chromium", "firefox", "webkit"}:
        raise SystemExit(f"unsupported PLAYWRIGHT_BROWSER: {engine}")

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

                  const bounded = await createFlags2EnvWorker({
                    configText,
                    maxPendingRequests: 2,
                    timeoutMs: 10000,
                  });
                  const first = bounded.parse(["tool", "serve", "--port", "8101"]);
                  const second = bounded.parse(["tool", "serve", "--port", "8102"]);
                  const pendingAtLimit = bounded.pendingRequests;
                  let busy;
                  try {
                    await bounded.parse(["tool", "serve", "--port", "8103"]);
                    busy = {name: "", message: "unexpected success"};
                  } catch (error) {
                    busy = {name: error.name, message: error.message};
                  }
                  const draining = bounded.drain();
                  const accepted = await Promise.all([first, second]);
                  await draining;
                  const pendingAfterDrain = bounded.pendingRequests;
                  await bounded.close();

                  const graceful = await createFlags2EnvWorker({configText});
                  const acceptedDuringClose = graceful.parse([
                    "tool", "serve", "--port", "8201"
                  ]);
                  const closingPromise = graceful.close({timeoutMs: 5000});
                  const closingState = graceful.closing;
                  const closingPhase = graceful.state;
                  let rejectedWhileClosing;
                  try {
                    await graceful.parse(["tool"]);
                    rejectedWhileClosing = "unexpected success";
                  } catch (error) {
                    rejectedWhileClosing = error.message;
                  }
                  const acceptedCloseValue = await acceptedDuringClose;
                  await closingPromise;

                  const stalled = await createFlags2EnvWorker({
                    configText,
                    timeoutMs: 5000,
                    workerUrl: `${baseUrl}/tests/browser/stall-after-init-worker.mjs`,
                  });
                  const stalledRequest = stalled.parse(["tool"]);
                  let closeTimeout;
                  try {
                    await stalled.close({timeoutMs: 100});
                    closeTimeout = {name: "", message: "unexpected success"};
                  } catch (error) {
                    closeTimeout = {name: error.name, message: error.message};
                  }
                  let stalledRequestError;
                  try {
                    await stalledRequest;
                    stalledRequestError = {name: "", message: "unexpected success"};
                  } catch (error) {
                    stalledRequestError = {name: error.name, message: error.message};
                  }

                  const controller = new AbortController();
                  const aborted = await createFlags2EnvWorker({
                    configText,
                    signal: controller.signal,
                    workerUrl: `${baseUrl}/tests/browser/stall-after-init-worker.mjs`,
                  });
                  const abortedRequest = aborted.parse(["tool"]);
                  controller.abort();
                  let abortResult;
                  try {
                    await abortedRequest;
                    abortResult = {name: "", message: "unexpected success"};
                  } catch (error) {
                    abortResult = {name: error.name, message: error.message};
                  }

                  const alreadyAbortedController = new AbortController();
                  alreadyAbortedController.abort();
                  let alreadyAborted;
                  try {
                    await createFlags2EnvWorker({
                      configText,
                      signal: alreadyAbortedController.signal,
                    });
                    alreadyAborted = {name: "", message: "unexpected success"};
                  } catch (error) {
                    alreadyAborted = {name: error.name, message: error.message};
                  }

                  return {
                    pendingAtLimit,
                    pendingAfterDrain,
                    busy,
                    acceptedPorts: accepted.map((value) => value.PORT),
                    boundedClosed: bounded.closed,
                    boundedPhase: bounded.state,
                    closingState,
                    closingPhase,
                    acceptedClosePort: acceptedCloseValue.PORT,
                    rejectedWhileClosing,
                    gracefulClosed: graceful.closed,
                    gracefulPhase: graceful.state,
                    closeTimeout,
                    stalledRequestError,
                    stalledClosed: stalled.closed,
                    stalledPhase: stalled.state,
                    stalledFailed: stalled.failed,
                    abortResult,
                    abortedClosed: aborted.closed,
                    abortedPhase: aborted.state,
                    abortedFailed: aborted.failed,
                    alreadyAborted,
                  };
                }""",
                {"baseUrl": base_url},
            )

            assert result["pendingAtLimit"] == 2
            assert result["pendingAfterDrain"] == 0
            assert result["busy"]["name"] == "BusyError"
            assert "2 pending requests" in result["busy"]["message"]
            assert result["acceptedPorts"] == ["8101", "8102"]
            assert result["boundedClosed"] is True
            assert result["boundedPhase"] == "closed"
            assert result["closingState"] is True
            assert result["closingPhase"] == "draining"
            assert result["acceptedClosePort"] == "8201"
            assert "closing" in result["rejectedWhileClosing"]
            assert result["gracefulClosed"] is True
            assert result["gracefulPhase"] == "closed"
            assert result["closeTimeout"]["name"] == "TimeoutError"
            assert "close timed out" in result["closeTimeout"]["message"]
            assert result["stalledRequestError"]["name"] == "TimeoutError"
            assert result["stalledClosed"] is True
            assert result["stalledPhase"] == "failed"
            assert result["stalledFailed"] is True
            assert result["abortResult"]["name"] == "AbortError"
            assert result["abortedClosed"] is True
            assert result["abortedPhase"] == "closed"
            assert result["abortedFailed"] is False
            assert result["alreadyAborted"]["name"] == "AbortError"
            assert not external_requests, external_requests
            assert not errors, errors
            context.tracing.stop()
        except BaseException:
            RESULTS.mkdir(parents=True, exist_ok=True)
            page.screenshot(
                path=RESULTS / f"{engine}-worker-lifecycle-failure.png",
                full_page=True,
            )
            context.tracing.stop(
                path=RESULTS / f"{engine}-worker-lifecycle-trace.zip"
            )
            raise
        finally:
            context.close()
            browser.close()

    print(f"flags2env {engine} worker lifecycle contract passed")


if __name__ == "__main__":
    main()
