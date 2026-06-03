import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
let nativeModule;

function native() {
  if (!nativeModule) {
    nativeModule = require(process.env.FLAGS2ENV_NODE_ADDON || "./build/Release/flags2env.node");
  }
  return nativeModule;
}

export function parse(argv = process.argv, options = {}) {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvJson = JSON.stringify(argv.map(String));
  const raw = options.configPath ? native().parseJson(argvJson, options.configPath) : native().parseJson(argvJson);
  return JSON.parse(raw);
}

export function parseProcess(options = {}) {
  const raw = options.configPath ? native().parseProcessJson(options.configPath) : native().parseProcessJson();
  return JSON.parse(raw);
}

export function apply(target = process.env, argv = process.argv, options = {}) {
  return Object.assign(target, parse(argv, options));
}

export function applyProcess(target = process.env, options = {}) {
  return Object.assign(target, parseProcess(options));
}

export default {
  parse,
  parseProcess,
  apply,
  applyProcess,
};
