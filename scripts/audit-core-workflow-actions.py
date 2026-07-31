#!/usr/bin/env python3
"""Audit the core GitHub Actions workflows without third-party dependencies."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = (
    ROOT / ".github/workflows/e2e.yml",
    ROOT / ".github/workflows/client-packaging.yml",
    ROOT / ".github/workflows/cli-flags-audit.yml",
)
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
DOCKER_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
USES = re.compile(r"\buses:\s*([^\s#]+)")
JOB = re.compile(r"^  ([A-Za-z0-9_-]+):(?:\s*#.*)?$")


def section(lines: list[str], name: str) -> list[str] | None:
    marker = f"{name}:"
    for index, line in enumerate(lines):
        if line.rstrip() != marker:
            continue
        result: list[str] = []
        for candidate in lines[index + 1 :]:
            if candidate.strip() and not candidate.startswith((" ", "\t")):
                break
            result.append(candidate)
        return result
    return None


def jobs(lines: list[str]) -> list[tuple[str, list[str]]]:
    try:
        start = next(index for index, line in enumerate(lines) if line.rstrip() == "jobs:")
    except StopIteration:
        return []

    result: list[tuple[str, list[str]]] = []
    name: str | None = None
    body: list[str] = []
    for line in lines[start + 1 :]:
        if line.strip() and not line.startswith((" ", "\t")):
            break
        match = JOB.match(line.rstrip())
        if match:
            if name is not None:
                result.append((name, body))
            name = match.group(1)
            body = []
        elif name is not None:
            body.append(line)
    if name is not None:
        result.append((name, body))
    return result


def audit_checkout(path: Path, lines: list[str]) -> list[str]:
    findings: list[str] = []
    for index, line in enumerate(lines):
        match = USES.search(line)
        if not match or not match.group(1).startswith("actions/checkout@"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        block: list[str] = []
        for candidate in lines[index + 1 :]:
            candidate_indent = len(candidate) - len(candidate.lstrip(" "))
            if candidate.strip() and candidate_indent == indent and candidate.lstrip().startswith("- "):
                break
            if candidate.strip() and candidate_indent < indent:
                break
            block.append(candidate)
        if not any(re.match(r"^\s*persist-credentials:\s*false\s*(?:#.*)?$", item) for item in block):
            findings.append(f"{path}:{index + 1}: checkout must set persist-credentials: false")
    return findings


def audit_action(path: Path, line_number: int, reference: str) -> str | None:
    if reference.startswith("./"):
        return None
    if reference.startswith("docker://"):
        image = reference.removeprefix("docker://")
        if "@" not in image or not DOCKER_DIGEST.fullmatch(image.rsplit("@", 1)[1]):
            return f"{path}:{line_number}: Docker action is not pinned by sha256 digest: {reference}"
        return None
    if "@" not in reference or not FULL_SHA.fullmatch(reference.rsplit("@", 1)[1]):
        return f"{path}:{line_number}: action is not pinned by a full commit SHA: {reference}"
    return None


def audit_workflow(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    findings: list[str] = []

    permissions = section(lines, "permissions")
    if permissions is None or not any(re.match(r"^  contents:\s*read\s*$", line) for line in permissions):
        findings.append(f"{path}: top-level contents: read is required")

    concurrency = section(lines, "concurrency")
    if concurrency is None or not any(re.match(r"^  cancel-in-progress:\s*true\s*$", line) for line in concurrency):
        findings.append(f"{path}: concurrency with cancel-in-progress: true is required")

    workflow_jobs = jobs(lines)
    if not workflow_jobs:
        findings.append(f"{path}: no jobs found")
    for job_name, body in workflow_jobs:
        if not any(re.match(r"^    timeout-minutes:\s*[1-9][0-9]*\s*$", line) for line in body):
            findings.append(f"{path}: job {job_name!r} requires timeout-minutes")

    for line_number, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        match = USES.search(line)
        if match:
            finding = audit_action(path, line_number, match.group(1))
            if finding:
                findings.append(finding)

    findings.extend(audit_checkout(path, lines))

    if path.name == "e2e.yml":
        mutable_default = re.compile(r'^\s+default:\s*["\']?(?:main|master|stable|v\d+)["\']?\s*$')
        for line_number, line in enumerate(lines, 1):
            if mutable_default.match(line):
                findings.append(f"{path}:{line_number}: cross-repository workflow input default must be an immutable SHA")
        fallback_refs = re.findall(r"ref:\s*\$\{\{\s*inputs\.[^|]+\|\|\s*'([^']+)'\s*\}\}", text)
        for fallback in fallback_refs:
            if not FULL_SHA.fullmatch(fallback):
                findings.append(f"{path}: checkout input fallback is not an immutable SHA: {fallback}")

    return findings


def main() -> int:
    findings: list[str] = []
    for workflow in WORKFLOWS:
        if not workflow.is_file():
            findings.append(f"missing core workflow: {workflow}")
            continue
        findings.extend(audit_workflow(workflow))

    if findings:
        print("Core workflow policy violations:", file=sys.stderr)
        for finding in findings:
            print(f"- {finding}", file=sys.stderr)
        return 1

    print("Core workflow action policy passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
