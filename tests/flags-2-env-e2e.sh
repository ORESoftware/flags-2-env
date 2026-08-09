#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: tests/flags-2-env-e2e.sh /absolute/path/to/zed" >&2
  exit 2
fi

zed=$1
if [[ ! -x "$zed" ]]; then
  echo "zed executable not found: $zed" >&2
  exit 2
fi
zed="$(cd -- "$(dirname -- "$zed")" && pwd -P)/$(basename -- "$zed")"

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ ! -f "$repo_root/.zpkg.toml" ]]; then
  echo "could not locate the flags-2-env repository root" >&2
  exit 2
fi

read -r package_ref package_version < <(
  python3 - "$repo_root/.zpkg.toml" <<'PY_ZPKG'
import pathlib
import sys
import tomllib

package = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())["package"]
org = package["org"]
name = package["name"]
version = package["version"]
print(f"{org}/{name}@={version} {version}")
PY_ZPKG
)
if [[ -z "$package_ref" || -z "$package_version" ]]; then
  echo "could not derive the exact package coordinate from .zpkg.toml" >&2
  exit 2
fi

remove_suite_root=false
if [[ -n "${F2E_E2E_ROOT:-}" ]]; then
  suite_root=$F2E_E2E_ROOT
  if [[ -e "$suite_root" ]]; then
    echo "F2E_E2E_ROOT must not already exist: $suite_root" >&2
    exit 2
  fi
  mkdir -p "$suite_root"
else
  suite_root="$(mktemp -d "${TMPDIR:-/tmp}/flags-2-env-e2e.XXXXXX")"
  remove_suite_root=true
fi

cleanup() {
  if $remove_suite_root && [[ "${F2E_E2E_KEEP:-0}" != 1 ]]; then
    rm -rf -- "$suite_root"
  else
    printf 'flags2env E2E workspace: %s\n' "$suite_root"
  fi
}
trap cleanup EXIT

r2g_root="$suite_root/r2g"
author_home="$suite_root/author-home"
(
  cd "$repo_root"
  ZED_PKG_HOME="$author_home" "$zed" r2g --r2g-root "$r2g_root"
)

roundtrip="$r2g_root/oresoftware-flags-2-env"
registry="$roundtrip/registry"
if [[ ! -d "$registry" ]]; then
  echo "zed r2g did not create its file registry: $registry" >&2
  exit 1
fi

consumer_home="$suite_root/consumer-home"
registry_url="file://$registry"
projects="$suite_root/consumer projects"
mkdir -p "$projects"

write_layout() {
  local layout=$1
  local project=$2
  local invocation expected marker

  mkdir -p "$project"
  case "$layout" in
    npm)
      printf '{"name":"flags2env-npm-consumer","private":true}\n' > "$project/package.json"
      mkdir -p "$project/src/deep"
      invocation="$project/src/deep"
      expected="$project"
      marker="$project/package.json"
      ;;
    pnpm)
      printf 'packages:\n  - "packages/*"\n' > "$project/pnpm-workspace.yaml"
      mkdir -p "$project/packages/web/src"
      printf '{"name":"flags2env-pnpm-consumer","private":true,"packageManager":"pnpm@10"}\n' > "$project/packages/web/package.json"
      invocation="$project"
      expected="$project/packages/web"
      marker="$project/packages/web/package.json"
      ;;
    maven)
      printf '%s\n' \
        '<project xmlns="http://maven.apache.org/POM/4.0.0">' \
        '  <modelVersion>4.0.0</modelVersion>' \
        '  <groupId>example</groupId><artifactId>flags2env-consumer</artifactId><version>1</version>' \
        '</project>' > "$project/pom.xml"
      mkdir -p "$project/src/main/java"
      invocation="$project/src/main/java"
      expected="$project"
      marker="$project/pom.xml"
      ;;
    ruby)
      printf "source 'https://rubygems.org'\ngem 'rake'\n" > "$project/Gemfile"
      mkdir -p "$project/lib"
      invocation="$project/lib"
      expected="$project"
      marker="$project/Gemfile"
      ;;
    python-venv)
      printf '%s\n' \
        '[project]' \
        'name = "flags2env-consumer"' \
        'version = "0.0.0"' > "$project/pyproject.toml"
      mkdir -p "$project/.venv/bin"
      printf 'home = /usr/bin\ninclude-system-site-packages = false\nversion = 3\n' > "$project/.venv/pyvenv.cfg"
      invocation="$project/.venv/bin"
      expected="$project"
      marker="$project/pyproject.toml"
      ;;
    go-module)
      printf 'module example.com/flags2env-consumer\n\ngo 1.23\n' > "$project/go.mod"
      mkdir -p "$project/cmd/app"
      invocation="$project/cmd/app"
      expected="$project"
      marker="$project/go.mod"
      ;;
    standalone-jar)
      mkdir -p "$project/lib"
      printf 'standalone jar fixture\n' > "$project/lib/application.jar"
      invocation="$project"
      expected="$project"
      marker="$project/lib/application.jar"
      ;;
    bash)
      mkdir -p "$project/bin"
      printf '#!/usr/bin/env bash\nset -euo pipefail\n' > "$project/bin/run.sh"
      chmod +x "$project/bin/run.sh"
      invocation="$project"
      expected="$project"
      marker="$project/bin/run.sh"
      ;;
    *)
      echo "unknown E2E layout: $layout" >&2
      exit 2
      ;;
  esac

  F2E_LAYOUT_INVOCATION=$invocation
  F2E_LAYOUT_EXPECTED=$expected
  F2E_LAYOUT_MARKER=$marker
}

