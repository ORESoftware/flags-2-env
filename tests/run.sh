#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLI="$ROOT_DIR/build/flags2env"
FIXTURE_DIR="$ROOT_DIR/tests/fixtures"
TMP_TEST_DIR="${TMPDIR:-/tmp}/flags2env-tests-$$"
rm -rf "$TMP_TEST_DIR"
mkdir -p "$TMP_TEST_DIR"
trap 'rm -rf "$TMP_TEST_DIR"' EXIT

run_case() {
  expected="$1"
  shift
  actual="$(cd "$FIXTURE_DIR" && "$CLI" "$@")"
  if [ "$actual" != "$expected" ]; then
    printf 'Expected: %s\nActual:   %s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

run_case '{"PORT":"8080","DEBUG":"true","COLOR":"true","HOST":"127.0.0.1","VERBOSE":"true","NODE_ENV":"production"}' app --port 8080 --debug --host 127.0.0.1 -v -mproduction
run_case '{"PORT":"9000","DEBUG":"false","COLOR":"false"}' app -p 9000 --no-color
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --unknown value positional
run_case '{"PORT":"8181","DEBUG":"true","COLOR":"true"}' app exec --port 8181 --debug
run_case '{"PORT":"3000","DEBUG":"true","COLOR":"true"}' app --port --debug
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --port --unknown
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true","HOST":"-internal"}' app --host=-internal
run_case '{"PORT":"4000","DEBUG":"true","COLOR":"true","VERBOSE":"true"}' app -dv --listen-port=4000
run_case '{"PORT":"3000","DEBUG":"true","COLOR":"true"}' app --debug=t
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --debug false
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --debug 0
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --debug=f
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app -d1 -d0
run_case '{"PORT":"3000","DEBUG":"true","COLOR":"true"}' app -d=1
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --color=0
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"false"}' app --color=false
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --debug=1 --debug=0
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --debug=t --debug=f
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --color=1
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app -v0
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app -- --port 9999 --debug

actual="$(cd "$ROOT_DIR" && "$CLI" app --config .cli-flags.toml --native-lib ./build/libflags2env.so --node-addon ./clients/nodejs/build/Release/flags2env.node --runtime nodejs --audit=t)"
expected='{"FLAGS2ENV_CONFIG":".cli-flags.toml","FLAGS2ENV_NATIVE_LIB":"./build/libflags2env.so","FLAGS2ENV_NODE_ADDON":"./clients/nodejs/build/Release/flags2env.node","FLAGS2ENV_RUNTIME":"nodejs","FLAGS2ENV_AUDIT":"true"}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected root config parse: %s\nActual:                     %s\n' "$expected" "$actual" >&2
  exit 1
fi

case "$actual" in
  *PORT*|*NODE_ENV*)
    printf 'Root config should not parse app env names: %s\n' "$actual" >&2
    exit 1
    ;;
esac

actual="$(cd "$ROOT_DIR" && "$CLI" audit)"
expected='{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected root config audit: %s\nActual:                     %s\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$(cd "$FIXTURE_DIR/nested/deeper" && "$CLI" audit)"
expected='{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected clean audit: %s\nActual:               %s\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$("$CLI" audit env "$ROOT_DIR/tests/env-audit-clean/.cli-flags.toml" "$ROOT_DIR/tests/env-audit-clean/.env")"
expected='{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected clean env audit: %s\nActual:                   %s\n' "$expected" "$actual" >&2
  exit 1
fi

set +e
actual="$("$CLI" audit env "$ROOT_DIR/tests/env-audit-drift/.cli-flags.toml" "$ROOT_DIR/tests/env-audit-drift/.env")"
status=$?
set -e
expected='{"ok":false,"errorCount":1,"warningCount":4,"errors":[".env key \"EXTRA\" is not declared by .cli-flags.toml"],"warnings":[".env key \"DEBUG\" appears more than once",".env line 5 has invalid key \"BAD-KEY\"",".cli-flags.toml env \"HOST\" is not present in .env",".cli-flags.toml env \"VERBOSE\" is not present in .env"]}'
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected failing env audit status and report:\n%s\nActual status: %s\nActual: %s\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

