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

native_library_path() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "$repo_root/build/libflags2env.dylib"
      ;;
    *)
      printf '%s\n' "$repo_root/build/libflags2env.so"
      ;;
  esac
}

build_declared_readme_path() {
  local command_name command_path command_dir
  local -a command_dirs=()
  local -a command_names=(
    ar
    bash
    cc
    cp
    dirname
    env
    gcc
    ld
    ln
    make
    mkdir
    node
    npm
    npx
    pkg-config
    readlink
    rm
    sed
    sh
    uname
  )
  command_names+=("$@")

  for command_name in "${command_names[@]}"; do
    command_path="$(command -v "$command_name")"
    command_dir="$(dirname "$command_path")"
    if [[ ! " ${command_dirs[*]} " =~ \ ${command_dir}\  ]]; then
      command_dirs+=("$command_dir")
    fi
  done

  local IFS=:
  printf '%s\n' "${command_dirs[*]}"
}

run_stage() {
  local stage="$1"

  printf '\n==> agent-check stage: %s\n' "$stage"
  case "$stage" in
    preflight)
      git diff --check
      nixfmt --check flake.nix .nix/dev-shell.nix
      shellcheck .nix/agent-check.sh
      shfmt -i 2 -ci -d .nix/agent-check.sh
      actionlint .github/workflows/nix.yml
      nix flake check --show-trace
      ;;
    dependencies)
      npm ci
      ;;
    build)
      make clean all
      ;;
    borrow)
      make borrow-check
      ;;
    readme-core)
      PATH="$(build_declared_readme_path)" ./scripts/test-readme-snippets.mjs
      ;;
    readme-python)
      env FLAGS2ENV_NATIVE_LIB="$(native_library_path)" PATH="$(build_declared_readme_path python3)" ./scripts/test-readme-snippets.mjs
      ;;
    readme-ruby)
      env FLAGS2ENV_NATIVE_LIB="$(native_library_path)" PATH="$(build_declared_readme_path ruby)" ./scripts/test-readme-snippets.mjs
      ;;
    readme)
      local readme_stage
      for readme_stage in readme-core readme-python readme-ruby; do
        run_stage "$readme_stage"
      done
      ;;
    parity)
      make parity-test
      ;;
    native-build)
      make build/process-smoke build/api-hardening build/allocation-failure
      ;;
    shell-tests)
      ./tests/run.sh
      ;;
    api-hardening)
      build/api-hardening
      ;;
    allocation-failure)
      build/allocation-failure tests/subcommands-deep/.cli-flags.toml
      ;;
    process-smoke)
      build/process-smoke --port 7777 -d
      ;;
    test)
      local test_stage
      for test_stage in borrow readme parity native-build shell-tests api-hardening allocation-failure process-smoke; do
        run_stage "$test_stage"
      done
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
  preflight | dependencies | build | borrow | readme-core | readme-python | readme-ruby | readme | parity | native-build | shell-tests | api-hardening | allocation-failure | process-smoke | test | package)
    run_stage "$1"
    ;;
  *)
    printf 'usage: %s [all|preflight|dependencies|build|borrow|readme-core|readme-python|readme-ruby|readme|parity|native-build|shell-tests|api-hardening|allocation-failure|process-smoke|test|package]\n' "$0" >&2
    exit 64
    ;;
esac
