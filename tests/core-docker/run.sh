#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DOCKERFILE="$ROOT_DIR/tests/core-docker/Dockerfile"

all_targets=(
  debian
  alpine
)

if (($# > 0)); then
  targets=("$@")
else
  targets=("${all_targets[@]}")
fi

is_known_target() {
  local requested="$1"
  local target
  for target in "${all_targets[@]}"; do
    if [[ "$requested" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

for target in "${targets[@]}"; do
  if ! is_known_target "$target"; then
    printf 'unknown core Docker target: %s\n' "$target" >&2
    printf 'available targets: %s\n' "${all_targets[*]}" >&2
    exit 2
  fi

  image="flags2env-core-${target//[^a-zA-Z0-9_.-]/-}"
  printf '\n==> building core test image: %s\n' "$target"
  docker build \
    --file "$DOCKERFILE" \
    --target "test-$target" \
    --tag "$image" \
    "$ROOT_DIR"

  printf '==> running core tests: %s\n' "$target"
  docker run --rm "$image"
done

printf '\ncore Docker tests passed\n'
