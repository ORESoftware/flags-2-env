#!/usr/bin/env bash
# DEN-2846: pinned build harness for target-qualified prebuilt artifacts.
#
# Produces, per canonical triple (prebuilt/targets.json is the authority):
#   $OUT/<triple>/libflags2env.a                     static
#   $OUT/<triple>/libflags2env.{so|dylib}            shared (unsigned by default)
#   $OUT/<triple>/<artifact>.symbols.txt             normalized exported-symbol list
#   $OUT/<triple>/<artifact>.buildinfo.json          toolchain provenance seam for DEN-2847
#
# Linux GNU/musl targets build with the PINNED Zig toolchain; Darwin targets
# build with the PINNED native Apple clang + SDK (scripts/prebuilt/toolchains.json;
# fail-closed on drift). Reproducibility contract (ADR 0001): two clean builds
# produce identical unsigned bytes — `verify` proves it. Darwin ad-hoc signing
# (F2E_SIGN=adhoc) runs only after unsigned comparison, per the ADR.
#
# Outputs stay OUT of prebuilt/ — committing certified artifacts (and the atomic
# build/ removal) is the DEN-2848 slice. Default OUT is build/prebuilt-staging
# (gitignored).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PIN="$REPO/scripts/prebuilt/toolchains.json"
TARGETS_JSON="$REPO/prebuilt/targets.json"
OUT="${PREBUILT_OUT:-$REPO/build/prebuilt-staging}"
SRC=("$REPO/src/parser.c" "$REPO/src/terminal_context.c")
SDE="${SOURCE_DATE_EPOCH:-$(git -C "$REPO" log -1 --format=%ct 2>/dev/null || echo 0)}"
export SOURCE_DATE_EPOCH="$SDE"

# -g0: release prebuilts carry no debug info (zig cc embeds it by default and
# pushes the linux static archives against the 1 MiB per-file budget).
CFLAGS_COMMON=(-std=c99 -Wall -Wextra -Wpedantic -O2 -g0 -fPIC "-ffile-prefix-map=$REPO=.")

# What gets RECORDED in buildinfo/manifest. `-ffile-prefix-map` necessarily
# contains the absolute checkout path; recording it verbatim would make the
# manifest differ per machine and would publish a local filesystem path. The
# binaries are unaffected (the flag maps that prefix to "." inside them), so the
# recorded form is normalized to a placeholder.
CFLAGS_RECORDED=("${CFLAGS_COMMON[@]/-ffile-prefix-map=$REPO=./-ffile-prefix-map=<source-root>=.}")

jq_py() { python3 -c "import json,sys; $1" "${@:2}"; }

pin() { jq_py "d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$PIN" "$1"; }

tier1_triples() {
  jq_py "d=json.load(open(sys.argv[1]));
print('\n'.join(t['triple'] for t in d['targets'] if t['tier']==1))" "$TARGETS_JSON"
}

runtime_floor() {
  # Fails with a clear diagnostic rather than a StopIteration traceback when the
  # `prebuilt-%` pattern rule forwards a name that is not a declared triple
  # (e.g. `make prebuilt-typo`).
  jq_py "d=json.load(open(sys.argv[1]))
m=[t for t in d['targets'] if t['triple']==sys.argv[2]]
if not m:
    sys.stderr.write('FATAL: %r is not a target in prebuilt/targets.json; known: %s\n' % (
        sys.argv[2], ', '.join(t['triple'] for t in d['targets'])))
    raise SystemExit(2)
print(m[0]['minimum_runtime'])" "$TARGETS_JSON" "$1"
}

check_toolchains() {
  local need_zig=$1 need_darwin=$2
  if [ "$need_zig" = yes ]; then
    local want have
    want=$(pin "d['zig']['version']")
    have=$(zig version)
    [ "$have" = "$want" ] || { echo "FATAL: zig $have != pinned $want (update scripts/prebuilt/toolchains.json via PR)"; exit 2; }
  fi
  if [ "$need_darwin" = yes ]; then
    local want_cc want_sdk have_cc have_sdk
    want_cc=$(pin "d['darwin']['compiler_id']")
    want_sdk=$(pin "d['darwin']['sdk_version']")
    have_cc=$(clang --version | head -1)
    have_sdk=$(xcrun --sdk macosx --show-sdk-version)
    case "$have_cc" in "$want_cc"*) ;; *) echo "FATAL: '$have_cc' != pinned '$want_cc*'"; exit 2;; esac
    [ "$have_sdk" = "$want_sdk" ] || { echo "FATAL: macOS SDK $have_sdk != pinned $want_sdk"; exit 2; }
  fi
}

