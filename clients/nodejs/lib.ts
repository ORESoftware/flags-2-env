import { createRequire } from "node:module";

export type EnvMap = Record<string, string>;

export type Flags2EnvOptions = {
  configPath?: string;
};

export type HelpTableOptions = Flags2EnvOptions & {
  terminalColumns?: number;
};

export type TableWriter = {
  columns?: number;
  write(chunk: string): unknown;
};

export type ParseResult = EnvMap & {
  readonly isHelpMenu: boolean;
  printTable(target?: TableWriter): string;
};

export type AuditEnvOptions = Flags2EnvOptions & {
  envPath?: string;
};

export type AuditReport = {
  ok: boolean;
  errorCount: number;
  warningCount: number;
  errors: string[];
  warnings: string[];
};

type NativeModule = {
  parseJson(argvJson: string, configPath?: string): string;
  parseProcessJson(configPath?: string): string;
  auditConfigJson(configPath?: string): string;
  auditConfigStatus(configPath?: string): number;
  auditEnvJson(configPath?: string, envPath?: string): string;
  auditEnvStatus(configPath?: string, envPath?: string): number;
  completionScript(shell: string, command?: string, configPath?: string): string;
  isHelpJson(argvJson: string): boolean;
  helpTable(command?: string, terminalColumns?: number, configPath?: string): string;
};

const require = createRequire(import.meta.url);
let nativeModule: NativeModule | undefined;

function native(): NativeModule {
  if (!nativeModule) {
    nativeModule = require(process.env.FLAGS2ENV_NODE_ADDON || "./build/Release/flags2env.node") as NativeModule;
  }
  return nativeModule;
}

function envMap(): EnvMap {
  return process.env as EnvMap;
}

function resolveTerminalColumns(target?: TableWriter, requested?: number): number {
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

export function helpTable(command = "flags2env", options: HelpTableOptions = {}): string {
  return options.configPath
    ? native().helpTable(String(command), options.terminalColumns || 0, options.configPath)
    : native().helpTable(String(command), options.terminalColumns || 0);
}

function withHelpMetadata(result: EnvMap, argvItems: string[], argvJson: string, options: Flags2EnvOptions): ParseResult {
  const command = argvItems[0] || "flags2env";
  const isHelpMenu = native().isHelpJson(argvJson);
  Object.defineProperties(result, {
    isHelpMenu: {
      enumerable: false,
      value: isHelpMenu,
    },
    printTable: {
      enumerable: false,
      value(target: TableWriter = process.stdout): string {
        if (!target || typeof target.write !== "function") {
          throw new TypeError("printTable target must expose write(chunk)");
        }
        const table = helpTable(command, {
          configPath: options.configPath,
          terminalColumns: resolveTerminalColumns(target),
        });
        const output = table.endsWith("\n") ? table : `${table}\n`;
        target.write(output);
        return table;
      },
    },
  });
  return result as ParseResult;
}

export function parse(argv: readonly unknown[] = process.argv, options: Flags2EnvOptions = {}): ParseResult {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvItems = argv.map(String);
  const argvJson = JSON.stringify(argvItems);
  const raw = options.configPath ? native().parseJson(argvJson, options.configPath) : native().parseJson(argvJson);
  return withHelpMetadata(JSON.parse(raw) as EnvMap, argvItems, argvJson, options);
}

export function parseProcess(options: Flags2EnvOptions = {}): ParseResult {
  const argvItems = process.argv.map(String);
  const argvJson = JSON.stringify(argvItems);
  const raw = options.configPath ? native().parseProcessJson(options.configPath) : native().parseProcessJson();
  return withHelpMetadata(JSON.parse(raw) as EnvMap, argvItems, argvJson, options);
}

export function apply(target: EnvMap = envMap(), argv: readonly unknown[] = process.argv, options: Flags2EnvOptions = {}): EnvMap {
  return Object.assign(target, parse(argv, options));
}

export function applyProcess(target: EnvMap = envMap(), options: Flags2EnvOptions = {}): EnvMap {
  return Object.assign(target, parseProcess(options));
}

export function auditConfig(options: Flags2EnvOptions = {}): AuditReport {
  const raw = options.configPath ? native().auditConfigJson(options.configPath) : native().auditConfigJson();
  return JSON.parse(raw) as AuditReport;
}

export function auditConfigStatus(options: Flags2EnvOptions = {}): number {
  return options.configPath ? native().auditConfigStatus(options.configPath) : native().auditConfigStatus();
}

export function auditEnv(options: AuditEnvOptions = {}): AuditReport {
  const raw = options.configPath
    ? native().auditEnvJson(options.configPath, options.envPath)
    : native().auditEnvJson();
  return JSON.parse(raw) as AuditReport;
}

export function auditEnvStatus(options: AuditEnvOptions = {}): number {
  return options.configPath
    ? native().auditEnvStatus(options.configPath, options.envPath)
    : native().auditEnvStatus();
}

export function completionScript(shell: "bash" | "zsh" | string, command = "flags2env", options: Flags2EnvOptions = {}): string {
  return options.configPath
    ? native().completionScript(String(shell), String(command), options.configPath)
    : native().completionScript(String(shell), String(command));
}

export default {
  parse,
  parseProcess,
  apply,
  applyProcess,
  auditConfig,
  auditConfigStatus,
  auditEnv,
  auditEnvStatus,
  completionScript,
  helpTable,
};
