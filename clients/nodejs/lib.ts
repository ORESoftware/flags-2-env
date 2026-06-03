import { createRequire } from "node:module";

export type EnvMap = Record<string, string>;

export type Flags2EnvOptions = {
  configPath?: string;
};

type NativeModule = {
  parseJson(argvJson: string, configPath?: string): string;
  parseProcessJson(configPath?: string): string;
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

export default {
  parse,
  parseProcess,
  apply,
  applyProcess,
};