# llvm-ar (via `zig ar`) writes deterministic archives by default.
make_archive() { # out.a objects...
  local out=$1; shift
  zig ar rcs "$out" "$@"
}

emit_symbols() { # artifact -> artifact.symbols.txt
  # Normalized exported-symbol set: every defined global (type T/D/B/S/R/W/V),
  # Mach-O leading underscore stripped, sorted unique. Deliberately UNFILTERED
  # so an accidental non-f2e_ export changes the digest and surfaces as an ABI
  # leak instead of being hidden by a namespace filter.
  nm --defined-only -g "$1" 2>/dev/null \
    | awk 'NF>=3 && $2 ~ /^[TDBSRWV]$/ {print $3}' \
    | sed 's/^_//' | sort -u > "$1.symbols.txt"
}

emit_buildinfo() { # artifact triple kind compiler linker archiver sysroot floor flags...
  local artifact=$1 triple=$2 kind=$3 compiler=$4 linker=$5 archiver=$6 sysroot=$7 floor=$8; shift 8
  python3 - "$artifact" "$triple" "$kind" "$compiler" "$linker" "$archiver" "$sysroot" "$floor" "$@" <<'EOF'
import json, sys
a = sys.argv
info = {
    "target": a[2], "kind": a[3], "compiler": a[4], "linker": a[5],
    "archiver": a[6], "sdk_or_sysroot": a[7], "minimum_runtime": a[8],
    "compile_flags": a[9:],
}
with open(a[1] + ".buildinfo.json", "w") as f:
    json.dump(info, f, indent=2, sort_keys=True)
    f.write("\n")
EOF
}

build_one() { # triple outdir
  local triple=$1 dir=$2
  mkdir -p "$dir"
  local floor; floor=$(runtime_floor "$triple")
  local objs=() cc_desc link_desc ar_desc sysroot shared_name shared_flags=() cc=()

  case "$triple" in
    aarch64-apple-darwin|x86_64-apple-darwin)
      local arch=arm64 minflag
      [ "$triple" = x86_64-apple-darwin ] && arch=x86_64
      case "$floor" in "macOS 11.0") minflag=-mmacosx-version-min=11.0;; "macOS 10.15") minflag=-mmacosx-version-min=10.15;; *) echo "unknown darwin floor $floor"; exit 2;; esac
      local sdkpath; sdkpath=$(xcrun --sdk macosx --show-sdk-path)
      cc=(clang -arch "$arch" "$minflag" -isysroot "$sdkpath")
      cc_desc="$(clang --version | head -1)"
      link_desc="ld64 via clang driver ($cc_desc)"
      sysroot="MacOSX$(xcrun --sdk macosx --show-sdk-version).sdk"
      shared_name=libflags2env.dylib
      # No -no_uuid: modern dyld refuses to load dylibs without LC_UUID
      # ("missing LC_UUID load command" — found by the harness's own dlopen
      # probe). ld's UUID is content-derived, so determinism is preserved and
      # `verify` proves it.
      shared_flags=(-dynamiclib -Wl,-install_name,@rpath/libflags2env.dylib)
      ;;
    *-linux-*)
      case "$triple" in
        x86_64-unknown-linux-gnu)      cc=(zig cc -target x86_64-linux-gnu.2.28);;
        aarch64-unknown-linux-gnu)     cc=(zig cc -target aarch64-linux-gnu.2.28);;
        x86_64-unknown-linux-musl)     cc=(zig cc -target x86_64-linux-musl);;
        aarch64-unknown-linux-musl)    cc=(zig cc -target aarch64-linux-musl);;
        armv7-unknown-linux-gnueabihf) cc=(zig cc -target arm-linux-gnueabihf.2.28);;
        *) echo "unknown linux triple: $triple"; exit 2;;
      esac
      local zv; zv=$(zig version)
      cc_desc="zig cc $zv (target ${cc[3]})"
      link_desc="lld via zig cc $zv"
      case "$triple" in
        *musl*) sysroot="zig $zv bundled musl 1.2.x";;
        *)      sysroot="zig $zv bundled glibc compat (floor per target suffix)";;
      esac
      shared_name=libflags2env.so
      shared_flags=(-shared -Wl,-soname,libflags2env.so)
      ;;
    *) echo "unknown triple: $triple"; exit 2;;
  esac
  ar_desc="zig ar ($(zig ar --version 2>/dev/null | head -1))"

  local o
  for s in "${SRC[@]}"; do
    o="$dir/$(basename "${s%.c}").o"
    "${cc[@]}" "${CFLAGS_COMMON[@]}" -c "$s" -o "$o"
    objs+=("$o")
  done

  make_archive "$dir/libflags2env.a" "${objs[@]}"
  emit_symbols "$dir/libflags2env.a"
  emit_buildinfo "$dir/libflags2env.a" "$triple" static "$cc_desc" "n/a (archive)" "$ar_desc" "$sysroot" "$floor" "${CFLAGS_RECORDED[@]}"

  "${cc[@]}" "${CFLAGS_COMMON[@]}" "${shared_flags[@]}" "${SRC[@]}" -o "$dir/$shared_name"
  if [ "${F2E_SIGN:-off}" = adhoc ] && [[ "$triple" == *apple-darwin ]]; then
    codesign -s - -f "$dir/$shared_name"
  fi
  emit_symbols "$dir/$shared_name"
  emit_buildinfo "$dir/$shared_name" "$triple" shared "$cc_desc" "$link_desc" "n/a" "$sysroot" "$floor" "${CFLAGS_RECORDED[@]}" "${shared_flags[@]}"

  rm -f "${objs[@]}"
  echo "built $triple -> $dir"
}

