#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLI="$ROOT_DIR/build/flags2env"

if [ ! -x "$CLI" ]; then
  make -C "$ROOT_DIR" cli
fi

changed_files() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
    return
  fi

  base="${BASE_SHA:-}"
  head="${HEAD_SHA:-HEAD}"

  if [ -n "$base" ] && git -C "$ROOT_DIR" cat-file -e "$base^{commit}" 2>/dev/null; then
    git -C "$ROOT_DIR" diff --name-only "$base" "$head"
    return
  fi

  if git -C "$ROOT_DIR" rev-parse HEAD^ >/dev/null 2>&1; then
    git -C "$ROOT_DIR" diff --name-only HEAD^ "$head"
    return
  fi

  git -C "$ROOT_DIR" ls-files
}

files="$(changed_files "$@" | awk '/(^|\/)\.cli-flags\.toml$/')"
if [ -z "$files" ]; then
  printf 'cli-flags audit: no changed .cli-flags.toml files\n'
  exit 0
fi

status_file="$(mktemp)"
printf '0\n' >"$status_file"

printf '%s\n' "$files" | while IFS= read -r file; do
  case "$file" in
    /*) path="$file" ;;
    *) path="$ROOT_DIR/$file" ;;
  esac

  if [ ! -f "$path" ]; then
    printf 'cli-flags audit: skipping removed file %s\n' "$file"
    continue
  fi

  printf 'cli-flags audit: %s\n' "$file"
  set +e
  report="$("$CLI" audit "$path")"
  audit_status=$?
  set -e
  printf '%s\n' "$report"

  if [ "$audit_status" -ne 0 ]; then
    printf '1\n' >"$status_file"
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      printf '::error file=%s::flags2env config audit failed\n' "$file"
    fi
  fi
done

status="$(cat "$status_file")"
rm -f "$status_file"
exit "$status"
