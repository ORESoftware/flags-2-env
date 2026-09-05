#!/usr/bin/env bash
# Simulates readline completion against the generated bash scripts by driving
# COMP_WORDS/COMP_CWORD directly and asserting COMPREPLY.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
CLI="${FLAGS2ENV_BIN:-$ROOT_DIR/build/flags2env}"

fail() {
  printf 'completion test failed: %s\n' "$1" >&2
  exit 1
}

if ! type complete >/dev/null 2>&1 || ! type compgen >/dev/null 2>&1; then
  fail 'Bash programmable-completion builtins complete and compgen are required'
fi

load_completion() {
  # shellcheck disable=SC1090
  source /dev/stdin <<<"$("$CLI" completion bash "$1" "$2")"
}

# complete_words <function> <words...> — last word is the one being completed
run_complete() {
  local fn="$1"
  shift
  COMP_WORDS=("$@")
  COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
  COMPREPLY=()
  "$fn" || true
  printf '%s\n' "${COMPREPLY[@]-}"
}

expect_contains() {
  local label="$1" haystack="$2" needle="$3"
  case " $haystack " in
    *" $needle "*) ;;
    *) fail "$label: expected '$needle' in: $haystack" ;;
  esac
}

expect_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  case " $haystack " in
    *" $needle "*) fail "$label: did not expect '$needle' in: $haystack" ;;
    *) ;;
  esac
}

load_completion gitish "$ROOT_DIR/tests/subcommands/.cli-flags.toml"

# top level: command names are offered for a bare word
reply="$(run_complete _flags2env_complete_gitish gitish '' | tr '\n' ' ')"
expect_contains 'top-level commands' "$reply" 'add'
expect_contains 'top-level commands' "$reply" 'commit'
expect_contains 'top-level commands' "$reply" 'ci'
expect_contains 'top-level commands' "$reply" 'remote'

# top level: only global options are offered for a dash word
reply="$(run_complete _flags2env_complete_gitish gitish '--' | tr '\n' ' ')"
expect_contains 'top-level options' "$reply" '--verbose'
expect_contains 'top-level options' "$reply" '--author'
expect_contains 'top-level options' "$reply" '--color'
expect_not_contains 'top-level options' "$reply" '--fetch'
expect_not_contains 'top-level options' "$reply" '--chmod'

# inside a subcommand: its options plus inherited globals, not siblings'
reply="$(run_complete _flags2env_complete_gitish gitish add '--' | tr '\n' ' ')"
expect_contains 'add options' "$reply" '--all'
expect_contains 'add options' "$reply" '--chmod'
expect_contains 'add options' "$reply" '--verbose'
expect_not_contains 'add options' "$reply" '--message'
expect_not_contains 'add options' "$reply" '--fetch'

# command aliases resolve scopes too
reply="$(run_complete _flags2env_complete_gitish gitish ci '--' | tr '\n' ' ')"
expect_contains 'commit alias options' "$reply" '--message'
expect_not_contains 'commit alias options' "$reply" '--chmod'

# nested scope: `gitish remote <TAB>` offers its subcommands
reply="$(run_complete _flags2env_complete_gitish gitish remote '' | tr '\n' ' ')"
expect_contains 'remote subcommands' "$reply" 'add'
expect_not_contains 'remote subcommands' "$reply" 'commit'

# nested scope options
reply="$(run_complete _flags2env_complete_gitish gitish remote add '--' | tr '\n' ' ')"
expect_contains 'remote add options' "$reply" '--fetch'
expect_contains 'remote add options' "$reply" '--track'
expect_contains 'remote add options' "$reply" '--author'
expect_not_contains 'remote add options' "$reply" '--all'

# bool value completion still works per scope
reply="$(run_complete _flags2env_complete_gitish gitish remote add --fetch '' | tr '\n' ' ')"
expect_contains 'bool values' "$reply" 'true'
expect_contains 'bool values' "$reply" 'false'

# after an operand, commands are no longer offered
reply="$(run_complete _flags2env_complete_gitish gitish add somefile.txt '' | tr '\n' ' ')"
expect_not_contains 'post-operand words' "$reply" 'commit'

# after --, nothing is suggested (falls through to file completion)
reply="$(run_complete _flags2env_complete_gitish gitish add -- '' | tr '\n' ' ')"
if [ -n "${reply// /}" ]; then
  fail "post--- words: expected empty COMPREPLY, got: $reply"
fi

# deep fixture: four-level scope resolution
load_completion tool "$ROOT_DIR/tests/subcommands-deep/.cli-flags.toml"
reply="$(run_complete _flags2env_complete_tool tool ws remote add tag '--' | tr '\n' ' ')"
expect_contains 'deep scope options' "$reply" '--name'
expect_contains 'deep scope options' "$reply" '--dry-run'
reply="$(run_complete _flags2env_complete_tool tool ws remote add '' | tr '\n' ' ')"
expect_contains 'deep scope subcommands' "$reply" 'tag'
expect_contains 'deep scope subcommand aliases' "$reply" 'annotate'

# Every alias maps to the canonical nested scope.
reply="$(run_complete _flags2env_complete_tool tool workspace remotes create annotate '--' | tr '\n' ' ')"
expect_contains 'deep alias scope options' "$reply" '--name'
expect_contains 'deep alias scope options' "$reply" '--dry-run'