install_layout() {
  local layout=$1
  local mode=$2
  local project="$projects/$layout project"
  local invocation expected marker
  write_layout "$layout" "$project"
  invocation=$F2E_LAYOUT_INVOCATION
  expected=$F2E_LAYOUT_EXPECTED
  marker=$F2E_LAYOUT_MARKER

  local marker_before
  marker_before="$(cksum < "$marker")"
  printf '\n==> %s (%s install)\n' "$layout" "$mode"

  (
    cd "$invocation"
    ZED_PKG_HOME="$consumer_home" \
    ZED_PKG_REGISTRY="$registry_url" \
      "$zed" install "$package_ref" \
        --skip-manifest \
        --allow-build \
        --adapter none \
        --install-mode "$mode"
  )

  local modules="$expected/zed_modules"
  local target="$modules/oresoftware/flags-2-env"
  local bin="$modules/.bin/flags2env"
  local contract="$target/.cli-flags.toml"

  [[ "$(cksum < "$marker")" == "$marker_before" ]]
  [[ ! -e "$expected/.zpkg.toml" ]]
  [[ -f "$expected/.zpkg.lock" ]]
  [[ -x "$bin" ]]
  [[ -x "$target/build/flags2env" ]]
  [[ -f "$contract" ]]
  [[ -f "$target/clients/bash/flags2env.bash" ]]
  [[ -f "$target/clients/zsh/flags2env.zsh" ]]
  [[ -f "$target/scripts/verify-shell-contract.py" ]]
  [[ ! -e "$expected/node_modules" ]]
  [[ ! -e "$expected/.zed/classpath" ]]
  [[ ! -e "$expected/.zed/go.work" ]]
  [[ ! -e "$expected/.zed/pythonpath" ]]
  grep -Fq 'org = "oresoftware"' "$expected/.zpkg.lock"
  grep -Fq 'name = "flags-2-env"' "$expected/.zpkg.lock"
  grep -Fq "version = \"$package_version\"" "$expected/.zpkg.lock"

  if [[ "$mode" == symlink ]]; then
    [[ -L "$target" ]]
  else
    [[ ! -L "$target" ]]
  fi

  local audit
  audit="$(
    cd "$expected"
    ZED_PKG_HOME="$consumer_home" \
    ZED_PKG_REGISTRY="$registry_url" \
      "$zed" run flags2env -- audit "$contract"
  )"
  [[ "$audit" == *'"ok":true'* ]]

  local exports
  exports="$(
    cd "$expected"
    ZED_PKG_HOME="$consumer_home" \
    ZED_PKG_REGISTRY="$registry_url" \
      "$zed" run flags2env -- shell-env --config "$contract" -- --audit
  )"
  [[ "$exports" == *"export FLAGS2ENV_AUDIT='true'"* ]]

  (
    unset FLAGS2ENV_AUDIT
    export FLAGS2ENV_BIN="$target/build/flags2env"
    export FLAGS2ENV_CONFIG="$contract"
    # shellcheck source=/dev/null
    source "$target/clients/bash/flags2env.bash"
    flags2env_apply --audit
    [[ "$FLAGS2ENV_AUDIT" == true ]]
  )

  (
    unset FLAGS2ENV_AUDIT
    export FLAGS2ENV_BIN="$target/build/flags2env"
    export FLAGS2ENV_CONFIG="$contract"
    zsh -f -c '
      set -eu
      source "$1"
      flags2env_apply --audit
      [[ "$FLAGS2ENV_AUDIT" == true ]]
    ' zsh "$target/clients/zsh/flags2env.zsh"
  )

  if [[ "$layout" == npm ]]; then
    python3 "$target/scripts/verify-shell-contract.py" \
      --cli "$target/build/flags2env" \
      --contract "$contract" \
      --command flags2env \
      --install
  fi

  rm -rf -- "$modules"
  (
    cd "$expected"
    ZED_PKG_HOME="$consumer_home" \
    ZED_PKG_REGISTRY="$registry_url" \
      "$zed" install \
        --frozen \
        --skip-manifest \
        --allow-build \
        --adapter none \
        --install-mode "$mode"
  )
  [[ -x "$modules/.bin/flags2env" ]]
  [[ "$(cksum < "$marker")" == "$marker_before" ]]

  printf 'PASS: %s\n' "$layout"
}

install_layout npm symlink
install_layout pnpm copy
install_layout maven symlink
install_layout ruby copy
install_layout python-venv symlink
install_layout go-module copy
install_layout standalone-jar symlink
install_layout bash copy

printf '\nflags-2-env Zed multi-layout E2E: PASS (8 layouts)\n'
