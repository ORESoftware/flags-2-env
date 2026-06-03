import { CString, FFIType, dlopen, suffix } from "bun:ffi";
import { join } from "node:path";

export type EnvMap = Record<string, string>;

export type Flags2EnvOptions = {
  configPath?: string;
  libraryPath?: string;
};

type NativeSymbols = {
  f2e_parse_json_argv(argvJson: Buffer): unknown;
  f2e_parse_json_argv_from_file(configPath: Buffer, argvJson: Buffer): unknown;
  f2e_parse_process(): unknown;
  f2e_parse_process_from_file(configPath: Buffer): unknown;
  f2e_free(value: unknown): void;
};

const defaultLibraryPath = join(import.meta.dir, "native", `libflags2env.${suffix}`);
let library: NativeSymbols | undefined;

function cstring(value: string): Buffer {
  return Buffer.from(`${value}\0`, "utf8");
}

function native(libraryPath?: string): NativeSymbols {
  if (!library) {
    library = dlopen(libraryPath || process.env.FLAGS2ENV_NATIVE_LIB || defaultLibraryPath, {
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
    }).symbols as NativeSymbols;
  }
  return library;
}

function readJsonPointer(resultPtr: unknown, libraryPath?: string): EnvMap {
  if (!resultPtr) {
    return {};
  }
  try {
    return JSON.parse(new CString(resultPtr as never).toString()) as EnvMap;
  } finally {
    native(libraryPath).f2e_free(resultPtr);
  }
}

function envMap(): EnvMap {
  return process.env as EnvMap;
}

export function parse(argv: readonly unknown[] = Bun.argv, options: Flags2EnvOptions = {}): EnvMap {
  if (!Array.isArray(argv)) {
    throw new TypeError("argv must be an array of strings");
  }
  const argvJson = cstring(JSON.stringify(argv.map(String)));
  const resultPtr = options.configPath
    ? native(options.libraryPath).f2e_parse_json_argv_from_file(cstring(options.configPath), argvJson)
    : native(options.libraryPath).f2e_parse_json_argv(argvJson);
  return readJsonPointer(resultPtr, options.libraryPath);
}

export function parseProcess(options: Flags2EnvOptions = {}): EnvMap {
  const resultPtr = options.configPath
    ? native(options.libraryPath).f2e_parse_process_from_file(cstring(options.configPath))
    : native(options.libraryPath).f2e_parse_process();
  return readJsonPointer(resultPtr, options.libraryPath);
}

export function apply(target: EnvMap = envMap(), argv: readonly unknown[] = Bun.argv, options: Flags2EnvOptions = {}): EnvMap {
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
