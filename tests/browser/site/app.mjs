import { createFlags2EnvBrowser } from "/client/index.mjs";

const defaultContract = `[parse]
command_env = "APP_COMMAND"
unknown_options_env = "APP_UNKNOWN"
errors_env = "APP_ERRORS"
allow_unknown = false

[flags.verbose]
env = "APP_VERBOSE"
aliases = ["verbose"]
type = "bool"
default = "false"
help = "Enable verbose output."

[commands.develop]
aliases = ["dev"]
help = "Open the development environment."

[commands.develop.flags.profile]
env = "APP_PROFILE"
aliases = ["profile"]
type = "string"
default = "default"
help = "Development profile."

[commands.develop.flags.workers]
env = "APP_WORKERS"
aliases = ["workers"]
type = "int"
default = "2"
help = "Worker count."
`;

const contract = document.querySelector("#contract");
const argv = document.querySelector("#argv");
const values = document.querySelector("#values");
const result = document.querySelector("#result");
const status = document.querySelector("#status");

contract.value = defaultContract;
argv.value = '["zed", "dev", "--profile", "ai", "--workers", "4", "workspace"]';
values.value = '{"APP_VERBOSE":"yes","APP_WORKERS":"4"}';

function setStatus(message, state = "ok") {
  status.value = message;
  status.dataset.state = state;
}

function parseJsonInput(input, name) {
  let parsed;
  try {
    parsed = JSON.parse(input.value);
  } catch (error) {
    throw new TypeError(`${name} is not valid JSON: ${error.message}`);
  }
  return parsed;
}

async function run(operation) {
  setStatus("Running…");
  result.textContent = "";
  try {
    const client = await createFlags2EnvBrowser(contract.value);
    const parsedArgv = parseJsonInput(argv, "argv");
    let output;
    switch (operation) {
      case "structured":
        output = client.parseStructured(parsedArgv);
        break;
      case "audit":
        output = client.auditConfig();
        break;
      case "help":
        output = client.helpTableForArgv(parsedArgv[0] || "flags2env", parsedArgv, 88);
        break;
      case "coerce":
        output = client.coerce(parseJsonInput(values, "values"));
        break;
      default:
        throw new TypeError(`unknown operation: ${operation}`);
    }
    result.textContent = typeof output === "string" ? output : JSON.stringify(output, null, 2);
    setStatus("Complete");
  } catch (error) {
    result.textContent = `${error.name}: ${error.message}`;
    setStatus("Failed", "error");
  }
}

document.querySelectorAll("[data-operation]").forEach((button) => {
  button.addEventListener("click", () => run(button.dataset.operation));
});

window.flags2envDemo = Object.freeze({ run, defaultContract });
