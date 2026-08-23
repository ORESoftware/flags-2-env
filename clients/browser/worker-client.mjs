import {
  WorkerClientEvent,
  WorkerClientPhase,
  initialWorkerClientState,
  isWorkerClientTerminal,
  reduceWorkerClientLifecycle,
} from "./lifecycle.mjs";

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
  if (
    !worker ||
    typeof worker.addEventListener !== "function" ||
    typeof worker.postMessage !== "function" ||
    typeof worker.terminate !== "function"
  ) {
    try {
      worker?.terminate?.();
    } catch {
      // The invalid factory result is rejected below regardless of cleanup support.
    }
    throw new TypeError("workerFactory must return a Worker-compatible object");
  }

  let nextId = 1;
  let closePromise = null;
  let lifecycle = initialWorkerClientState();
  const pending = new Map();
  const drainWaiters = new Set();
  let failClosed = null;

  const transition = (event) => {
    const outcome = reduceWorkerClientLifecycle(
      lifecycle,
      event,
      maxPendingRequests,
    );
    lifecycle = outcome.state;
    return outcome;
  };

  const assertResourceInvariant = () => {
    if (lifecycle.pending !== pending.size) {
      const error = new Error("flags2env worker lifecycle/resource invariant failed");
      failClosed?.(error);
      throw error;
    }
  };

  const notifyDrained = () => {
    assertResourceInvariant();
    if (lifecycle.pending !== 0) return;
    for (const resolve of drainWaiters) resolve();
    drainWaiters.clear();
  };

  let onAbort = null;
  const stopWorker = () => {
    if (onAbort) {
      try {
        signal?.removeEventListener("abort", onAbort);
      } catch {
        // Termination must continue even for a malformed signal implementation.
      }
    }
    try {
      worker.terminate();
    } catch {
      // The lifecycle is already terminal; no response can be observed again.
    }
  };

  const takePending = () => {
    const entries = [...pending.values()];
    pending.clear();
    for (const entry of entries) clearTimeout(entry.timer);
    return entries;
  };

  const shutdown = (reason, event) => {
    const error = normalizeTerminationReason(reason);
    if (isWorkerClientTerminal(lifecycle)) {
      const entries = takePending();
      for (const entry of entries) entry.reject(error);
      notifyDrained();
      stopWorker();
      return;
    }

    const entries = takePending();
    const outcome = transition(event);
    if (!outcome.accepted || !isWorkerClientTerminal(lifecycle)) {
      lifecycle = reduceWorkerClientLifecycle(
        lifecycle,
        WorkerClientEvent.FAULT,
        maxPendingRequests,
      ).state;
    }
    assertResourceInvariant();
    for (const entry of entries) entry.reject(error);
    notifyDrained();
    stopWorker();
  };

  failClosed = (reason) => {
    const error = normalizeTerminationReason(reason);
    const entries = takePending();
    if (!isWorkerClientTerminal(lifecycle)) {
      transition(WorkerClientEvent.FAULT);
    }
    for (const entry of entries) entry.reject(error);
    notifyDrained();
    stopWorker();
    return error;
  };

  const settlePending = (id, succeeded) => {
    const entry = pending.get(id);
    if (!entry) return null;
    pending.delete(id);
    clearTimeout(entry.timer);
    const event =
      entry.kind === "initialization"
        ? succeeded
          ? WorkerClientEvent.INITIALIZED
          : WorkerClientEvent.INITIALIZATION_FAILED
        : WorkerClientEvent.REQUEST_SETTLED;
    const outcome = transition(event);
    if (!outcome.accepted) {
      return {
        entry,
        error: failClosed("flags2env worker lifecycle failed closed"),
      };
    }
    assertResourceInvariant();
    notifyDrained();
    return { entry, error: null };
  };

  const allocateId = () => {
    if (nextId > Number.MAX_SAFE_INTEGER) {
      throw new RangeError(
        "flags2env worker request ID space is exhausted; create a new worker",
      );
    }
    const id = nextId;
    nextId += 1;
    return id;
  };

  const requestStateError = (outcome) => {
    if (outcome.code === "busy") return busyError(maxPendingRequests);
    if (outcome.code === "closing") {
      return new Error("flags2env worker is closing");
    }
    if (isWorkerClientTerminal(outcome.state)) {
      return new Error("flags2env worker is closed");
    }
    return new Error("flags2env worker is not ready");
  };

  const request = (
    method,
    args = [],
    requestTimeoutMs = timeoutMs,
    kind = "request",
  ) => {
    if (typeof method !== "string" || !Array.isArray(args)) {
      return Promise.reject(new TypeError("worker request requires a method and args array"));
    }
    assertTimeout(requestTimeoutMs);
    assertResourceInvariant();
    const event =
      kind === "initialization"
        ? WorkerClientEvent.INITIALIZE_REQUESTED
        : WorkerClientEvent.REQUEST_STARTED;
    const started = reduceWorkerClientLifecycle(
      lifecycle,
      event,
      maxPendingRequests,
    );
    if (!started.accepted) return Promise.reject(requestStateError(started));

    const id = allocateId();
    const envelope = { id, method, args };
    assertSerializable(envelope);
    lifecycle = started.state;

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const settled = settlePending(id, false);
        settled?.entry.reject(
          settled.error ??
            timeoutError(`flags2env worker request timed out after ${requestTimeoutMs}ms`),
        );
      }, requestTimeoutMs);
      pending.set(id, { resolve, reject, timer, kind });
      try {
        assertResourceInvariant();
        worker.postMessage(envelope);
      } catch (error) {
        const settled = settlePending(id, false);
        settled?.entry.reject(settled.error ?? error);
      }
    });
  };

  try {
    worker.addEventListener("message", (event) => {
      const message = event.data;
      const settled = settlePending(message?.id, message?.ok === true);
      if (!settled) return;
      if (settled.error) settled.entry.reject(settled.error);
      else if (message.ok === true) settled.entry.resolve(message.value);
      else settled.entry.reject(remoteError(message.error));
    });
    worker.addEventListener("error", () =>
      shutdown("flags2env worker failed", WorkerClientEvent.FAULT),
    );
    worker.addEventListener("messageerror", () =>
      shutdown(
        "flags2env worker returned an invalid message",
        WorkerClientEvent.FAULT,
      ),
    );
    onAbort = () => shutdown(abortError(), WorkerClientEvent.TERMINATE);
    signal?.addEventListener("abort", onAbort, { once: true });
  } catch (error) {
    shutdown(error, WorkerClientEvent.FAULT);
    throw error;
  }
  if (signal?.aborted) {
    const error = abortError();
    shutdown(error, WorkerClientEvent.TERMINATE);
    throw error;
  }

  const terminate = (reason = "flags2env worker was terminated") => {
    if (isWorkerClientTerminal(lifecycle)) return;
    shutdown(reason, WorkerClientEvent.TERMINATE);
  };

  const drain = () => {
    assertResourceInvariant();
    if (lifecycle.pending === 0) return Promise.resolve();
    return new Promise((resolve) => drainWaiters.add(resolve));
  };

  const close = (closeOptions = {}) => {
    if (isWorkerClientTerminal(lifecycle)) return Promise.resolve();
    if (closePromise) return closePromise;
    if (!closeOptions || typeof closeOptions !== "object" || Array.isArray(closeOptions)) {
      return Promise.reject(new TypeError("close options must be an object"));
    }
    const effectiveTimeout = assertTimeout(
      closeOptions.timeoutMs ?? closeTimeoutMs,
      "close timeoutMs",
    );
    const started = transition(WorkerClientEvent.CLOSE_REQUESTED);
    if (!started.accepted) return Promise.reject(requestStateError(started));
    assertResourceInvariant();

    closePromise = (async () => {
      if (lifecycle.pending > 0) {
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
          shutdown(error, WorkerClientEvent.FAULT);
          throw error;
        } finally {
          clearTimeout(timer);
        }
      }
      if (isWorkerClientTerminal(lifecycle)) return;
      const completed = transition(WorkerClientEvent.DRAIN_COMPLETED);
      if (!completed.accepted) {
        const error = failClosed("flags2env worker close lifecycle failed closed");
        throw error;
      }
      assertResourceInvariant();
      stopWorker();
    })();
    return closePromise;
  };

  try {
    await request("__init", [configText], timeoutMs, "initialization");
  } catch (error) {
    if (!isWorkerClientTerminal(lifecycle)) {
      shutdown("flags2env worker initialization failed", WorkerClientEvent.FAULT);
    } else {
      stopWorker();
    }
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
    get state() {
      return lifecycle.phase;
    },
    get failed() {
      return lifecycle.phase === WorkerClientPhase.FAILED;
    },
    get pendingRequests() {
      return lifecycle.pending;
    },
    get closing() {
      return lifecycle.phase !== WorkerClientPhase.READY;
    },
    get closed() {
      return isWorkerClientTerminal(lifecycle);
    },
  });
}

export default createFlags2EnvWorker;
