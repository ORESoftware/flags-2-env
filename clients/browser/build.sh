#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/clients/browser/dist}"
# Resolved from the repository root above.
# shellcheck disable=SC1091
source "$ROOT/clients/browser/toolchain.env"

command -v emcc >/dev/null 2>&1 || {
  echo "emcc is required to build the browser client" >&2
  exit 1
}

actual_emcc_version=$(emcc --version | sed -n '1s/.*) \([0-9][0-9.]*\).*/\1/p')
if [[ "$actual_emcc_version" != "$F2E_EMSCRIPTEN_VERSION" ]]; then
  if [[ "${F2E_ALLOW_UNPINNED_EMSCRIPTEN:-0}" != "1" ]]; then
    echo "emcc $F2E_EMSCRIPTEN_VERSION is required; found ${actual_emcc_version:-unknown}" >&2
    echo "use the pinned image: $F2E_EMSCRIPTEN_IMAGE" >&2
    exit 1
  fi
  echo "warning: building with unsupported emcc ${actual_emcc_version:-unknown}" >&2
fi

mkdir -p "$OUT"

emcc "$ROOT/src/parser.c" \
  -I"$ROOT/src" \
  -include "$ROOT/clients/browser/compat.h" \
  -std=c99 \
  -Werror=implicit-function-declaration \
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
  -sEXPORTED_FUNCTIONS='["_malloc","_free","_f2e_parse_json_argv_from_file","_f2e_parse_structured_json_argv_from_file","_f2e_resolve_commands_json_argv_from_file","_f2e_audit_config_from_file","_f2e_coerce_json_from_file","_f2e_help_table_for_json_argv_from_file","_f2e_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["FS","UTF8ToString","stringToUTF8","lengthBytesUTF8"]' \
  -o "$OUT/flags2env.mjs"

cp "$ROOT/clients/browser/lib.mjs" "$OUT/lib.mjs"
cp "$ROOT/clients/browser/lib.d.ts" "$OUT/lib.d.ts"
cp "$ROOT/clients/browser/lifecycle.mjs" "$OUT/lifecycle.mjs"
cp "$ROOT/clients/browser/worker.mjs" "$OUT/worker.mjs"
cp "$ROOT/clients/browser/worker-client.mjs" "$OUT/worker-client.mjs"
cp "$ROOT/clients/browser/worker-client.d.ts" "$OUT/worker-client.d.ts"
printf 'browser WebAssembly client built at %s\n' "$OUT"
