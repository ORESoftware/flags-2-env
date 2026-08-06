const MAX_RPC_BYTES = 4 * 1024 * 1024;
const MAX_TIMEOUT_MS = 120_000;
const MAX_PENDING_REQUESTS = 4096;
const DEFAULT_MAX_PENDING_REQUESTS = 128;
const encoder = new TextEncoder();

function assertIntegerInRange(value, label, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${label} must be an integer between ${minimum} and ${maximum}`);
  }
  return value;
}

function assertTimeout(value, label = "timeoutMs") {
  return assertIntegerInRange(value, label, 1, MAX_TIMEOUT_MS);
}

function assertPendingLimit(value) {
  return assertIntegerInRange(value, "maxPendingRequests", 1, MAX_PENDING_REQUESTS);
}

function assertAbortSignal(value) {
  if (
    value !== undefined &&
    (!value ||
      typeof value.aborted !== "boolean" ||
      typeof value.addEventListener !== "function" ||
      typeof value.removeEventListener !== "function")
  ) {
    throw new TypeError("signal must be an AbortSignal-compatible object");
  }
  return value;
}

function namedError(name, message) {
  const error = new Error(message);
  error.name = name;
  return error;
}

function abortError() {
  return namedError("AbortError", "flags2env worker was aborted");
}

function busyError(limit) {
  return namedError(
    "BusyError",
    `flags2env worker already has ${limit} pending requests`,
  );
}

function timeoutError(message) {
  return namedError("TimeoutError", message);
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
  const names = new Set([
    "Error",
    "TypeError",
    "RangeError",
    "SyntaxError",
    "TimeoutError",
    "AbortError",
    "BusyError",
  ]);
  error.name = names.has(payload?.name) ? payload.name : "Error";
  return error;
}

function normalizeTerminationReason(reason) {
  if (reason instanceof Error) return reason;
  return new Error(
    typeof reason === "string" && reason
      ? reason
      : "flags2env worker was terminated",
  );
}

export async function createFlags2EnvWorker(options = {}) {
  const {
    configText = "",
    timeoutMs = 15_000,
    closeTimeoutMs = timeoutMs,
    maxPendingRequests = DEFAULT_MAX_PENDING_REQUESTS,
    signal,
    workerUrl = new URL("./worker.mjs", import.meta.url),
    workerFactory = (url, init) => new Worker(url, init),
  } = options;
  if (typeof configText !== "string") throw new TypeError("configText must be a string");
  assertTimeout(timeoutMs);
  assertTimeout(closeTimeoutMs, "closeTimeoutMs");
  assertPendingLimit(maxPendingRequests);
  assertAbortSignal(signal);
  if (typeof workerFactory !== "function") throw new TypeError("workerFactory must be a function");
  if (signal?.aborted) throw abortError();

  const worker = workerFactory(workerUrl, { type: "module", name: "flags2env" });
  if (!worker || typeof worker.postMessage !== "function" || typeof worker.terminate !== "function") {
    throw new TypeError("workerFactory must return a Worker-compatible object");
  }

  let nextId = 1;
  let closed = false;
  let closing = false;
  let closePromise = null;
  const pending = new Map();
  const drainWaiters = new Set();

  const notifyDrained = () => {
    if (pending.size !== 0) return;
    for (const resolve of drainWaiters) resolve();
    drainWaiters.clear();
  };

  const removePending = (id) => {
    const entry = pending.get(id);
    if (!entry) return null;
    pending.delete(id);
    clearTimeout(entry.timer);
    notifyDrained();
    return entry;
  };

  const rejectAll = (error) => {
    for (const id of [...pending.keys()]) {
      const entry = removePending(id);
      entry?.reject(error);
    }
    notifyDrained();
  };

  const onAbort = () => terminate(abortError());

  const terminate = (reason = "flags2env worker was terminated") => {
    if (closed) return;
    closing = true;
    closed = true;
    signal?.removeEventListener("abort", onAbort);
    worker.terminate();
    rejectAll(normalizeTerminationReason(reason));
  };

  const allocateId = () => {
    for (let attempts = 0; attempts <= maxPendingRequests; attempts += 1) {
      if (nextId > Number.MAX_SAFE_INTEGER) nextId = 1;
      const id = nextId;
      nextId += 1;
      if (!pending.has(id)) return id;
    }
    throw busyError(maxPendingRequests);
  };

  worker.addEventListener("message", (event) => {
    const message = event.data;
    const entry = removePending(message?.id);
    if (!entry) return;
    if (message.ok === true) entry.resolve(message.value);
    else entry.reject(remoteError(message.error));
  });
  worker.addEventListener("error", () => terminate("flags2env worker failed"));
  worker.addEventListener("messageerror", () => terminate("flags2env worker returned an invalid message"));
  signal?.addEventListener("abort", onAbort, { once: true });

  const request = (method, args = [], requestTimeoutMs = timeoutMs) => {
    if (closed) return Promise.reject(new Error("flags2env worker is closed"));
    if (closing) return Promise.reject(new Error("flags2env worker is closing"));
    if (typeof method !== "string" || !Array.isArray(args)) {
      return Promise.reject(new TypeError("worker request requires a method and args array"));
    }
    assertTimeout(requestTimeoutMs);
    if (pending.size >= maxPendingRequests) {
      return Promise.reject(busyError(maxPendingRequests));
    }
    const id = allocateId();
    const envelope = { id, method, args };
    assertSerializable(envelope);

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const entry = removePending(id);
        entry?.reject(
          timeoutError(`flags2env worker request timed out after ${requestTimeoutMs}ms`),
        );
      }, requestTimeoutMs);
      pending.set(id, { resolve, reject, timer });
      try {
        worker.postMessage(envelope);
      } catch (error) {
        const entry = removePending(id);
        entry?.reject(error);
      }
    });
  };

  const drain = () => {
    if (pending.size === 0) return Promise.resolve();
    return new Promise((resolve) => drainWaiters.add(resolve));
  };

  const close = (closeOptions = {}) => {
    if (closed) return Promise.resolve();
    if (closePromise) return closePromise;
    if (!closeOptions || typeof closeOptions !== "object" || Array.isArray(closeOptions)) {
      return Promise.reject(new TypeError("close options must be an object"));
    }
    const effectiveTimeout = assertTimeout(
      closeOptions.timeoutMs ?? closeTimeoutMs,
      "close timeoutMs",
    );
    closing = true;
    closePromise = (async () => {
      if (pending.size > 0) {
        let timer;
        try {
          await Promise.race([
            drain(),
            new Promise((_, reject) => {
              timer = setTimeout(
                () =>
                  reject(
                    timeoutError(
                      `flags2env worker close timed out after ${effectiveTimeout}ms`,
                    ),
                  ),
                effectiveTimeout,
              );
            }),
          ]);
        } catch (error) {
          terminate(error);
          throw error;
        } finally {
          clearTimeout(timer);
        }
      }
      terminate("flags2env worker was closed");
    })();
    return closePromise;
  };

  try {
    await request("__init", [configText]);
  } catch (error) {
    terminate(
      error?.name === "AbortError"
        ? error
        : "flags2env worker initialization failed",
    );
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
    drain,
    close,
    terminate,
    get pendingRequests() {
      return pending.size;
    },
    get closing() {
      return closing;
    },
    get closed() {
      return closed;
    },
  });
}

export default createFlags2EnvWorker;
