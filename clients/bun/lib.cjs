"use strict";

const { CString, FFIType, dlopen, suffix } = require("bun:ffi");
const { join } = require("node:path");

const defaultLibraryPath = join(__dirname, "native", `libflags2env.${suffix}`);
let library;

function cstring(value) {
  return Buffer.from(`${value}\0`, "utf8");
}

function native() {
  if (!library) {
    library = dlopen(process.env.FLAGS2ENV_NATIVE_LIB || defaultLibraryPath, {
      f2e_parse_json_argv: {
        args: [FFIType.cstring],
        returns: FFIType.ptr,
      },
      f2e_parse_json_argv_from_file: {
        args: [FFIType.cstring, FFIType.cstring],
        returns: FFIType.ptr,
      },
      f2e_parse_process: {
        args: [],
        returns: FFIType.ptr,
      },
      f2e_parse_process_from_file: {
        args: [FFIType.cstring],
        returns: FFIType.ptr,
      },
      f2e_free: {
        args: [FFIType.ptr],
        returns: "void",
      },
    }).symbols;
  }
  return library;
}

function readJsonPointer(resultPtr) {
  if (!resultPtr) {
    return {};
  }
  try {
    return JSON.parse(new CString(resultPtr).toString());
  } finally {
    native().f2e_free(resultPtr);
  }
}

function parse(argv = Bun.argv, options = {}) {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvJson = cstring(JSON.stringify(argv.map(String)));
  const resultPtr = options.configPath
    ? native().f2e_parse_json_argv_from_file(cstring(options.configPath), argvJson)
    : native().f2e_parse_json_argv(argvJson);
  return readJsonPointer(resultPtr);
}

function parseProcess(options = {}) {
  const resultPtr = options.configPath
    ? native().f2e_parse_process_from_file(cstring(options.configPath))
    : native().f2e_parse_process();
  return readJsonPointer(resultPtr);
}

function apply(target = process.env, argv = Bun.argv, options = {}) {
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