completion_bash="$("$CLI" completion bash mycli "$FIXTURE_DIR/.cli-flags.toml")"
case "$completion_bash" in
  *'_flags2env_complete_mycli()'*'--port --port= --listen-port --listen-port= -p'*'--no-debug'*'complete -o default -F _flags2env_complete_mycli -- '\''mycli'\'''*)
    ;;
  *)
    printf 'Unexpected bash completion script:\n%s\n' "$completion_bash" >&2
    exit 1
    ;;
esac

completion_zsh="$("$CLI" completion zsh mycli "$FIXTURE_DIR/.cli-flags.toml")"
case "$completion_zsh" in
  *'#compdef mycli'*'_arguments -s'*"'--port[PORT]:value:'"*"'--debug[DEBUG]::value:(true false t 1 f 0)'"*"'--no-debug[DEBUG]'"*)
    ;;
  *)
    printf 'Unexpected zsh completion script:\n%s\n' "$completion_zsh" >&2
    exit 1
    ;;
esac

F2E_COMPLETION_DIR="$TMP_TEST_DIR/bash-completions" \
F2E_BASHRC="$TMP_TEST_DIR/bashrc" \
  "$CLI" completion install bash mycli "$FIXTURE_DIR/.cli-flags.toml" >/dev/null
if [ ! -f "$TMP_TEST_DIR/bash-completions/mycli" ] ||
   ! grep -q '_flags2env_complete_mycli' "$TMP_TEST_DIR/bash-completions/mycli" ||
   ! grep -q 'flags2env completion: bash mycli' "$TMP_TEST_DIR/bashrc"; then
  printf 'Bash completion install did not write expected files under %s\n' "$TMP_TEST_DIR" >&2
  exit 1
fi

F2E_COMPLETION_DIR="$TMP_TEST_DIR/zsh-completions" \
F2E_ZSHRC="$TMP_TEST_DIR/zshrc" \
  "$CLI" completion install zsh mycli "$FIXTURE_DIR/.cli-flags.toml" >/dev/null
if [ ! -f "$TMP_TEST_DIR/zsh-completions/_mycli" ] ||
   ! grep -q '#compdef mycli' "$TMP_TEST_DIR/zsh-completions/_mycli" ||
   ! grep -q 'flags2env completion: zsh mycli' "$TMP_TEST_DIR/zshrc"; then
  printf 'Zsh completion install did not write expected files under %s\n' "$TMP_TEST_DIR" >&2
  exit 1
fi

INVALID_CONFIG="$ROOT_DIR/tests/audit-invalid/.cli-flags.toml"
set +e
actual="$("$CLI" audit "$INVALID_CONFIG")"
status=$?
set -e
expected='{"ok":false,"errorCount":6,"warningCount":1,"errors":["flags.debug true_aliases contains canonical false","flags.debug value alias \"t\" appears in both true_aliases and false_aliases","alias \"no-debug\" clashes with negated bool flag flags.debug","flags.debug and flags.trace both map to env \"DEBUG\"","flags.debug and flags.trace both use short flag \"d\"","flags.debug and flags.trace both use alias \"debug\""],"warnings":["flags.trace declares boolean value aliases but type is not bool"]}'
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected failing audit status and report:\n%s\nActual status: %s\nActual: %s\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

actual="$(cd "$FIXTURE_DIR/nested/deeper" && "$CLI" app --debug=t)"
expected='{"PORT":"3000","DEBUG":"true","COLOR":"true"}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected upward search: %s\nActual:                 %s\n' "$expected" "$actual" >&2
  exit 1
fi

HOME_FIXTURE="$ROOT_DIR/tests/home-with-config"
actual="$(cd "$HOME_FIXTURE" && HOME="$HOME_FIXTURE" "$CLI" app --bad)"
expected='{}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected HOME refusal: %s\nActual:                %s\n' "$expected" "$actual" >&2
  exit 1
fi

