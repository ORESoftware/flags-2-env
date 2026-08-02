#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import threading
from contextlib import contextmanager
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import Browser, Page, sync_playwright

ROOT = Path(__file__).resolve().parents[2]
RESULTS = ROOT / "build" / "browser-results"


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        return


@contextmanager
def server():
    handler = lambda *args, **kwargs: QuietHandler(*args, directory=ROOT, **kwargs)
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{httpd.server_port}"
    finally:
        httpd.shutdown()
        thread.join(timeout=5)
        httpd.server_close()


def output_json(page: Page) -> dict[str, object]:
    return json.loads(page.locator("#output").inner_text())


def run_suite(browser: Browser, base_url: str) -> None:
    context = browser.new_context(viewport={"width": 1280, "height": 900})
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

        page.get_by_role("button", name="Parse", exact=True).click()
        parsed = output_json(page)
        assert parsed["PORT"] == "8080"
        assert parsed["DEBUG"] == "true"
        assert parsed["TOOL_COMMAND"] == "serve"

        page.get_by_role("button", name="Structured parse", exact=True).click()
        structured = output_json(page)
        assert structured["command"] == "serve"
        assert structured["providedFlags"]["PORT"] == "8080"
        assert structured["unknownOptions"] == []
        assert structured["errors"] == []

        page.locator("#argv-json").fill(
            '["tool","serve","worker","--name","alpha","--verbose"]'
        )
        page.get_by_role("button", name="Structured parse", exact=True).click()
        nested = output_json(page)
        assert nested["command"] == "serve worker"
        assert nested["providedFlags"]["WORKER_NAME"] == "alpha"
        assert nested["providedFlags"]["TOOL_VERBOSE"] == "true"

        resolved = page.evaluate(
            "() => window.__flags2env.resolveCommands([\"tool\",\"serve\",\"worker\"])"
        )
        assert resolved == {"path": ["serve", "worker"], "label": "serve worker"}

        page.locator("#argv-json").fill(
            '["tool","serve","--port","not-a-number"]'
        )
        page.get_by_role("button", name="Structured parse", exact=True).click()
        invalid = output_json(page)
        assert invalid["errors"], invalid
        assert "PORT" not in invalid["providedFlags"]

        page.locator("#argv-json").fill('["tool","serve","--help"]')
        page.get_by_role("button", name="Help", exact=True).click()
        help_text = page.locator("#output").inner_text()
        assert "--port" in help_text
        assert "--debug" in help_text
        assert "worker" in help_text

        page.get_by_role("button", name="Audit config", exact=True).click()
        audit = output_json(page)
        assert isinstance(audit, dict)
        assert not audit.get("errors"), audit

        page.get_by_role("button", name="Coerce", exact=True).click()
        coercion = output_json(page)
        assert coercion["ok"] is True
        assert coercion["value"]["PORT"] == 8080
        assert coercion["value"]["DEBUG"] is True
        assert coercion["value"]["TOOL_VERBOSE"] is False

        nul_error = page.evaluate(
            """() => {
              try {
                window.__flags2env.parse(["tool", "bad" + String.fromCharCode(0)]);
                return "";
              } catch (error) {
                return error.message;
              }
            }"""
        )
        assert "NUL bytes" in nul_error

        count_error = page.evaluate(
            """() => {
              try {
                window.__flags2env.parse(Array.from({length: 4097}, () => "x"));
                return "";
              } catch (error) {
                return error.message;
              }
            }"""
        )
        assert "4096-item" in count_error

        config_error = page.evaluate(
            """() => {
              try {
                window.__flags2env.setConfig("x".repeat(1024 * 1024 + 1));
                return "";
              } catch (error) {
                return error.message;
              }
            }"""
        )
        assert "1048576-byte" in config_error

        columns_error = page.evaluate(
            """() => {
              try {
                window.__flags2env.helpTableForArgv("tool", ["tool"], 1001);
                return "";
              } catch (error) {
                return error.message;
              }
            }"""
        )
        assert "between 1 and 1000" in columns_error

        page.set_viewport_size({"width": 390, "height": 844})
        assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth")
        page.locator("#argv-json").focus()
        assert page.evaluate("document.activeElement.id") == "argv-json"

        assert not external_requests, external_requests
        assert not errors, errors
        context.tracing.stop()
    except BaseException:
        RESULTS.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=RESULTS / "failure.png", full_page=True)
        context.tracing.stop(path=RESULTS / "trace.zip")
        raise
    finally:
        context.close()


def main() -> None:
    os.chdir(ROOT)
    with server() as base_url, sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        try:
            run_suite(browser, base_url)
        finally:
            browser.close()
    print("flags2env browser Playwright contract passed")


if __name__ == "__main__":
    main()
