const MAX_RPC_BYTES = 4 * 1024 * 1024;
const MAX_TIMEOUT_MS = 120_000;
const encoder = new TextEncoder();

function assertTimeout(value) {
  if (!Number.isInteger(value) || value < 1 || value > MAX_TIMEOUT_MS) {
    throw new RangeError(`timeoutMs must be an integer between 1 and ${MAX_TIMEOUT_MS}`);
  }
  return value;
}

function assertSerializable(value) {
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

function remoteError(payload) {
  const error = new Error(payload?.message || "flags2env worker request failed");
  const names = new Set(["Error", "TypeError", "RangeError", "SyntaxError", "TimeoutError"]);
  error.name = names.has(payload?.name) ? payload.name : "Error";
  return error;
}

export async function createFlags2EnvWorker(options = {}) {
  const {
    configText = "",
    timeoutMs = 15_000,
    workerUrl = new URL("./worker.mjs", import.meta.url),
    workerFactory = (url, init) => new Worker(url, init),
  } = options;
  if (typeof configText !== "string") throw new TypeError("configText must be a string");
  assertTimeout(timeoutMs);
  if (typeof workerFactory !== "function") throw new TypeError("workerFactory must be a function");

  const worker = workerFactory(workerUrl, { type: "module", name: "flags2env" });
  if (!worker || typeof worker.postMessage !== "function" || typeof worker.terminate !== "function") {
    throw new TypeError("workerFactory must return a Worker-compatible object");
  }

  let nextId = 1;
  let closed = false;
  const pending = new Map();

  const rejectAll = (error) => {
    for (const entry of pending.values()) {
      clearTimeout(entry.timer);
      entry.reject(error);
    }
    pending.clear();
  };

  const terminate = (reason = "flags2env worker was terminated") => {
    if (closed) return;
    closed = true;
    worker.terminate();
    rejectAll(new Error(reason));
  };

  worker.addEventListener("message", (event) => {
    const message = event.data;
    const entry = pending.get(message?.id);
    if (!entry) return;
    pending.delete(message.id);
    clearTimeout(entry.timer);
    if (message.ok === true) entry.resolve(message.value);
    else entry.reject(remoteError(message.error));
  });
  worker.addEventListener("error", () => terminate("flags2env worker failed"));
  worker.addEventListener("messageerror", () => terminate("flags2env worker returned an invalid message"));

  const request = (method, args = [], requestTimeoutMs = timeoutMs) => {
    if (closed) return Promise.reject(new Error("flags2env worker is closed"));
    if (typeof method !== "string" || !Array.isArray(args)) {
      return Promise.reject(new TypeError("worker request requires a method and args array"));
    }
    assertTimeout(requestTimeoutMs);
    const id = nextId++;
    const envelope = { id, method, args };
    assertSerializable(envelope);

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        const error = new Error(`flags2env worker request timed out after ${requestTimeoutMs}ms`);
        error.name = "TimeoutError";
        reject(error);
      }, requestTimeoutMs);
      pending.set(id, { resolve, reject, timer });
      try {
        worker.postMessage(envelope);
      } catch (error) {
        clearTimeout(timer);
        pending.delete(id);
        reject(error);
      }
    });
  };

  try {
    await request("__init", [configText]);
  } catch (error) {
    terminate("flags2env worker initialization failed");
    throw error;
  }

  return Object.freeze({
    setConfig: (value) => request("setConfig", [value]),
    parse: (argv) => request("parse", [argv]),
    parseStructured: (argv) => request("parseStructured", [argv]),
    resolveCommands: (argv) => request("resolveCommands", [argv]),
    auditConfig: () => request("auditConfig"),
    coerce: (values) => request("coerce", [values]),
    helpTableForArgv: (command, argv, terminalColumns) =>
      request(
        "helpTableForArgv",
        terminalColumns === undefined ? [command, argv] : [command, argv, terminalColumns],
      ),
    terminate,
    get closed() {
      return closed;
    },
  });
}

export default createFlags2EnvWorker;
