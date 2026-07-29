#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-all}

run_manifest() {
  command -v jq >/dev/null || {
    echo "jq is required; run this command through nix develop" >&2
    return 1
  }

  local manifest="$repo_root/formal/fmctl.json"
  echo "==> Manifest: ${manifest#"$repo_root/"}"
  jq --exit-status '
    .schemaVersion == "formal-methods.v1"
    and (.repoUrl | type == "string" and startswith("https://"))
    and (.gitRef | type == "string" and length > 0)
    and (.paths | type == "array" and length > 0 and all(type == "string"))
    and (.languages | type == "array" and length > 0 and all(type == "string"))
    and (.heuristics | type == "boolean")
  ' "$manifest" >/dev/null
}

run_cbmc() {
  command -v cbmc >/dev/null || {
    echo "cbmc is required; run this command through nix develop" >&2
    return 1
  }

  local harness="$repo_root/formal/cbmc/parser_harness.c"
  local proof
  for proof in harness_size_bounds harness_strlcpy harness_option_shape; do
    echo "==> CBMC: $proof"
    cbmc "$harness" \
      --function "$proof" \
      --drop-unused-functions \
      --reachability-slice-fb \
      --bounds-check \
      --pointer-check \
      --pointer-overflow-check \
      --signed-overflow-check \
      --unsigned-overflow-check \
      --conversion-check \
      --div-by-zero-check \
      --unwind 10 \
      --unwinding-assertions \
      --trace \
      --verbosity 3
  done
}

run_z3() {
  command -v z3 >/dev/null || {
    echo "z3 is required; run this command through nix develop" >&2
    return 1
  }

  local spec output line checks
  while IFS= read -r -d '' spec; do
    echo "==> Z3: ${spec#"$repo_root/"}"
    output=$(z3 -smt2 "$spec")
    checks=0
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" != "unsat" ]]; then
        echo "expected an unsat proof obligation, got: $line" >&2
        return 1
      fi
      checks=$((checks + 1))
    done <<<"$output"
    if [[ "$checks" -eq 0 ]]; then
      echo "no proof obligations were evaluated in $spec" >&2
      return 1
    fi
  done < <(find "$repo_root/formal/smt" -type f -name '*.smt2' -print0 | sort -z)
}

case "$mode" in
  all)
    run_manifest
    run_cbmc
    run_z3
    ;;
  manifest)
    run_manifest
    ;;
  cbmc)
    run_cbmc
    ;;
  z3)
    run_z3
    ;;
  *)
    echo "usage: $0 [all|manifest|cbmc|z3]" >&2
    exit 2
    ;;
esac
