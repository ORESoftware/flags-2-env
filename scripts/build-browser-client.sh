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
rm -f "$tmp_file"

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

emcc "$repo_root/src/parser.c" \
  -I"$repo_root/src" \
  -O2 \
  -flto \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sSINGLE_FILE=1 \
  -sENVIRONMENT=web,worker \
  -sALLOW_MEMORY_GROWTH=1 \
  -sFILESYSTEM=1 \
  -sNO_EXIT_RUNTIME=1 \
  -sASSERTIONS=0 \
  -sEXPORTED_FUNCTIONS='["_f2e_parse_json_argv_from_file","_f2e_parse_structured_json_argv_from_file","_f2e_resolve_commands_json_argv_from_file","_f2e_help_table_for_json_argv_from_file","_f2e_audit_config_from_file","_f2e_coerce_json_from_file","_f2e_completion_script_from_file","_f2e_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["ccall","UTF8ToString","FS"]' \
  -o "$tmp_file"

# Refuse a surprising network-backed or dynamic-code-loading artifact. The
# client must remain a self-contained ES module once the local file is loaded.
if grep -Eq '(fetch\(|XMLHttpRequest|WebSocket|eval\(|new Function)' "$tmp_file"; then
  echo "error: generated browser module contains a forbidden network or dynamic-code primitive" >&2
  rm -f "$tmp_file"
  exit 1
fi

mv "$tmp_file" "$out_file"
printf 'built %s (%s bytes)\n' "$out_file" "$(wc -c <"$out_file")"