resolve_set() { # args -> triples on stdout
  if [ $# -eq 0 ] || [ "$1" = tier1 ]; then tier1_triples; else printf '%s\n' "$@"; fi
}

need_flags() { # triples -> "yes/no yes/no" for zig/darwin
  local z=no d=no t
  while read -r t; do case "$t" in *linux*) z=yes;; *apple-darwin) d=yes;; esac; done
  echo "$z $d"
}

cmd_build() {
  local triples; triples=$(resolve_set "$@")
  read -r nz nd < <(echo "$triples" | need_flags)
  check_toolchains "$nz" "$nd"
  echo "SOURCE_DATE_EPOCH=$SDE"
  while read -r t; do build_one "$t" "$OUT/$t"; done <<< "$triples"
}

cmd_verify() {
  local triples; triples=$(resolve_set "$@")
  read -r nz nd < <(echo "$triples" | need_flags)
  check_toolchains "$nz" "$nd"
  local a="$OUT/.verify-a" b="$OUT/.verify-b" rc=0 t f rel
  rm -rf "$a" "$b"
  echo "SOURCE_DATE_EPOCH=$SDE (two independent clean builds, unsigned)"
  while read -r t; do F2E_SIGN=off build_one "$t" "$a/$t" >/dev/null; done <<< "$triples"
  while read -r t; do F2E_SIGN=off build_one "$t" "$b/$t" >/dev/null; done <<< "$triples"
  while read -r t; do
    for f in "$a/$t"/libflags2env.*; do
      case "$f" in *.symbols.txt|*.buildinfo.json) continue;; esac
      rel="$t/$(basename "$f")"
      if cmp -s "$f" "$b/$rel"; then
        printf 'REPRODUCIBLE  %-52s %s\n' "$rel" "$(shasum -a 256 "$f" | cut -c1-16)…"
      else
        printf 'DIVERGENT     %-52s\n' "$rel"; rc=1
      fi
    done
  done <<< "$triples"
  exit $rc
}

case "${1:-}" in
  build)  shift; cmd_build "$@";;
  verify) shift; cmd_verify "$@";;
  list)   tier1_triples;;
  *) echo "usage: $0 {build|verify|list} [tier1|<triple>...]   (env: PREBUILT_OUT, SOURCE_DATE_EPOCH, F2E_SIGN=off|adhoc)"; exit 64;;
esac
