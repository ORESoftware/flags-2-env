#!/usr/bin/env sh
set -eu

target=${1:-${ZED_PKG_TEST_TARGET:-}}
if [ -z "$target" ]; then
  echo "usage: verify-zed-package.sh <installed-package-root>" >&2
  exit 2
fi

cli="$target/build/flags2env"
contract="$target/.cli-flags.toml"
bash_helper="$target/clients/bash/flags2env.bash"
zsh_helper="$target/clients/zsh/flags2env.zsh"

test -x "$cli"
test -f "$contract"
test -f "$bash_helper"
test -f "$zsh_helper"

audit=$("$cli" audit "$contract")
case "$audit" in
  *'"ok":true'*'"errorCount":0'*) ;;
  *)
    printf 'unexpected installed-package audit:\n%s\n' "$audit" >&2
    exit 1
    ;;
esac

exports=$("$cli" shell-env --config "$contract" -- --audit)
case "$exports" in
  *"export FLAGS2ENV_AUDIT='true'"*) ;;
  *)
    printf 'unexpected installed-package exports:\n%s\n' "$exports" >&2
    exit 1
    ;;
esac

types=$("$cli" generate typescript "$contract" --name Flags2EnvZedSmoke)
case "$types" in
  *'export interface Flags2EnvZedSmoke'*'FLAGS2ENV_AUDIT?: boolean;'*) ;;
  *)
    printf 'unexpected installed-package generated types:\n%s\n' "$types" >&2
    exit 1
    ;;
esac

completion=$("$cli" completion bash flags2env "$contract")
case "$completion" in
  *'# flags2env bash completion'*'_flags2env_complete_flags2env()'*) ;;
  *)
    printf 'unexpected installed-package completion:\n%s\n' "$completion" >&2
    exit 1
    ;;
esac

printf 'flags2env Zed package smoke: PASS\n'
