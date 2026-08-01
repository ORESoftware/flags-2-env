import createFlags2EnvModule from "./dist/flags2env.mjs";

const DEFAULT_CONFIG_PATH = "/flags2env/.cli-flags.toml";
const MAX_CONFIG_BYTES = 1024 * 1024;
const MAX_ARGV_ITEMS = 4096;
const MAX_ARG_BYTES = 64 * 1024;
const MAX_ARGV_BYTES = 4 * 1024 * 1024;
const encoder = new TextEncoder();

export class CoercionError extends TypeError {
  constructor(errors) {
    super(`flags2env could not coerce config: ${errors.join("; ")}`);
    this.name = "CoercionError";
    this.errors = [...errors];
  }
}

function assertText(value, name, maxBytes) {
  if (typeof value !== "string") {
    throw new TypeError(`${name} must be a string`);
  }
  if (value.includes("\0")) {
    throw new TypeError(`${name} must not contain NUL bytes`);
  }
  const bytes = encoder.encode(value).byteLength;
  if (bytes > maxBytes) {
    throw new RangeError(`${name} exceeds the ${maxBytes}-byte browser limit`);
  }
  return value;
}

function normalizeArgv(argv) {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  if (argv.length > MAX_ARGV_ITEMS) {
    throw new RangeError(`argv exceeds the ${MAX_ARGV_ITEMS}-item browser limit`);
  }
  let totalBytes = 0;
  const normalized = argv.map((value, index) => {
    const item = assertText(String(value), `argv[${index}]`, MAX_ARG_BYTES);
    totalBytes += encoder.encode(item).byteLength;
    return item;
  });
  if (totalBytes > MAX_ARGV_BYTES) {
    throw new RangeError(`argv exceeds the ${MAX_ARGV_BYTES}-byte browser limit`);
  }
  return normalized;
}

function parseJsonResult(raw, operation) {
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new TypeError(`${operation} returned invalid JSON: ${error.message}`);
  }
}

function ensureDirectory(fs, path) {
  const parts = path.split("/").filter(Boolean);
  let current = "";
  for (const part of parts) {
    current += `/${part}`;
    try {
      fs.mkdir(current);
    } catch (error) {
      if (error?.errno !== 20 && error?.code !== "EEXIST") {
        throw error;
      }
    }
  }
}

/**
 * Instantiate the real C parser as WebAssembly and bind it to one immutable
 * browser-side TOML contract. Create another client to use another contract.
 */
export async function createFlags2EnvBrowser(config, options = {}) {
  const configText = assertText(config, "config", MAX_CONFIG_BYTES);
  const configPath = options.configPath || DEFAULT_CONFIG_PATH;
  assertText(configPath, "configPath", 4096);
  if (!configPath.startsWith("/") || configPath.endsWith("/")) {
    throw new TypeError("configPath must be an absolute virtual file path");
  }

  const moduleFactory = options.moduleFactory || createFlags2EnvModule;
  const module = await moduleFactory({ noInitialRun: true });
  if (!module?.FS || typeof module.ccall !== "function" || typeof module.UTF8ToString !== "function") {
    throw new TypeError("the WebAssembly module does not expose the required flags2env runtime methods");
  }
  if (typeof module._f2e_free !== "function") {
    throw new TypeError("the WebAssembly module does not expose f2e_free");
  }

  const parent = configPath.slice(0, configPath.lastIndexOf("/")) || "/";
  ensureDirectory(module.FS, parent);
  module.FS.writeFile(configPath, configText, { encoding: "utf8" });

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

  const ownedString = (name, argTypes, args) =>
    withCall(() => {
      const pointer = module.ccall(name, "number", argTypes, args);
      if (!pointer) {
        throw new Error(`${name} returned a null pointer`);
      }
      try {
        return module.UTF8ToString(pointer);
      } finally {
        module._f2e_free(pointer);
      }
    });

  const argvJson = (argv) => JSON.stringify(normalizeArgv(argv));

  return Object.freeze({
    parse(argv = ["flags2env"]) {
      return parseJsonResult(
        ownedString(
          "f2e_parse_json_argv_from_file",
          ["string", "string"],
          [configPath, argvJson(argv)],
        ),
        "parse",
      );
    },

    parseStructured(argv = ["flags2env"]) {
      return parseJsonResult(
        ownedString(
          "f2e_parse_structured_json_argv_from_file",
          ["string", "string"],
          [configPath, argvJson(argv)],
        ),
        "parseStructured",
      );
    },

    resolveCommands(argv = ["flags2env"]) {
      return parseJsonResult(
        ownedString(
          "f2e_resolve_commands_json_argv_from_file",
          ["string", "string"],
          [configPath, argvJson(argv)],
        ),
        "resolveCommands",
      );
    },

    auditConfig() {
      return parseJsonResult(
        ownedString("f2e_audit_config_from_file", ["string"], [configPath]),
        "auditConfig",
      );
    },

    helpTableForArgv(command = "flags2env", argv = ["flags2env"], terminalColumns = 100) {
      assertText(String(command), "command", 4096);
      if (!Number.isInteger(terminalColumns) || terminalColumns < 0 || terminalColumns > 1000) {
        throw new RangeError("terminalColumns must be an integer between 0 and 1000");
      }
      return ownedString(
        "f2e_help_table_for_json_argv_from_file",
        ["string", "string", "string", "number"],
        [configPath, String(command), argvJson(argv), terminalColumns],
      );
    },

    completionScript(shell, command = "flags2env") {
      assertText(String(shell), "shell", 64);
      assertText(String(command), "command", 4096);
      return ownedString(
        "f2e_completion_script_from_file",
        ["string", "string", "string"],
        [configPath, String(shell), String(command)],
      );
    },

    coerce(values) {
      if (!values || typeof values !== "object" || Array.isArray(values)) {
        throw new TypeError("coerce values must be an object");
      }
      const valuesJson = JSON.stringify(values);
      if (typeof valuesJson !== "string") {
        throw new TypeError("coerce values must be JSON serializable");
      }
      assertText(valuesJson, "coerce values", MAX_ARGV_BYTES);
      const report = parseJsonResult(
        ownedString(
          "f2e_coerce_json_from_file",
          ["string", "string"],
          [configPath, valuesJson],
        ),
        "coerce",
      );
      if (!report.ok) {
        throw new CoercionError(report.errors || ["unknown coercion failure"]);
      }
      return report.value;
    },
  });
}

export default createFlags2EnvBrowser;
