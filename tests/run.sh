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
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --port x
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --port=x
run_case '{"PORT":"-1","DEBUG":"false","COLOR":"true"}' app --port -1
run_case '{"PORT":"+7","DEBUG":"false","COLOR":"true"}' app --port +7
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --no-port=8181
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
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app -- --help

actual="$(cd "$ROOT_DIR/tests/equals-only" && FLAGS2ENV_ALLOW_UNKNOWN=1 "$CLI" app --future value)"
expected="{\"PORT\":\"3000\",\"DEBUG\":\"false\",\"F2E_POSITIONALS\":\"[\\\"$CLI\\\",\\\"app\\\",\\\"value\\\"]\"}"
if [ "$actual" != "$expected" ]; then
  printf 'Expected env allow-unknown parse: %s\nActual:                           %s\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$(cd "$ROOT_DIR" && "$CLI" app --allow-unknown --future)"
expected='{"FLAGS2ENV_ALLOW_UNKNOWN":"true"}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected root allow-unknown parse: %s\nActual:                           %s\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$("$CLI" shell-env --config "$FIXTURE_DIR/.cli-flags.toml" -- app --debug=t --port 8181 --host "it's-local")"
for expected_export in "export PORT='8181'" "export DEBUG='true'" "export COLOR='true'" "export HOST='it'\\''s-local'"; do
  case "$actual" in
    *"$expected_export"*)
      ;;
    *)
      printf 'Unexpected shell env output; missing %s:\n%s\n' "$expected_export" "$actual" >&2
      exit 1
      ;;
  esac
done

FLAGS2ENV_BIN="$CLI" FLAGS2ENV_CONFIG="$FIXTURE_DIR/.cli-flags.toml" bash "$ROOT_DIR/clients/bash/test.bash"
if command -v zsh >/dev/null 2>&1; then
  FLAGS2ENV_BIN="$CLI" FLAGS2ENV_CONFIG="$FIXTURE_DIR/.cli-flags.toml" zsh "$ROOT_DIR/clients/zsh/test.zsh"
fi

wide_help="$(cd "$FIXTURE_DIR" && COLUMNS=132 "$CLI" app --help)"
case "$wide_help" in
  *'| Option(s)'*'| Env'*'| Type'*'| Default'*'| Description'*'TCP port for the app listener.'*'More help: https://example.com/flags2env/help'*)
    ;;
  *)
    printf 'Unexpected wide help table:\n%s\n' "$wide_help" >&2
    exit 1
    ;;
esac
case "$wide_help" in
  *'{"PORT"'*)
    printf 'Help should print a table, not JSON:\n%s\n' "$wide_help" >&2
    exit 1
    ;;
esac

narrow_help="$(cd "$FIXTURE_DIR" && COLUMNS=70 "$CLI" app --help)"
case "$narrow_help" in
  *'| Option(s)'*'| Details'*'env=PORT; type=integer; default=3000'*'More help: https://example.com/flags2env/help'*)
    ;;
  *)
    printf 'Unexpected narrow help table:\n%s\n' "$narrow_help" >&2
    exit 1
    ;;
esac
case "$narrow_help" in
  *'| Env'*|*'| Description'*)
    printf 'Narrow help should use fewer columns:\n%s\n' "$narrow_help" >&2
    exit 1
    ;;
esac

custom_help="$(cd "$ROOT_DIR/tests/table-options" && COLUMNS=132 "$CLI" app --help)"
case "$custom_help" in
  *'| Option(s)'*'| Description'*'TCP port for the app listener.'*)
    ;;
  *)
    printf 'Unexpected custom help table:\n%s\n' "$custom_help" >&2
    exit 1
    ;;
esac
case "$custom_help" in
  *'| Env'*|*'| Type'*|*'| Default'*)
    printf 'Custom help should omit unselected/excluded columns:\n%s\n' "$custom_help" >&2
    exit 1
    ;;
esac

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

NATIVE_SCALARS_DIR="$ROOT_DIR/tests/native-scalars"
actual="$(cd "$NATIVE_SCALARS_DIR" && "$CLI" app)"
expected='{"PORT":"3000","DEBUG":"false","PAYLOAD":"7"}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected native scalar defaults: %s\nActual:                          %s\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$(cd "$NATIVE_SCALARS_DIR" && "$CLI" app --debug 1 --payload true --port +12)"
expected='{"PORT":"+12","DEBUG":"true","PAYLOAD":"true"}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected native scalar overrides: %s\nActual:                           %s\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$("$CLI" audit env "$ROOT_DIR/tests/env-audit-clean/.cli-flags.toml" "$ROOT_DIR/tests/env-audit-clean/.env")"
expected='{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected clean env audit: %s\nActual:                   %s\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$("$CLI" audit env "$ROOT_DIR/tests/env-audit-ignore/.cli-flags.toml" "$ROOT_DIR/tests/env-audit-ignore/.env")"
expected='{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected ignored env audit: %s\nActual:                     %s\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$("$ROOT_DIR/scripts/audit-changed-cli-flags.sh" "tests/env-audit-ignore/.cli-flags.toml")"
case "$actual" in
  *'cli-flags audit: tests/env-audit-ignore/.cli-flags.toml'*'cli-flags env audit: tests/env-audit-ignore/.env'*'{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'*)
    ;;
  *)
    printf 'Expected changed-config helper to run ignored env audit:\n%s\n' "$actual" >&2
    exit 1
    ;;
esac

actual="$("$ROOT_DIR/scripts/audit-changed-cli-flags.sh" "tests/env-audit-ignore/.env")"
case "$actual" in
  *'cli-flags audit: tests/env-audit-ignore/.cli-flags.toml'*'cli-flags env audit: tests/env-audit-ignore/.env'*'{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'*)
    ;;
  *)
    printf 'Expected changed-env helper to run adjacent config audit:\n%s\n' "$actual" >&2
    exit 1
    ;;
