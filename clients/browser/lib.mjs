import createFlags2EnvModule from "./flags2env.mjs";

const CONFIG_DIR = "/flags2env";
const CONFIG_PATH = `${CONFIG_DIR}/.cli-flags.toml`;

function assertString(value, label) {
  if (typeof value !== "string") {
    throw new TypeError(`${label} must be a string`);
  }
  return value;
}

function assertArgv(argv) {
  if (!Array.isArray(argv) || argv.some((item) => typeof item !== "string")) {
    throw new TypeError("argv must be an array of strings");
  }
  return argv;
}

function withCString(module, value, callback) {
  const text = assertString(value, "C string");
  const size = module.lengthBytesUTF8(text) + 1;
  const pointer = module._malloc(size);
  if (!pointer) {
    throw new Error(`flags2env WebAssembly could not allocate ${size} bytes`);
  }
  try {
    module.stringToUTF8(text, pointer, size);
    return callback(pointer);
  } finally {
    module._free(pointer);
  }
}

function copyOwnedResult(module, pointer, operation) {
  if (!pointer) {
    throw new Error(`${operation} returned a null pointer`);
  }
  try {
    return module.UTF8ToString(pointer);
  } finally {
    module._f2e_free(pointer);
  }
}

function parseJsonResult(raw, operation) {
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new SyntaxError(`${operation} returned invalid JSON: ${error.message}`);
  }
}

export async function createFlags2Env(options = {}) {
  const { configText = "", moduleOptions = {} } = options;
  const module = await createFlags2EnvModule(moduleOptions);
  module.FS.mkdirTree(CONFIG_DIR);

  const setConfig = (nextConfig) => {
    module.FS.writeFile(CONFIG_PATH, assertString(nextConfig, "configText"), {
      encoding: "utf8",
    });
  };
  setConfig(configText);

  const callConfigAndJson = (operation, fn, payload) =>
    withCString(module, CONFIG_PATH, (configPointer) =>
      withCString(module, payload, (payloadPointer) =>
        copyOwnedResult(module, fn(configPointer, payloadPointer), operation),
      ),
    );

  return Object.freeze({
    setConfig,

    parse(argv) {
      const raw = callConfigAndJson(
        "parse",
        module._f2e_parse_json_argv_from_file,
        JSON.stringify(assertArgv(argv)),
      );
      return parseJsonResult(raw, "parse");
    },

    parseStructured(argv) {
      const raw = callConfigAndJson(
        "parseStructured",
        module._f2e_parse_structured_json_argv_from_file,
        JSON.stringify(assertArgv(argv)),
      );
      return parseJsonResult(raw, "parseStructured");
    },

    auditConfig() {
      const raw = withCString(module, CONFIG_PATH, (configPointer) =>
        copyOwnedResult(
          module,
          module._f2e_audit_config_from_file(configPointer),
          "auditConfig",
        ),
      );
      return parseJsonResult(raw, "auditConfig");
    },

    coerce(values) {
      if (!values || typeof values !== "object" || Array.isArray(values)) {
        throw new TypeError("coerce values must be an object");
      }
      const raw = callConfigAndJson(
        "coerce",
        module._f2e_coerce_json_from_file,
        JSON.stringify(values),
      );
      return parseJsonResult(raw, "coerce");
    },

    helpTableForArgv(command, argv, terminalColumns = 80) {
      const columns = Number.isFinite(terminalColumns)
        ? Math.max(1, Math.floor(terminalColumns))
        : 80;
      const argvJson = JSON.stringify(assertArgv(argv));
      return withCString(module, CONFIG_PATH, (configPointer) =>
        withCString(module, assertString(command, "command"), (commandPointer) =>
          withCString(module, argvJson, (argvPointer) =>
            copyOwnedResult(
              module,
              module._f2e_help_table_for_json_argv_from_file(
                configPointer,
                commandPointer,
                argvPointer,
                columns,
              ),
              "helpTableForArgv",
            ),
          ),
        ),
      );
    },
  });
}

export default createFlags2Env;
