import { createRequire } from "node:module";

export type EnvMap = Record<string, string>;

export type Flags2EnvOptions = {
  configPath?: string;
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

export function parse(argv: readonly unknown[] = process.argv, options: Flags2EnvOptions = {}): EnvMap {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvJson = JSON.stringify(argv.map(String));
  const raw = options.configPath ? native().parseJson(argvJson, options.configPath) : native().parseJson(argvJson);
  return JSON.parse(raw) as EnvMap;
}

export function parseProcess(options: Flags2EnvOptions = {}): EnvMap {
  const raw = options.configPath ? native().parseProcessJson(options.configPath) : native().parseProcessJson();
  return JSON.parse(raw) as EnvMap;
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
};
