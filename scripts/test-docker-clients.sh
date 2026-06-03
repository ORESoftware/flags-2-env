#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
  CLIENTS="$*"
else
  CLIENTS="c nodejs bun deno dart golang python ruby php rust swift erlang elixir gleam java"
fi

for client in $CLIENTS; do
  dockerfile="$ROOT_DIR/clients/$client/Dockerfile"
  if [ ! -f "$dockerfile" ]; then
    printf 'missing Dockerfile for client: %s\n' "$client" >&2
    exit 1
  fi

  image="flags2env-$client"
  printf '\n==> docker build %s\n' "$client"
  docker build -f "$dockerfile" -t "$image" "$ROOT_DIR"

  printf '\n==> docker run %s\n' "$client"
  docker run --rm "$image"
done
