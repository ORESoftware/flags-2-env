import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
let nativeModule;

export class CoercionError extends TypeError {
  constructor(errors) {
    super(`flags2env could not coerce config: ${errors.join("; ")}`);
    this.name = "CoercionError";
    this.errors = [...errors];
  }
}

function native() {
  if (!nativeModule) {
    nativeModule = require(process.env.FLAGS2ENV_NODE_ADDON || "./build/Release/flags2env.node");
  }
  return nativeModule;
}

function resolveTerminalColumns(target, requested) {
  if (requested && Number.isFinite(requested) && requested > 0) {
    return Math.floor(requested);
  }
  if (target?.columns && Number.isFinite(target.columns) && target.columns > 0) {
    return Math.floor(target.columns);
  }
  if (process.stdout.columns && Number.isFinite(process.stdout.columns) && process.stdout.columns > 0) {
    return Math.floor(process.stdout.columns);
  }
  const envColumns = Number(process.env.COLUMNS);
  return Number.isFinite(envColumns) && envColumns > 0 ? Math.floor(envColumns) : 0;
}

export function helpTable(command = "flags2env", options = {}) {
  return options.configPath
    ? native().helpTable(String(command), options.terminalColumns || 0, options.configPath)
    : native().helpTable(String(command), options.terminalColumns || 0);
}

export function helpTableForArgv(command = "flags2env", argv = process.argv, options = {}) {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvJson = JSON.stringify(argv.map(String));
  if (typeof native().helpTableForArgv !== "function") {
    return helpTable(command, options);
  }
  return options.configPath
    ? native().helpTableForArgv(String(command), argvJson, options.terminalColumns || 0, options.configPath)
    : native().helpTableForArgv(String(command), argvJson, options.terminalColumns || 0);
}

function withHelpMetadata(result, argvItems, argvJson, options) {
  const command = argvItems[0] || "flags2env";
  const isHelpMenu = native().isHelpJson(argvJson);
  Object.defineProperties(result, {
    isHelpMenu: {
      enumerable: false,
      value: isHelpMenu,
    },
    printTable: {
      enumerable: false,
      value(target = process.stdout) {
        if (!target || typeof target.write !== "function") {
          throw new TypeError("printTable target must expose write(chunk)");
        }
        const table = helpTableForArgv(command, argvItems, {
          configPath: options.configPath,
          terminalColumns: resolveTerminalColumns(target),
        });
        const output = table.endsWith("\n") ? table : `${table}\n`;
        target.write(output);
        return table;
      },
    },
  });
  return result;
}

export function parse(argv = process.argv, options = {}) {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvItems = argv.map(String);
  const argvJson = JSON.stringify(argvItems);
  const raw = options.configPath ? native().parseJson(argvJson, options.configPath) : native().parseJson(argvJson);
  return withHelpMetadata(JSON.parse(raw), argvItems, argvJson, options);
}

export function parseFromArgs(argv = process.argv, options = {}) {
  return parse(argv, options);
}

/**
 * Structured parse: {flags, command, subcommands, extras, unknownOptions,
 * errors} as separate channels (dashdash-style), so nothing is packed into —
 * or shadowed by — env keys. `flags` is the same map parse() returns.
 */
export function parseStructured(argv = process.argv, options = {}) {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvItems = argv.map(String);
  const argvJson = JSON.stringify(argvItems);
  const raw = options.configPath
    ? native().parseStructuredJson(argvJson, options.configPath)
    : native().parseStructuredJson(argvJson);
  return withHelpMetadata(JSON.parse(raw), argvItems, argvJson, options);
}

/** Resolves just the [commands.*] path for argv: {path: string[], label}. */
export function resolveCommands(argv = process.argv, options = {}) {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvJson = JSON.stringify(argv.map(String));
  const raw = options.configPath
    ? native().resolveCommandsJson(argvJson, options.configPath)
    : native().resolveCommandsJson(argvJson);
  return JSON.parse(raw);
}

export function parseProcess(options = {}) {
  const argvItems = process.argv.map(String);
  const argvJson = JSON.stringify(argvItems);
  const raw = options.configPath ? native().parseProcessJson(options.configPath) : native().parseProcessJson();
  return withHelpMetadata(JSON.parse(raw), argvItems, argvJson, options);
}

export function apply(target = process.env, argv = process.argv, options = {}) {
  return Object.assign(target, parse(argv, options));
}

export function applyProcess(target = process.env, options = {}) {
  return Object.assign(target, parseProcess(options));
}

export function auditConfig(options = {}) {
  const raw = options.configPath ? native().auditConfigJson(options.configPath) : native().auditConfigJson();
  return JSON.parse(raw);
}

export function auditConfigStatus(options = {}) {
  return options.configPath ? native().auditConfigStatus(options.configPath) : native().auditConfigStatus();
}

export function auditEnv(options = {}) {
  const raw = options.configPath
    ? native().auditEnvJson(options.configPath, options.envPath)
    : native().auditEnvJson();
  return JSON.parse(raw);
}

export function auditEnvStatus(options = {}) {
  return options.configPath
    ? native().auditEnvStatus(options.configPath, options.envPath)
    : native().auditEnvStatus();
}

export function completionScript(shell, command = "flags2env", options = {}) {
  return options.configPath
    ? native().completionScript(String(shell), String(command), options.configPath)
    : native().completionScript(String(shell), String(command));
}

export function generateTypes(language, options = {}) {
  return options.configPath
    ? native().generateTypes(String(language), options.typeName, options.configPath)
    : native().generateTypes(String(language), options.typeName);
}

export function coerce(values = process.env, options = {}) {
  if (!values || typeof values !== "object" || Array.isArray(values)) {
    throw new TypeError("coerce values must be an object");
  }
  const valuesJson = JSON.stringify(values);
  if (typeof valuesJson !== "string") {
    throw new TypeError("coerce values must be JSON serializable");
  }
  const raw = options.configPath
    ? native().coerceJson(valuesJson, options.configPath)
    : native().coerceJson(valuesJson);
  const report = JSON.parse(raw);
  if (!report.ok) {
    throw new CoercionError(report.errors);
  }
  return report.value;
}

export default {
  parse,
  parseFromArgs,
  parseProcess,
  apply,
  applyProcess,
  coerce,
  CoercionError,
  auditConfig,
  auditConfigStatus,
  auditEnv,
  auditEnvStatus,
  completionScript,
  generateTypes,
  helpTable,
  helpTableForArgv,
};