completion="$("$CLI" completion bash mycli "$FIXTURE_DIR/.cli-flags.toml")"
printf '%s\n' "$completion" | grep -F "complete -o default -F _flags2env_complete_mycli -- 'mycli'" >/dev/null ||
  { printf 'Bash completion missing command binding:\n%s\n' "$completion" >&2; exit 1; }
printf '%s\n' "$completion" | grep -F -- "--listen-port=" >/dev/null ||
  { printf 'Bash completion missing listen-port alias:\n%s\n' "$completion" >&2; exit 1; }
printf '%s\n' "$completion" | grep -F -- "--no-debug" >/dev/null ||
  { printf 'Bash completion missing negated bool:\n%s\n' "$completion" >&2; exit 1; }

completion="$("$CLI" completion zsh mycli "$FIXTURE_DIR/.cli-flags.toml")"
printf '%s\n' "$completion" | grep -F "#compdef mycli" >/dev/null ||
  { printf 'Zsh completion missing compdef:\n%s\n' "$completion" >&2; exit 1; }
printf '%s\n' "$completion" | grep -F -- "--port[PORT]:value:" >/dev/null ||
  { printf 'Zsh completion missing port spec:\n%s\n' "$completion" >&2; exit 1; }
printf '%s\n' "$completion" | grep -F -- "--no-debug[DEBUG]" >/dev/null ||
  { printf 'Zsh completion missing negated bool:\n%s\n' "$completion" >&2; exit 1; }

actual="$("$CLI" env-audit "$ROOT_DIR/tests/env-audit-clean/.cli-flags.toml")"
expected='{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected clean env audit: %s\nActual:                   %s\n' "$expected" "$actual" >&2
  exit 1
fi

set +e
actual="$("$CLI" env-audit "$ROOT_DIR/tests/env-audit/.cli-flags.toml" "$ROOT_DIR/tests/env-audit/.env")"
status=$?
set -e
expected='{"ok":false,"errorCount":1,"warningCount":3,"errors":[".env key \"FLAGS2ENV_EXTRA\" is not declared by .cli-flags.toml"],"warnings":[".env key \"FLAGS2ENV_DEBUG\" appears more than once",".env line 5 is not KEY=value",".cli-flags.toml env \"FLAGS2ENV_RUNTIME\" is not present in .env"]}'
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected failing env audit status and report:\n%s\nActual status: %s\nActual: %s\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

INSTALL_HOME="$(mktemp -d)"
trap 'rm -rf "$INSTALL_HOME"' EXIT
HOME="$INSTALL_HOME" \
F2E_BASH_COMPLETION_DIR="$INSTALL_HOME/bash-completions" \
F2E_BASHRC="$INSTALL_HOME/.bashrc" \
  "$CLI" install-completion bash mycli "$FIXTURE_DIR/.cli-flags.toml" >/dev/null

if [ ! -f "$INSTALL_HOME/bash-completions/mycli" ] ||
   ! grep -q "_flags2env_complete_mycli" "$INSTALL_HOME/bash-completions/mycli" ||
   ! grep -q "flags2env completion: bash mycli" "$INSTALL_HOME/.bashrc"; then
  printf 'Bash completion install did not write expected files under %s\n' "$INSTALL_HOME" >&2
  exit 1
fi

HOME="$INSTALL_HOME" \
F2E_ZSH_COMPLETION_DIR="$INSTALL_HOME/zfunc" \
F2E_ZSHRC="$INSTALL_HOME/.zshrc" \
  "$CLI" completion install zsh mycli "$FIXTURE_DIR/.cli-flags.toml" >/dev/null

if [ ! -f "$INSTALL_HOME/zfunc/_mycli" ] ||
   ! grep -q "#compdef mycli" "$INSTALL_HOME/zfunc/_mycli" ||
   ! grep -q "flags2env completion: zsh mycli" "$INSTALL_HOME/.zshrc"; then
  printf 'Zsh completion install did not write expected files under %s\n' "$INSTALL_HOME" >&2
  exit 1
fi

printf 'flags2env tests passed\n'
