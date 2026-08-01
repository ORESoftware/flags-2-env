import http from "node:http";
import { readFile } from "node:fs/promises";
import { extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const siteRoot = resolve(root, "tests/browser/site");
const clientRoot = resolve(root, "clients/browser");
const host = "127.0.0.1";
const port = Number(process.env.PORT || 4173);

const mimeTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
]);

function safeResolve(base, requested) {
  const relative = requested.replace(/^\/+/, "");
  const candidate = resolve(base, relative);
  if (candidate !== base && !candidate.startsWith(`${base}${sep}`)) {
    return null;
  }
  return candidate;
}

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", `http://${host}:${port}`);
    let target;
    if (url.pathname === "/") {
      target = resolve(siteRoot, "index.html");
    } else if (url.pathname.startsWith("/site/")) {
      target = safeResolve(siteRoot, url.pathname.slice("/site/".length));
    } else if (url.pathname.startsWith("/client/")) {
      target = safeResolve(clientRoot, url.pathname.slice("/client/".length));
    }

    if (!target) {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("not found\n");
      return;
    }

    const body = await readFile(target);
    response.writeHead(200, {
      "cache-control": "no-store",
      "content-security-policy": "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'none'",
      "cross-origin-opener-policy": "same-origin",
      "cross-origin-resource-policy": "same-origin",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "content-type": mimeTypes.get(extname(target)) || "application/octet-stream",
    });
    response.end(body);
  } catch (error) {
    if (error?.code === "ENOENT") {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("not found\n");
      return;
    }
    console.error(error);
    response.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    response.end("internal error\n");
  }
});

server.listen(port, host, () => {
  console.log(`flags2env browser test server listening on http://${host}:${port}`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
