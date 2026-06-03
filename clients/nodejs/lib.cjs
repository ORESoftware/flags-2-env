"use strict";

let nativeModule;

function native() {
  if (!nativeModule) {
    nativeModule = require(process.env.FLAGS2ENV_NODE_ADDON || "./build/Release/flags2env.node");
  }
  return nativeModule;
}

function parse(argv = process.argv, options = {}) {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvJson = JSON.stringify(argv.map(String));
  const raw = options.configPath ? native().parseJson(argvJson, options.configPath) : native().parseJson(argvJson);
  return JSON.parse(raw);
}

function parseProcess(options = {}) {
  const raw = options.configPath ? native().parseProcessJson(options.configPath) : native().parseProcessJson();
  return JSON.parse(raw);
}

function apply(target = process.env, argv = process.argv, options = {}) {
  return Object.assign(target, parse(argv, options));
}

function applyProcess(target = process.env, options = {}) {
  return Object.assign(target, parseProcess(options));
}

module.exports = {
  parse,
  parseProcess,
  apply,
  applyProcess,
};
module.exports.default = module.exports;
