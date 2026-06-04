#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
source "$ROOT_DIR/clients/zsh/flags2env.zsh"

FLAGS2ENV_BIN="${FLAGS2ENV_BIN:-$ROOT_DIR/build/flags2env}"
FLAGS2ENV_CONFIG="$ROOT_DIR/tests/fixtures/.cli-flags.toml"
export FLAGS2ENV_BIN FLAGS2ENV_CONFIG

flags2env_apply app --debug=t --port 8181 --host "it's-local"

[[ "${DEBUG:-}" == "true" ]]
[[ "${PORT:-}" == "8181" ]]
[[ "${HOST:-}" == "it's-local" ]]
[[ "${COLOR:-}" == "true" ]]

