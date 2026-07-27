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

run_stage() {
  local stage="$1"

  printf '\n==> agent-check stage: %s\n' "$stage"
  case "$stage" in
    preflight)
      git diff --check
      nixfmt --check flake.nix .nix/dev-shell.nix
      shellcheck .nix/agent-check.sh
      shfmt -i 2 -d .nix/agent-check.sh
      actionlint .github/workflows/nix.yml
      nix flake check --show-trace
      ;;
    dependencies)
      npm ci
      ;;
    build)
      make clean all
      ;;
    test)
      make test
      ;;
    package)
      npm run pack:audit
      npm run pack:dry-run
      npm run release:audit
      ;;
    *)
      printf 'unknown agent-check stage: %s\n' "$stage" >&2
      return 64
      ;;
  esac
}

case "${1:-all}" in
  all)
    for stage in preflight dependencies build test package; do
      run_stage "$stage"
    done
    ;;
  preflight | dependencies | build | test | package)
    run_stage "$1"
    ;;
  *)
    printf 'usage: %s [all|preflight|dependencies|build|test|package]\n' "$0" >&2
    exit 64
    ;;
esac