# A separated option value may equal either a command name or command alias;
# completion must consume it as a value rather than entering that command.
reply="$(run_complete _flags2env_complete_tool tool --label ws '' | tr '\n' ' ')"
expect_contains 'canonical command-looking value keeps root scope' "$reply" 'ws'
expect_contains 'canonical command-looking value keeps root aliases' "$reply" 'workspace'
expect_not_contains 'canonical command-looking value keeps root scope' "$reply" 'remote'
reply="$(run_complete _flags2env_complete_tool tool -l workspace '' | tr '\n' ' ')"
expect_contains 'alias-looking short-option value keeps root scope' "$reply" 'ws'
expect_not_contains 'alias-looking short-option value keeps root scope' "$reply" 'remotes'

# The same rule has to survive the getopt spelling: `-nl workspace` is `-n`
# bundled with `-l`, so `workspace` is -l's value, not a command. Matching only
# whole option words let the bundle's value walk completion into that scope,
# while the parser stayed in root - completion and parse disagreeing about the
# same argv.
reply="$(run_complete _flags2env_complete_tool tool -nl workspace '' | tr '\n' ' ')"
expect_contains 'bundled short-option value keeps root scope' "$reply" 'ws'
expect_contains 'bundled short-option value keeps root scope' "$reply" 'workspace'
expect_not_contains 'bundled short-option value keeps root scope' "$reply" 'remote'
expect_not_contains 'bundled short-option value keeps root scope' "$reply" 'remotes'
# A lone bool short still consumes a following bool word, so the word after it
# is a command again.
reply="$(run_complete _flags2env_complete_tool tool -n workspace '' | tr '\n' ' ')"
expect_contains 'lone bool short enters the value scope' "$reply" 'remote'
# ...and once the bundle's value flag has an inline value it consumes nothing.
reply="$(run_complete _flags2env_complete_tool tool -nlx workspace '' | tr '\n' ' ')"
expect_contains 'inline bundle value leaves the command free' "$reply" 'remote'
# A character that is not a declared short makes the token no bundle at all,
# so it owns nothing that follows.
reply="$(run_complete _flags2env_complete_tool tool -nq workspace '' | tr '\n' ' ')"
expect_contains 'unbundleable token consumes nothing' "$reply" 'remote'

# The same rule applies inside nested scopes.
reply="$(run_complete _flags2env_complete_tool tool ws remote add --url tag '--' | tr '\n' ' ')"
expect_contains 'nested canonical command-looking value stays in add' "$reply" '--url'
expect_not_contains 'nested canonical command-looking value stays in add' "$reply" '--name'
reply="$(run_complete _flags2env_complete_tool tool workspace remotes create -u annotate '--' | tr '\n' ' ')"
expect_contains 'nested alias-looking value stays in add' "$reply" '--url'
expect_not_contains 'nested alias-looking value stays in add' "$reply" '--name'

# Invalid separated bool values remain eligible as commands; only recognized
# bool values are consumed by completion.
reply="$(run_complete _flags2env_complete_tool tool --dry-run workspace '' | tr '\n' ' ')"
expect_contains 'invalid bool value remains a command alias' "$reply" 'remote'
expect_contains 'invalid bool value remains a command alias' "$reply" 'remotes'

# A half-typed bundle used to complete to nothing at all, so the one feature
# whose whole point is that fingers already know it was the one feature
# completion could not teach. Continuations come from the active scope.
reply="$(run_complete _flags2env_complete_gitish gitish commit -av | tr '\n' ' ')"
expect_contains 'bundle continues with a scoped value short' "$reply" '-avm'
expect_not_contains 'bundle never repeats a character it already has' "$reply" '-ava'
expect_not_contains 'bundle never repeats a character it already has' "$reply" '-avv'
# A value-taking short closes the bundle: everything after it is its value.
reply="$(run_complete _flags2env_complete_gitish gitish commit -am | tr '\n' ' ')"
expect_not_contains 'a closed bundle offers no continuation' "$reply" '-amv'
# Scope still governs: a short belonging only to a sibling command is not
# offered, exactly as its long spelling is not.
reply="$(run_complete _flags2env_complete_gitish gitish commit -av | tr '\n' ' ')"
expect_not_contains 'sibling-command short does not leak into the bundle' "$reply" '-avf'

# flat configs (no commands) keep working through the same entry point
load_completion app "$ROOT_DIR/tests/fixtures/.cli-flags.toml"
reply="$(run_complete _flags2env_complete_app app '--' | tr '\n' ' ')"
expect_contains 'flat options' "$reply" '--port'
expect_contains 'flat options' "$reply" '--debug'

# The same continuations on a flat config...
reply="$(run_complete _flags2env_complete_app app -dv | tr '\n' ' ')"
expect_contains 'flat bundle continues with a bool short' "$reply" '-dvc'
expect_contains 'flat bundle continues with a value short' "$reply" '-dvp'
expect_not_contains 'flat bundle never repeats a character' "$reply" '-dvd'
expect_not_contains 'flat bundle offers no undeclared character' "$reply" '-dvz'
# ...and nothing once a value-taking short has closed it.
reply="$(run_complete _flags2env_complete_app app -dvp | tr '\n' ' ')"
expect_not_contains 'closed flat bundle offers no continuation' "$reply" '-dvpc'
# A lone short is left exactly as it was: one match, which readline completes
# outright. Fanning it out into every pair it could start would be a
# regression dressed up as a feature.
reply="$(run_complete _flags2env_complete_app app -d | tr '\n' ' ')"
expect_contains 'lone short still completes to itself' "$reply" '-d'
expect_not_contains 'lone short does not fan out' "$reply" '-dv'

printf 'bash completion tests passed\n'