esac

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

completion_zsh_path="$("$CLI" completion zsh /usr/local/bin/mycli/ "$FIXTURE_DIR/.cli-flags.toml")"
case "$completion_zsh_path" in
  *'#compdef mycli'*)
    ;;
  *)
    printf 'Zsh completion should use safe command basename:\n%s\n' "$completion_zsh_path" >&2
    exit 1
    ;;
esac

set +e
"$CLI" completion bash / "$FIXTURE_DIR/.cli-flags.toml" >/dev/null 2>/dev/null
status=$?
set -e
if [ "$status" -eq 0 ]; then
  printf 'Slash-only completion command name should fail\n' >&2
  exit 1
fi

set +e
"$CLI" completion bash 'bad;name' "$FIXTURE_DIR/.cli-flags.toml" >/dev/null 2>/dev/null
status=$?
set -e
if [ "$status" -eq 0 ]; then
  printf 'Unsafe completion command name should fail\n' >&2
  exit 1
fi

UNSAFE_CONFIG="$ROOT_DIR/tests/audit-unsafe-shell/.cli-flags.toml"
set +e
actual="$("$CLI" audit "$UNSAFE_CONFIG")"
status=$?
set -e
expected='{"ok":false,"errorCount":5,"warningCount":0,"errors":["flags.bad env \"BAD-NAME\" is not a valid env var name","flags.bad alias \"bad alias\" contains unsafe option characters","flags.bad has invalid short flag \";\"","flags.bad true_aliases contains unsafe shell token \"bad value\"","parse.positionals_env \"BAD-POSITIONALS\" is not a valid env var name"],"warnings":[]}'
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected unsafe config audit status and report:\n%s\nActual status: %s\nActual: %s\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

INVALID_ENV_ONLY_CONFIG="$ROOT_DIR/tests/audit-invalid-env-only/.cli-flags.toml"
set +e
actual="$("$CLI" audit "$INVALID_ENV_ONLY_CONFIG")"
status=$?
set -e
expected='{"ok":false,"errorCount":1,"warningCount":0,"errors":["flags.bad env \"BAD-NAME\" is not a valid env var name"],"warnings":[]}'
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected invalid env-only audit status and report:\n%s\nActual status: %s\nActual: %s\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

set +e
actual="$("$CLI" audit env "$INVALID_ENV_ONLY_CONFIG" "$ROOT_DIR/tests/env-audit/.env")"
status=$?
set -e
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected env audit to stop on invalid config:\n%s\nActual status: %s\nActual: %s\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

set +e
"$CLI" completion bash mycli "$INVALID_ENV_ONLY_CONFIG" >/dev/null 2>/dev/null
status=$?
set -e
if [ "$status" -eq 0 ]; then
  printf 'Invalid env-only config should not produce completion script\n' >&2
  exit 1
fi

INVALID_TYPE_CONFIG="$ROOT_DIR/tests/audit-invalid-type/.cli-flags.toml"
set +e
actual="$("$CLI" audit "$INVALID_TYPE_CONFIG")"
status=$?
set -e
expected='{"ok":false,"errorCount":1,"warningCount":0,"errors":["flags.port type \"integerer\" is not supported"],"warnings":[]}'
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected invalid type audit status and report:\n%s\nActual status: %s\nActual: %s\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

set +e
"$CLI" completion bash mycli "$UNSAFE_CONFIG" >/dev/null 2>/dev/null
status=$?
set -e
if [ "$status" -eq 0 ]; then
  printf 'Unsafe config should not produce completion script\n' >&2
  exit 1
fi

F2E_COMPLETION_DIR="$TMP_TEST_DIR/bash-completions" \
F2E_BASHRC="$TMP_TEST_DIR/bashrc" \
  "$CLI" completion install bash mycli "$FIXTURE_DIR/.cli-flags.toml" >/dev/null
F2E_COMPLETION_DIR="$TMP_TEST_DIR/bash-completions" \
F2E_BASHRC="$TMP_TEST_DIR/bashrc" \
  "$CLI" completion install bash mycli "$FIXTURE_DIR/.cli-flags.toml" >/dev/null
if [ ! -f "$TMP_TEST_DIR/bash-completions/mycli" ] ||
   ! grep -q '_flags2env_complete_mycli' "$TMP_TEST_DIR/bash-completions/mycli" ||
   ! grep -q 'flags2env completion: bash mycli' "$TMP_TEST_DIR/bashrc"; then
  printf 'Bash completion install did not write expected files under %s\n' "$TMP_TEST_DIR" >&2
  exit 1
fi
if [ "$(grep -c 'flags2env completion: bash mycli' "$TMP_TEST_DIR/bashrc")" -ne 1 ]; then
  printf 'Bash completion install should be idempotent under %s\n' "$TMP_TEST_DIR" >&2
  exit 1
fi

F2E_COMPLETION_DIR="$TMP_TEST_DIR/path-bash-completions" \
F2E_BASHRC="$TMP_TEST_DIR/path-bashrc" \
  "$CLI" completion install bash /usr/local/bin/mycli/ "$FIXTURE_DIR/.cli-flags.toml" >/dev/null
if [ ! -f "$TMP_TEST_DIR/path-bash-completions/mycli" ] ||
   ! grep -q "complete -o default -F _flags2env_complete_mycli -- 'mycli'" "$TMP_TEST_DIR/path-bash-completions/mycli" ||
   ! grep -q 'flags2env completion: bash mycli' "$TMP_TEST_DIR/path-bashrc"; then
  printf 'Bash completion install should use safe path basename under %s\n' "$TMP_TEST_DIR" >&2
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

printf 'flags2env tests passed\n'
