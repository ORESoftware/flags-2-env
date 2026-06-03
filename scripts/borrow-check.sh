#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLANG="${CLANG:-clang}"

if ! command -v "$CLANG" >/dev/null 2>&1; then
  printf 'borrow-check requires clang on PATH\n' >&2
  exit 1
fi

COMMON_FLAGS="-std=c99 -Wall -Wextra -Wpedantic -Werror -I$ROOT_DIR -I$ROOT_DIR/src"
ANALYZE_FLAGS="--analyze -Xanalyzer -analyzer-output=text"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_clang_analyzer() {
  out_file="$1"
  shift
  set +e
  # shellcheck disable=SC2086
  "$CLANG" $ANALYZE_FLAGS $COMMON_FLAGS "$@" >"$out_file" 2>&1
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    cat "$out_file" >&2
    return "$status"
  fi
  return 0
}

analyze() {
  label="$1"
  shift
  printf 'borrow-check: %s\n' "$label"
  out_file="$TMP_DIR/$(printf '%s' "$label" | tr '/ ' '__').out"
  run_clang_analyzer "$out_file" "$@"
  if grep -Eq '(^|: )[0-9]+:[0-9]+: (warning|error):' "$out_file"; then
    cat "$out_file" >&2
    exit 1
  fi
}

expect_analyzer_warning() {
  label="$1"
  pattern="$2"
  shift 2
  printf 'borrow-check: fixture %s\n' "$label"
  out_file="$TMP_DIR/fixture_$(printf '%s' "$label" | tr '/ ' '__').out"
  run_clang_analyzer "$out_file" "$@"
  if ! grep -Eq "$pattern" "$out_file"; then
    printf 'Expected analyzer warning matching /%s/ for %s\n' "$pattern" "$label" >&2
    cat "$out_file" >&2
    exit 1
  fi
}

cat >"$TMP_DIR/good.c" <<'EOF'
#include "src/parser.h"

int main(void) {
  const char *argv[] = {"app", "--help"};
  char *json = f2e_parse(2, argv);
  if (!json) {
    return 1;
  }
  f2e_free(json);
  return 0;
}
EOF

cat >"$TMP_DIR/leak.c" <<'EOF'
#include "src/parser.h"

int main(void) {
  const char *argv[] = {"app", "--help"};
  char *json = f2e_parse(2, argv);
  return json != 0;
}
EOF

cat >"$TMP_DIR/double_free.c" <<'EOF'
#include "src/parser.h"

int main(void) {
  const char *argv[] = {"app", "--help"};
  char *json = f2e_parse(2, argv);
  if (!json) {
    return 1;
  }
  f2e_free(json);
  f2e_free(json);
  return 0;
}
EOF

analyze "src/parser.c" "$ROOT_DIR/src/parser.c"
analyze "src/main.c" "$ROOT_DIR/src/main.c"
analyze "clients/c/lib.c" -I"$ROOT_DIR/clients/c" "$ROOT_DIR/clients/c/lib.c"
analyze "clients/c/test.c" -I"$ROOT_DIR/clients/c" "$ROOT_DIR/clients/c/test.c"
analyze "ownership fixture good" "$TMP_DIR/good.c"
expect_analyzer_warning "ownership fixture leak" 'Potential leak|leak of memory' "$TMP_DIR/leak.c"
expect_analyzer_warning "ownership fixture double free" 'Attempt to free released memory|Use of memory after it is freed|double free' "$TMP_DIR/double_free.c"

if command -v node >/dev/null 2>&1; then
  NODE_INCLUDE="$(node -p 'process.env.npm_config_nodedir ? `${process.env.npm_config_nodedir}/include/node` : ""' 2>/dev/null || true)"
  if [ -z "$NODE_INCLUDE" ]; then
    NODE_INCLUDE="$(find "$HOME/Library/Caches/node-gyp" "$HOME/.cache/node-gyp" -path '*/include/node/node_api.h' -print 2>/dev/null | head -n 1 | sed 's#/node_api.h$##')"
  fi
  if [ -n "$NODE_INCLUDE" ] && [ -f "$NODE_INCLUDE/node_api.h" ]; then
    analyze "clients/nodejs/addon.c" -I"$NODE_INCLUDE" "$ROOT_DIR/clients/nodejs/addon.c"
  else
    printf 'borrow-check: skipping clients/nodejs/addon.c; node_api.h not found\n'
  fi
fi

if command -v erl >/dev/null 2>&1; then
  ERL_INCLUDE="$(erl -noshell -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)]), halt().' 2>/dev/null || true)"
  if [ -n "$ERL_INCLUDE" ] && [ -f "$ERL_INCLUDE/erl_nif.h" ]; then
    analyze "clients/erlang/flags2env_nif.c" -I"$ERL_INCLUDE" "$ROOT_DIR/clients/erlang/flags2env_nif.c"
  else
    printf 'borrow-check: skipping clients/erlang/flags2env_nif.c; erl_nif.h not found\n'
  fi
fi

if [ -z "${JAVA_HOME:-}" ] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
  JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null || true)"
fi
if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/include/jni.h" ]; then
  JNI_OS_INCLUDE="$JAVA_HOME/include/linux"
  if [ "$(uname -s)" = "Darwin" ]; then
    JNI_OS_INCLUDE="$JAVA_HOME/include/darwin"
  fi
  if [ -d "$JNI_OS_INCLUDE" ]; then
    analyze "clients/java/native/flags2env_jni.c" -I"$JAVA_HOME/include" -I"$JNI_OS_INCLUDE" "$ROOT_DIR/clients/java/native/flags2env_jni.c"
  fi
else
  printf 'borrow-check: skipping clients/java/native/flags2env_jni.c; jni.h not found\n'
fi
