#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DOCKERFILE="$ROOT_DIR/tests/codegen-docker/Dockerfile"

all_targets=(
  nodejs
  typescript
  bun
  deno
  golang
  rust
  dart
  java
  python
  csharp
  json-schema
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
    printf 'unknown codegen Docker target: %s\n' "$target" >&2
    printf 'available targets: %s\n' "${all_targets[*]}" >&2
    exit 2
  fi

  image="flags2env-codegen-${target//[^a-zA-Z0-9_.-]/-}"
  printf '\n==> building generated-code test: %s\n' "$target"
  docker build \
    --file "$DOCKERFILE" \
    --target "test-$target" \
    --tag "$image" \
    "$ROOT_DIR"

  printf '==> running generated-code test: %s\n' "$target"
  docker run --rm "$image"
done
