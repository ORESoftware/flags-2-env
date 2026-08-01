import createFlags2EnvModule from "./flags2env.mjs";

const CONFIG_DIR = "/flags2env";
const CONFIG_PATH = `${CONFIG_DIR}/.cli-flags.toml`;
const MAX_CONFIG_BYTES = 1024 * 1024;
const MAX_ARGV_ITEMS = 4096;
const MAX_ARGUMENT_BYTES = 64 * 1024;
const MAX_PAYLOAD_BYTES = 4 * 1024 * 1024;
const encoder = new TextEncoder();

function assertString(value, label, maxBytes = MAX_PAYLOAD_BYTES) {
  if (typeof value !== "string") {
    throw new TypeError(`${label} must be a string`);
  }
  if (value.includes("\0")) {
    throw new TypeError(`${label} must not contain NUL bytes`);
  }
  const bytes = encoder.encode(value).byteLength;
  if (bytes > maxBytes) {
    throw new RangeError(`${label} exceeds the ${maxBytes}-byte browser limit`);
  }
  return value;
}

function assertArgv(argv) {
  if (!Array.isArray(argv) || argv.some((item) => typeof item !== "string")) {
    throw new TypeError("argv must be an array of strings");
  }
  if (argv.length > MAX_ARGV_ITEMS) {
    throw new RangeError(`argv exceeds the ${MAX_ARGV_ITEMS}-item browser limit`);
  }
  let totalBytes = 0;
  for (let index = 0; index < argv.length; index += 1) {
    const item = assertString(argv[index], `argv[${index}]`, MAX_ARGUMENT_BYTES);
    totalBytes += encoder.encode(item).byteLength;
  }
  if (totalBytes > MAX_PAYLOAD_BYTES) {
    throw new RangeError(`argv exceeds the ${MAX_PAYLOAD_BYTES}-byte browser limit`);
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
  let active = false;

  const withCall = (callback) => {
    if (active) {
      throw new Error("flags2env browser calls are not re-entrant");
    }
    active = true;
    try {
      return callback();
    } finally {
      active = false;
    }
  };

  const writeConfig = (nextConfig) => {
    module.FS.writeFile(
      CONFIG_PATH,
      assertString(nextConfig, "configText", MAX_CONFIG_BYTES),
      { encoding: "utf8" },
    );
  };
  writeConfig(configText);

  const callConfigAndJson = (operation, fn, payload) =>
    withCall(() =>
      withCString(module, CONFIG_PATH, (configPointer) =>
        withCString(module, payload, (payloadPointer) =>
          copyOwnedResult(module, fn(configPointer, payloadPointer), operation),
        ),
      ),
    );

  return Object.freeze({
    setConfig(nextConfig) {
      return withCall(() => writeConfig(nextConfig));
    },

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

    resolveCommands(argv) {
      const raw = callConfigAndJson(
        "resolveCommands",
        module._f2e_resolve_commands_json_argv_from_file,
        JSON.stringify(assertArgv(argv)),
      );
      return parseJsonResult(raw, "resolveCommands");
    },

    auditConfig() {
      const raw = withCall(() =>
        withCString(module, CONFIG_PATH, (configPointer) =>
          copyOwnedResult(
            module,
            module._f2e_audit_config_from_file(configPointer),
            "auditConfig",
          ),
        ),
      );
      return parseJsonResult(raw, "auditConfig");
    },

    coerce(values) {
      if (!values || typeof values !== "object" || Array.isArray(values)) {
        throw new TypeError("coerce values must be an object");
      }
      const payload = JSON.stringify(values);
      if (typeof payload !== "string") {
        throw new TypeError("coerce values must be JSON serializable");
      }
      assertString(payload, "coerce values");
      const raw = callConfigAndJson(
        "coerce",
        module._f2e_coerce_json_from_file,
        payload,
      );
      return parseJsonResult(raw, "coerce");
    },

    helpTableForArgv(command, argv, terminalColumns = 80) {
      if (!Number.isInteger(terminalColumns) || terminalColumns < 1 || terminalColumns > 1000) {
        throw new RangeError("terminalColumns must be an integer between 1 and 1000");
      }
      const argvJson = JSON.stringify(assertArgv(argv));
      return withCall(() =>
        withCString(module, CONFIG_PATH, (configPointer) =>
          withCString(module, assertString(command, "command", 4096), (commandPointer) =>
            withCString(module, argvJson, (argvPointer) =>
              copyOwnedResult(
                module,
                module._f2e_help_table_for_json_argv_from_file(
                  configPointer,
                  commandPointer,
                  argvPointer,
                  terminalColumns,
                ),
                "helpTableForArgv",
              ),
            ),
          ),
        ),
      );
    },
  });
}

export default createFlags2Env;
