import { createFlags2Env } from "../dist/lib.mjs";
import {
  DemoEvent,
  DemoPhase,
  initialDemoState,
  reduceDemoLifecycle,
} from "../dist/lifecycle.mjs";

const status = document.querySelector("#status");
const output = document.querySelector("#output");
const argvInput = document.querySelector("#argv-json");
const coerceInput = document.querySelector("#coerce-json");
let lifecycle = initialDemoState();

function transition(event) {
  const outcome = reduceDemoLifecycle(lifecycle, event);
  lifecycle = outcome.state;
  status.dataset.phase = lifecycle.phase;
  if (!outcome.accepted) {
    throw new Error("flags2env demo lifecycle failed closed");
  }
}

status.dataset.phase = lifecycle.phase;

function render(value) {
  output.textContent = typeof value === "string" ? value : JSON.stringify(value, null, 2);
}

function parseInput(element, label) {
  let value;
  try {
    value = JSON.parse(element.value);
  } catch (error) {
    throw new SyntaxError(`${label} is not valid JSON: ${error.message}`);
  }
  return value;
}

async function initialize() {
  const configResponse = await fetch("./config.toml", { cache: "no-store" });
  if (!configResponse.ok) {
    throw new Error(`could not load config.toml: HTTP ${configResponse.status}`);
  }
  const flags2env = await createFlags2Env({ configText: await configResponse.text() });

  document.querySelector("[data-action='parse']").addEventListener("click", () => {
    render(flags2env.parse(parseInput(argvInput, "argv JSON")));
  });
  document.querySelector("[data-action='structured']").addEventListener("click", () => {
    render(flags2env.parseStructured(parseInput(argvInput, "argv JSON")));
  });
  document.querySelector("[data-action='help']").addEventListener("click", () => {
    render(flags2env.helpTableForArgv("tool", parseInput(argvInput, "argv JSON"), 100));
  });
  document.querySelector("[data-action='audit']").addEventListener("click", () => {
    render(flags2env.auditConfig());
  });
  document.querySelector("[data-action='coerce']").addEventListener("click", () => {
    render(flags2env.coerce(parseInput(coerceInput, "environment JSON")));
  });

  transition(DemoEvent.INITIALIZED);
  status.textContent = "Ready — native parser loaded in WebAssembly.";
  status.dataset.ready = "true";
  window.__flags2env = flags2env;
  return flags2env;
}

window.__flags2envReady = initialize().catch((error) => {
  if (lifecycle.phase === DemoPhase.INITIALIZING) {
    transition(DemoEvent.INITIALIZATION_FAILED);
  }
  status.textContent = `Failed to initialize: ${error.message}`;
  status.dataset.ready = "false";
  render({ error: error.message });
  throw error;
});
