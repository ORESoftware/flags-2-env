#!/usr/bin/env bash
set -euo pipefail

if ! command -v emcc >/dev/null 2>&1; then
  echo "error: emcc is required; install Emscripten before building the browser client" >&2
  exit 127
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/clients/browser/dist"
out_file="$out_dir/flags2env.mjs"
tmp_file="$out_file.tmp"

mkdir -p "$out_dir"
rm -f "$tmp_file" "$out_dir"/*.wasm

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

emcc "$repo_root/src/parser.c" \
  -I"$repo_root/src" \
  -O2 \
  -flto \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sSINGLE_FILE=1 \
  -sDYNAMIC_EXECUTION=0 \
  -sENVIRONMENT=web,worker \
  -sALLOW_MEMORY_GROWTH=1 \
  -sFILESYSTEM=1 \
  -sNO_EXIT_RUNTIME=1 \
  -sASSERTIONS=0 \
  -sEXPORTED_FUNCTIONS='["_f2e_parse_json_argv_from_file","_f2e_parse_structured_json_argv_from_file","_f2e_resolve_commands_json_argv_from_file","_f2e_help_table_for_json_argv_from_file","_f2e_audit_config_from_file","_f2e_coerce_json_from_file","_f2e_completion_script_from_file","_f2e_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["ccall","UTF8ToString","FS"]' \
  -o "$tmp_file"

# SINGLE_FILE is the enforceable runtime property: no WebAssembly sidecar may
# be emitted or fetched after the local ES module is loaded. DYNAMIC_EXECUTION=0
# makes Emscripten fail compilation if generated code would require eval/new
# Function. Avoid grepping generic loader source: Emscripten may retain dormant
# fallback text even when the corresponding capability is compiled out.
if find "$out_dir" -maxdepth 1 -type f -name '*.wasm' -print -quit | grep -q .; then
  echo "error: browser build unexpectedly emitted a WebAssembly sidecar" >&2
  rm -f "$tmp_file" "$out_dir"/*.wasm
  exit 1
fi
if grep -Eq 'https?://|wss?://' "$tmp_file"; then
  echo "error: generated browser module contains a remote URL" >&2
  rm -f "$tmp_file"
  exit 1
fi
if ! grep -q 'data:application/octet-stream;base64,' "$tmp_file"; then
  echo "error: generated browser module does not contain an embedded WebAssembly payload" >&2
  rm -f "$tmp_file"
  exit 1
fi

mv "$tmp_file" "$out_file"
printf 'built %s (%s bytes)\n' "$out_file" "$(wc -c <"$out_file")"
