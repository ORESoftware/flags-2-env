import { createFlags2Env } from "./lib.mjs";
import {
  WorkerHostEvent,
  WorkerHostPhase,
  initialWorkerHostState,
  reduceWorkerHostLifecycle,
} from "./lifecycle.mjs";

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
let lifecycle = initialWorkerHostState();

function transition(event) {
  const outcome = reduceWorkerHostLifecycle(lifecycle, event);
  lifecycle = outcome.state;
  return outcome;
}

function assertHostInvariant() {
  const ready = lifecycle.phase === WorkerHostPhase.READY;
  if (ready !== (client !== null)) {
    client = null;
    lifecycle = reduceWorkerHostLifecycle(lifecycle, WorkerHostEvent.FAULT).state;
    throw new Error("flags2env worker lifecycle failed closed");
  }
}

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
      if (request.args.length !== 1 || typeof request.args[0] !== "string") {
        throw new TypeError("worker initialization requires config text");
      }
      const started = transition(WorkerHostEvent.INITIALIZE_REQUESTED);
      if (!started.accepted) {
        throw new Error("flags2env worker is already initialized or failed");
      }
      try {
        client = await createFlags2Env({ configText: request.args[0] });
        const initialized = transition(WorkerHostEvent.INITIALIZED);
        if (!initialized.accepted) {
          throw new Error("flags2env worker initialization lifecycle failed closed");
        }
        assertHostInvariant();
      } catch (error) {
        client = null;
        if (lifecycle.phase === WorkerHostPhase.INITIALIZING) {
          transition(WorkerHostEvent.INITIALIZATION_FAILED);
        } else if (lifecycle.phase !== WorkerHostPhase.FAILED) {
          transition(WorkerHostEvent.FAULT);
        }
        throw error;
      }
      response(id, true);
      return;
    }

    const requested = transition(WorkerHostEvent.CALL_REQUESTED);
    if (!requested.accepted) {
      throw new Error("flags2env worker is not initialized");
    }
    assertHostInvariant();
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
