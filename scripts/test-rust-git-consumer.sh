#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
repo_sha="$(git -C "$repo_root" rev-parse HEAD)"
consumer_parent="$(mktemp -d "${TMPDIR:-/tmp}/flags2env-git-consumer.XXXXXX")"
consumer_root="$consumer_parent/consumer"

cp -R "$repo_root/tests/fixtures/rust-git-consumer" "$consumer_root"
cargo add \
  --manifest-path "$consumer_root/Cargo.toml" \
  flags2env \
  --git "file://$repo_root" \
  --rev "$repo_sha"
cargo run --manifest-path "$consumer_root/Cargo.toml" --locked

