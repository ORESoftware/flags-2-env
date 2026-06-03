type EnvMap = Record<string, string>;

type Flags2EnvOptions = {
  configPath?: string;
  libraryPath?: string | URL;
};

let library:
  | Deno.DynamicLibrary<{
    f2e_parse_json_argv: { parameters: ["buffer"]; result: "pointer" };
    f2e_parse_json_argv_from_file: { parameters: ["buffer", "buffer"]; result: "pointer" };
    f2e_parse_process: { parameters: []; result: "pointer" };
    f2e_parse_process_from_file: { parameters: ["buffer"]; result: "pointer" };
    f2e_free: { parameters: ["pointer"]; result: "void" };
  }>
  | undefined;

function defaultLibraryPath(): URL {
  const suffix = Deno.build.os === "windows" ? "dll" : Deno.build.os === "darwin" ? "dylib" : "so";
  return new URL(`./native/libflags2env.${suffix}`, import.meta.url);
}

function cstring(value: string): Uint8Array {
  return new TextEncoder().encode(`${value}\0`);
}

function native(libraryPath?: string | URL) {
  if (!library) {
    library = Deno.dlopen(libraryPath ?? defaultLibraryPath(), {
      f2e_parse_json_argv: {
        parameters: ["buffer"],
        result: "pointer",
      },
      f2e_parse_json_argv_from_file: {
        parameters: ["buffer", "buffer"],
        result: "pointer",
      },
      f2e_parse_process: {
        parameters: [],
        result: "pointer",
      },
      f2e_parse_process_from_file: {
        parameters: ["buffer"],
        result: "pointer",
      },
      f2e_free: {
        parameters: ["pointer"],
        result: "void",
      },
    } as const);
  }
  return library.symbols;
}

function readJsonPointer(pointer: Deno.PointerValue, libraryPath?: string | URL): EnvMap {
  if (pointer === null) {
    return {};
  }
  try {
    const raw = new Deno.UnsafePointerView(pointer).getCString();
    return JSON.parse(raw) as EnvMap;
  } finally {
    native(libraryPath).f2e_free(pointer);
  }
}

export function parse(argv: string[] = Deno.args, options: Flags2EnvOptions = {}): EnvMap {
  const argvJson = cstring(JSON.stringify(argv.map(String)));
  const result = options.configPath
    ? native(options.libraryPath).f2e_parse_json_argv_from_file(cstring(options.configPath), argvJson)
    : native(options.libraryPath).f2e_parse_json_argv(argvJson);
  return readJsonPointer(result, options.libraryPath);
}

export function parseProcess(options: Flags2EnvOptions = {}): EnvMap {
  const result = options.configPath
    ? native(options.libraryPath).f2e_parse_process_from_file(cstring(options.configPath))
    : native(options.libraryPath).f2e_parse_process();
  return readJsonPointer(result, options.libraryPath);
}

export function envMap(): EnvMap {
  try {
    return Deno.env.toObject();
  } catch {
    return {};
  }
}

export function apply(target: EnvMap = envMap(), argv: string[] = Deno.args, options: Flags2EnvOptions = {}): EnvMap {
  return { ...target, ...parse(argv, options) };
}

export function applyProcess(target: EnvMap = envMap(), options: Flags2EnvOptions = {}): EnvMap {
  return { ...target, ...parseProcess(options) };
}
