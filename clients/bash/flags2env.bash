# shellcheck shell=bash

flags2env_shell() {
  local flags2env_bin="${FLAGS2ENV_BIN:-flags2env}"
  if [ -n "${FLAGS2ENV_CONFIG:-}" ]; then
    "$flags2env_bin" shell-env --config "$FLAGS2ENV_CONFIG" -- "$@"
  else
    "$flags2env_bin" shell-env -- "$@"
  fi
}

flags2env_apply() {
  local flags2env_exports
  if ! flags2env_exports="$(flags2env_shell "$@")"; then
    return $?
  fi
  eval "$flags2env_exports"
}

f2e_apply() {
  flags2env_apply "$@"
}

