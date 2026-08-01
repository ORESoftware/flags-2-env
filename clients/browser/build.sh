#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/clients/browser/dist}"

command -v emcc >/dev/null 2>&1 || {
  echo "emcc is required to build the browser client" >&2
  exit 1
}

mkdir -p "$OUT"

emcc "$ROOT/src/parser.c" \
  -I"$ROOT/src" \
  -include "$ROOT/clients/browser/compat.h" \
  -std=c99 \
  -O2 \
  -DNDEBUG \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sEXPORT_NAME=createFlags2EnvModule \
  -sENVIRONMENT=web,worker \
  -sALLOW_MEMORY_GROWTH=1 \
  -sFILESYSTEM=1 \
  -sDYNAMIC_EXECUTION=0 \
  -sNO_EXIT_RUNTIME=1 \
  -sEXPORTED_FUNCTIONS='["_malloc","_free","_f2e_parse_json_argv_from_file","_f2e_parse_structured_json_argv_from_file","_f2e_audit_config_from_file","_f2e_coerce_json_from_file","_f2e_help_table_for_json_argv_from_file","_f2e_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["FS","UTF8ToString","stringToUTF8","lengthBytesUTF8"]' \
  -o "$OUT/flags2env.mjs"

cp "$ROOT/clients/browser/lib.mjs" "$OUT/lib.mjs"
printf 'browser WebAssembly client built at %s\n' "$OUT"
