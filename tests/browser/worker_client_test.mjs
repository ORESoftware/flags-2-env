import assert from "node:assert/strict";
import test from "node:test";

import { createFlags2EnvWorker } from "../../clients/browser/worker-client.mjs";

class FakeWorker {
  constructor({ delayMs = 0, hangMethods = new Set() } = {}) {
    this.delayMs = delayMs;
    this.hangMethods = hangMethods;
    this.listeners = new Map();
    this.terminated = false;
    this.messages = [];
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener);
    this.listeners.set(type, listeners);
  }

  emit(type, data) {
    for (const listener of this.listeners.get(type) ?? []) {
      listener(type === "message" ? { data } : data);
    }
  }

  postMessage(message) {
    if (this.terminated) throw new Error("worker already terminated");
    this.messages.push(message);
    if (this.hangMethods.has(message.method)) return;
    setTimeout(() => {
      if (this.terminated) return;
      const value = message.method === "__init" ? true : { id: message.id };
      this.emit("message", { id: message.id, ok: true, value });
    }, this.delayMs);
  }

  terminate() {
    this.terminated = true;
  }
}

function factoryFor(worker) {
  return () => worker;
}

test("backpressure caps pending requests and drain observes accepted work", async () => {
  const worker = new FakeWorker({ delayMs: 25 });
  const client = await createFlags2EnvWorker({
    workerFactory: factoryFor(worker),
    maxPendingRequests: 2,
    timeoutMs: 1000,
  });

  const first = client.parse(["tool"]);
  const second = client.parse(["tool"]);
  assert.equal(client.pendingRequests, 2);
  await assert.rejects(client.parse(["tool"]), (error) => error.name === "BusyError");

  const drained = client.drain();
  await Promise.all([first, second, drained]);
  assert.equal(client.pendingRequests, 0);
  client.terminate();
});

test("close drains accepted requests and rejects new work", async () => {
  const worker = new FakeWorker({ delayMs: 20 });
  const client = await createFlags2EnvWorker({ workerFactory: factoryFor(worker) });
  const accepted = client.parse(["tool"]);
  const closing = client.close({ timeoutMs: 1000 });
  assert.equal(client.closing, true);
  await assert.rejects(client.parse(["tool"]), /closing/);
  await accepted;
  await closing;
  assert.equal(client.closed, true);
  assert.equal(worker.terminated, true);
});

test("close timeout terminates and rejects pending work", async () => {
  const worker = new FakeWorker({ hangMethods: new Set(["parse"]) });
  const client = await createFlags2EnvWorker({
    workerFactory: factoryFor(worker),
    timeoutMs: 1000,
  });
  const pending = client.parse(["tool"]);
  await assert.rejects(
    client.close({ timeoutMs: 20 }),
    (error) => error.name === "TimeoutError",
  );
  await assert.rejects(pending, (error) => error.name === "TimeoutError");
  assert.equal(client.closed, true);
});

test("AbortSignal terminates the worker and rejects pending work", async () => {
  const worker = new FakeWorker({ hangMethods: new Set(["parse"]) });
  const controller = new AbortController();
  const client = await createFlags2EnvWorker({
    workerFactory: factoryFor(worker),
    signal: controller.signal,
    timeoutMs: 1000,
  });
  const pending = client.parse(["tool"]);
  controller.abort();
  await assert.rejects(pending, (error) => error.name === "AbortError");
  assert.equal(client.closed, true);
  assert.equal(worker.terminated, true);
});

test("already-aborted signals fail before a worker is created", async () => {
  const controller = new AbortController();
  controller.abort();
  let created = false;
  await assert.rejects(
    createFlags2EnvWorker({
      signal: controller.signal,
      workerFactory: () => {
        created = true;
        return new FakeWorker();
      },
    }),
    (error) => error.name === "AbortError",
  );
  assert.equal(created, false);
});

test("immediate terminate remains idempotent", async () => {
  const worker = new FakeWorker();
  const client = await createFlags2EnvWorker({ workerFactory: factoryFor(worker) });
  client.terminate("manual stop");
  client.terminate("second stop");
  assert.equal(client.closed, true);
  await assert.rejects(client.auditConfig(), /closed/);
});
