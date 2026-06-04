import std/json

const libName =
  when defined(macosx):
    "libflags2env.dylib"
  elif defined(windows):
    "flags2env.dll"
  else:
    "libflags2env.so"

proc f2e_parse_json_argv(argvJson: cstring): cstring {.cdecl, dynlib: libName, importc.}
proc f2e_parse_json_argv_from_file(configPath: cstring, argvJson: cstring): cstring {.cdecl, dynlib: libName, importc.}
proc f2e_parse_process(): cstring {.cdecl, dynlib: libName, importc.}
proc f2e_parse_process_from_file(configPath: cstring): cstring {.cdecl, dynlib: libName, importc.}
proc f2e_free(value: cstring) {.cdecl, dynlib: libName, importc.}

proc ownedString(value: cstring): string =
  if value.isNil:
    return "{}"
  result = $value
  f2e_free(value)

proc parseJsonArgv*(argvJson: string): JsonNode =
  parseJson(ownedString(f2e_parse_json_argv(argvJson)))

proc parseJsonArgvFromFile*(configPath: string, argvJson: string): JsonNode =
  parseJson(ownedString(f2e_parse_json_argv_from_file(configPath, argvJson)))

proc parse*(argv: openArray[string]): JsonNode =
  parseJsonArgv($(%argv))

proc parseFromFile*(configPath: string, argv: openArray[string]): JsonNode =
  parseJsonArgvFromFile(configPath, $(%argv))

proc parseProcess*(): JsonNode =
  parseJson(ownedString(f2e_parse_process()))

proc parseProcessFromFile*(configPath: string): JsonNode =
  parseJson(ownedString(f2e_parse_process_from_file(configPath)))
