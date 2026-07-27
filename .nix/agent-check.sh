#!/usr/bin/env bash
set -euo pipefail

export CI="${CI:-1}"
export NO_COLOR="${NO_COLOR:-1}"
export CC="${CC:-gcc}"
export AR="${AR:-ar}"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

cache_root="${NIX_AGENT_CACHE_ROOT:-$repo_root/.cache/nix-agent}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$cache_root/xdg}"
export npm_config_cache="${npm_config_cache:-$cache_root/npm}"
export npm_config_build_from_source="${npm_config_build_from_source:-true}"
node_prefix="$(dirname "$(dirname "$(readlink -f "$(command -v node)")")")"
export npm_config_nodedir="${npm_config_nodedir:-$node_prefix}"
mkdir -p "$XDG_CACHE_HOME" "$npm_config_cache"

git diff --check
nixfmt --check flake.nix .nix/dev-shell.nix
shellcheck .nix/agent-check.sh
shfmt -d .nix/agent-check.sh
actionlint .github/workflows/nix.yml
nix flake check --show-trace

npm ci
make clean all
make test
npm run pack:audit
npm run pack:dry-run
npm run release:audit
