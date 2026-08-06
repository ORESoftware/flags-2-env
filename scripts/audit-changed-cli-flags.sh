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

files="$(changed_files "$@" | awk '
  /(^|\/)\.cli-flags\.toml$/ {
    print
    next
  }
  $0 == ".env" {
    print ".cli-flags.toml"
    next
  }
  /\/\.env$/ {
    file = $0
    sub(/\/\.env$/, "/.cli-flags.toml", file)
    print file
  }
' | sort -u)"
if [ -z "$files" ]; then
  printf 'cli-flags audit: no changed .cli-flags.toml files\n'
  exit 0
fi

status=0

while IFS= read -r file; do
  case "$file" in
    tests/audit-invalid*/.cli-flags.toml | \
    tests/audit-unsafe-shell/.cli-flags.toml | \
    tests/env-audit-drift/.cli-flags.toml)
      printf 'cli-flags audit: skipping expected-negative fixture %s\n' "$file"
      continue
      ;;
  esac

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
    status=1
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      printf '::error file=%s::flags2env config audit failed\n' "$file"
    fi
  fi

  env_path="$(dirname -- "$path")/.env"
  case "$file" in
    .cli-flags.toml) env_file=".env" ;;
    */.cli-flags.toml) env_file="${file%/.cli-flags.toml}/.env" ;;
    *) env_file="$(dirname -- "$file")/.env" ;;
  esac
  if [ ! -f "$env_path" ]; then
    printf 'cli-flags env audit: no adjacent .env for %s\n' "$file"
    continue
  fi

  printf 'cli-flags env audit: %s\n' "$env_file"
  set +e
  env_report="$("$CLI" audit env "$path" "$env_path")"
  env_audit_status=$?
  set -e
  printf '%s\n' "$env_report"

  if [ "$env_audit_status" -ne 0 ]; then
    status=1
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      printf '::error file=%s::flags2env env audit failed\n' "$env_file"
    fi
  fi
done <<EOF
$files
EOF

exit "$status"
