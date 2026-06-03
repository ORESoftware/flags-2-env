#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLI="$ROOT_DIR/build/flags2env"
FIXTURE_DIR="$ROOT_DIR/tests/fixtures"

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
run_case '{"PORT":"4000","DEBUG":"true","COLOR":"true","VERBOSE":"true"}' app -dv --listen-port=4000
run_case '{"PORT":"3000","DEBUG":"true","COLOR":"true"}' app --debug=t
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --debug false
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --debug 0
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --debug=f
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app -d1 -d0
run_case '{"PORT":"3000","DEBUG":"true","COLOR":"true"}' app -d=1
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"true"}' app --color=0
run_case '{"PORT":"3000","DEBUG":"false","COLOR":"false"}' app --color=false

actual="$(cd "$FIXTURE_DIR/nested/deeper" && "$CLI" audit)"
expected='{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected clean audit: %s\nActual:               %s\n' "$expected" "$actual" >&2
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
