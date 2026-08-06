#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-all}
readonly proof_timeout=600
readonly solver_kill_grace=10

require_timeout() {
  command -v timeout >/dev/null || {
    echo "GNU timeout is required; run this command through nix develop" >&2
    return 1
  }
}

run_manifest() {
  command -v jq >/dev/null || {
    echo "jq is required; run this command through nix develop" >&2
    return 1
  }

  local manifest="$repo_root/formal/fmctl.json"
  echo "==> Manifest: ${manifest#"$repo_root/"}"
  jq --exit-status '
    type == "object"
    and ((keys | sort) == ([
      "gitRef",
      "heuristics",
      "languages",
      "paths",
      "repoUrl",
      "schemaVersion"
    ] | sort))
    and .schemaVersion == "formal-methods.v1"
    and .repoUrl == "https://github.com/ORESoftware/flags-2-env.git"
    and (.gitRef | type == "string"
      and test("^[A-Za-z0-9][A-Za-z0-9._/-]{0,179}$")
      and contains("..") == false
      and startswith("-") == false)
    and (.paths | type == "array"
      and length > 0
      and length <= 64
      and length == (unique | length)
      and all(
        type == "string"
        and length > 0
        and length <= 240
        and startswith("/") == false
        and contains("\\") == false
        and (split("/") | all(. != "." and . != ".."))
      ))
    and (.languages | type == "array"
      and length == 3
      and (sort == ["c", "h", "rs"]))
    and (.heuristics | type == "boolean")
  ' "$manifest" >/dev/null

  local declared_path resolved_path
  while IFS= read -r declared_path; do
    resolved_path=$(realpath "$repo_root/$declared_path") || {
      echo "manifest path does not exist: $declared_path" >&2
      return 1
    }
    case "$resolved_path/" in
      "$repo_root"/*) ;;
      *)
        echo "manifest path escapes the repository: $declared_path" >&2
        return 1
        ;;
    esac
  done < <(jq -r '.paths[]' "$manifest")
}

run_cbmc() {
  command -v cbmc >/dev/null || {
    echo "cbmc is required; run this command through nix develop" >&2
    return 1
  }
  require_timeout

  local harness="$repo_root/formal/cbmc/parser_harness.c"
  local proof
  for proof in \
    harness_size_bounds \
    harness_strlcpy \
    harness_option_shape \
    harness_coercion_slot_bounds; do
    echo "==> CBMC: $proof"
    timeout \
      --signal=TERM \
      --kill-after="${solver_kill_grace}s" \
      "${proof_timeout}s" \
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
  require_timeout

  local -a specs=()
  local spec output line checks size
  while IFS= read -r -d '' spec; do
    specs+=("$spec")
  done < <(find "$repo_root/formal/smt" -type f -name '*.smt2' -print0 | sort -z)
  if (( ${#specs[@]} == 0 || ${#specs[@]} > 64 )); then
    echo "expected between 1 and 64 SMT specifications, got ${#specs[@]}" >&2
    return 1
  fi
  for spec in "${specs[@]}"; do
    size=$(wc -c <"$spec")
    if (( size > 1048576 )); then
      echo "SMT specification exceeds 1 MiB: ${spec#"$repo_root/"}" >&2
      return 1
    fi
    echo "==> Z3: ${spec#"$repo_root/"}"
    output=$(
      timeout \
        --signal=TERM \
        --kill-after="${solver_kill_grace}s" \
        "${proof_timeout}s" \
        z3 -T:60 -smt2 "$spec"
    )
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
  done
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
