import { createFlags2Env } from "./lib.mjs";

const MAX_RPC_BYTES = 4 * 1024 * 1024;
const encoder = new TextEncoder();
const METHODS = new Set([
  "setConfig",
  "parse",
  "parseStructured",
  "resolveCommands",
  "auditConfig",
  "coerce",
  "helpTableForArgv",
]);
const ERROR_NAMES = new Set([
  "Error",
  "TypeError",
  "RangeError",
  "SyntaxError",
  "TimeoutError",
]);

let client = null;
let initializing = false;

function safeSize(value) {
  if (value === undefined) return;
  let json;
  try {
    json = JSON.stringify(value);
  } catch {
    throw new TypeError("worker request must be JSON serializable");
  }
  if (typeof json !== "string" || encoder.encode(json).byteLength > MAX_RPC_BYTES) {
    throw new RangeError(`worker request exceeds the ${MAX_RPC_BYTES}-byte limit`);
  }
}

function publicError(error) {
  const name = ERROR_NAMES.has(error?.name) ? error.name : "Error";
  let message = typeof error?.message === "string" ? error.message : "flags2env worker request failed";
  message = message
    .replace(/(?:[A-Za-z]:)?[\\/](?:[^\s:]+[\\/])*[^\s:]+/g, "[path]")
    .replace(/[\r\n\t]+/g, " ")
    .slice(0, 1024);
  return { name, message: message || "flags2env worker request failed" };
}

function response(id, value) {
  self.postMessage({ id, ok: true, value });
}

function failure(id, error) {
  self.postMessage({ id, ok: false, error: publicError(error) });
}

self.addEventListener("message", async (event) => {
  const request = event.data;
  const id = Number.isSafeInteger(request?.id) && request.id > 0 ? request.id : null;
  if (id === null) return;

  try {
    safeSize(request);
    if (!request || typeof request !== "object" || Array.isArray(request)) {
      throw new TypeError("worker request must be an object");
    }
    if (typeof request.method !== "string" || !Array.isArray(request.args)) {
      throw new TypeError("worker request requires a method and args array");
    }

    if (request.method === "__init") {
      if (client || initializing) {
        throw new Error("flags2env worker is already initialized");
      }
      if (request.args.length !== 1 || typeof request.args[0] !== "string") {
        throw new TypeError("worker initialization requires config text");
      }
      initializing = true;
      try {
        client = await createFlags2Env({ configText: request.args[0] });
      } finally {
        initializing = false;
      }
      response(id, true);
      return;
    }

    if (!client) {
      throw new Error("flags2env worker is not initialized");
    }
    if (!METHODS.has(request.method)) {
      throw new TypeError(`unsupported flags2env worker method: ${request.method}`);
    }

    const value = client[request.method](...request.args);
    safeSize(value);
    response(id, value);
  } catch (error) {
    failure(id, error);
  }
});
