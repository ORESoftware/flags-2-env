#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FORMULA="$ROOT_DIR/packaging/homebrew/Formula/flags2env.rb"
FORMULA_NAME="${FLAGS2ENV_HOMEBREW_FORMULA:-flags2env}"
INSTALL_TARGET="${FLAGS2ENV_HOMEBREW_INSTALL_TARGET:-$FORMULA}"
TEST_TARGET="${FLAGS2ENV_HOMEBREW_TEST_TARGET:-$INSTALL_TARGET}"
AUDIT_TARGET="${FLAGS2ENV_HOMEBREW_AUDIT_TARGET:-$FORMULA_NAME}"
VERSION="${FLAGS2ENV_VERSION:-0.1.0}"
release=0

: "${HOMEBREW_CACHE:=${TMPDIR:-/tmp}/flags2env-homebrew-cache}"
export HOMEBREW_CACHE
mkdir -p "$HOMEBREW_CACHE"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release)
      release=1
      ;;
    --dry-run)
      release=0
      ;;
    *)
      printf 'usage: %s [--dry-run|--release]\n' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$release" -eq 1 ]; then
  if ! git -C "$ROOT_DIR" rev-parse "v$VERSION^{commit}" >/dev/null 2>&1; then
    printf 'homebrew release requires local git tag v%s\n' "$VERSION" >&2
    exit 1
  fi
  brew install --build-from-source "$INSTALL_TARGET"
  brew audit --strict --new --online "$AUDIT_TARGET"
  brew test "$TEST_TARGET"
else
  printf '[dry-run] homebrew: HOMEBREW_CACHE=%s\n' "$HOMEBREW_CACHE"
  printf '[dry-run] homebrew: brew install --build-from-source %s\n' "$INSTALL_TARGET"
  printf '[dry-run] homebrew: brew audit --strict --new --online %s\n' "$AUDIT_TARGET"
  printf '[dry-run] homebrew: brew test %s\n' "$TEST_TARGET"
fi
