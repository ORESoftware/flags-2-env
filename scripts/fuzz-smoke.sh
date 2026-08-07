#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FUZZ_SECONDS="${F2E_FUZZ_SECONDS:-20}"
FUZZ_RUNS="${F2E_FUZZ_RUNS:-0}"
WORK_DIR="${F2E_FUZZ_WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/flags2env-fuzz.XXXXXX")}"
FUZZ_SYSROOT=
DEFAULT_ASAN_OPTIONS="detect_leaks=1:strict_string_checks=1"

if [ -n "${CC:-}" ]; then
  FUZZ_CC="$CC"
elif [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
  LLVM_PREFIX="$(brew --prefix llvm 2>/dev/null || true)"
  if [ -n "$LLVM_PREFIX" ] && [ -x "$LLVM_PREFIX/bin/clang" ]; then
    FUZZ_CC="$LLVM_PREFIX/bin/clang"
    FUZZ_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
    DEFAULT_ASAN_OPTIONS="detect_leaks=0:strict_string_checks=1"
  else
    FUZZ_CC=clang
  fi
else
  FUZZ_CC=clang
fi

mkdir -p "$WORK_DIR"

export F2E_FUZZ_FIXTURE="$ROOT_DIR/tests/subcommands-deep/.cli-flags.toml"
export F2E_FUZZ_CONFIG="$WORK_DIR/fuzz-config.toml"
export F2E_FUZZ_ENV="$WORK_DIR/fuzz.env"

# ./.env is only ever read from the working directory, so the harness chdirs
# into a scratch directory of its own and writes the fuzzed file there
export F2E_FUZZ_DOTENV_CWD="$WORK_DIR/dotenv-cwd"
export F2E_FUZZ_DOTENV_CONFIG="$WORK_DIR/dotenv-config.toml"
mkdir -p "$F2E_FUZZ_DOTENV_CWD"
cat > "$F2E_FUZZ_DOTENV_CONFIG" <<'TOML'
[flags.str]
env = "F2E_FUZZ_STR"
aliases = ["str"]
type = "string"

[flags.int]
env = "F2E_FUZZ_INT"
aliases = ["int"]
type = "integer"

[flags.bool]
env = "F2E_FUZZ_BOOL"
aliases = ["bool"]
type = "bool"
dotenv_override = true

[flags.json]
env = "F2E_FUZZ_JSON"
aliases = ["json"]
type = "json"
TOML

set -- \
  -std=c99 \
  -O1 \
  -g \
  -fno-omit-frame-pointer \
  -fsanitize=fuzzer,address,undefined \
  -I"$ROOT_DIR/src" \
  "$ROOT_DIR/src/parser.c" \
  "$ROOT_DIR/tests/fuzz_parser.c" \
  -o "$WORK_DIR/fuzz-parser"

if [ -n "$FUZZ_SYSROOT" ]; then
  set -- -isysroot "$FUZZ_SYSROOT" "$@"
fi

"$FUZZ_CC" "$@"

set -- \
  -max_len=8192 \
  -timeout=10 \
  -verbosity=0 \
  -print_final_stats=1

if [ "$FUZZ_RUNS" -gt 0 ]; then
  set -- "$@" "-runs=$FUZZ_RUNS"
else
  set -- "$@" "-max_total_time=$FUZZ_SECONDS"
fi

ASAN_OPTIONS="${ASAN_OPTIONS:-$DEFAULT_ASAN_OPTIONS}" \
UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}" \
  "$WORK_DIR/fuzz-parser" "$@"
