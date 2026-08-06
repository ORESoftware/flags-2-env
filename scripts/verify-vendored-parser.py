#!/usr/bin/env python3
"""Verify that a consumer's vendored parser is the immutable parser_ref.

The reusable compliance workflow checks out the consumer and the exact
`parser_ref` in separate directories. This verifier resolves every path inside
its declared checkout root and compares the actual bytes compiled by the
consumer with canonical `src/parser.c` and `src/parser.h`.
"""

from __future__ import annotations

import argparse
import filecmp
import sys
from pathlib import Path, PurePosixPath


class VerificationError(ValueError):
    """Bounded, user-actionable verification failure."""


def safe_regular_file(root: Path, relative: str, label: str) -> Path:
    """Resolve one regular file without allowing checkout-root escape."""

    root = root.resolve(strict=True)
    if not root.is_dir():
        raise VerificationError(f"{label} root is not a directory")

    normalized = relative.replace("\\", "/")
    path = PurePosixPath(normalized)
    if (
        not normalized
        or path.is_absolute()
        or any(part in {"", ".", ".."} for part in path.parts)
    ):
        raise VerificationError(f"{label} must be a safe relative file path")

    try:
        candidate = (root / Path(*path.parts)).resolve(strict=True)
        candidate.relative_to(root)
    except (FileNotFoundError, RuntimeError, ValueError) as error:
        raise VerificationError(
            f"{label} does not name a readable regular file inside its checkout"
        ) from error

    if not candidate.is_file():
        raise VerificationError(
            f"{label} does not name a readable regular file inside its checkout"
        )
    return candidate


def verify_vendored_parser(
    consumer_root: Path,
    canonical_root: Path,
    parser_c_path: str,
    parser_h_path: str,
) -> None:
    """Verify paired vendored parser paths against canonical source bytes."""

    if bool(parser_c_path) != bool(parser_h_path):
        raise VerificationError(
            "vendored parser C and header paths must be supplied together"
        )
    if not parser_c_path:
        return

    actual_c = safe_regular_file(consumer_root, parser_c_path, "vendored parser C")
    actual_h = safe_regular_file(consumer_root, parser_h_path, "vendored parser header")
    expected_c = safe_regular_file(canonical_root, "src/parser.c", "canonical parser C")
    expected_h = safe_regular_file(canonical_root, "src/parser.h", "canonical parser header")

    if not filecmp.cmp(actual_c, expected_c, shallow=False):
        raise VerificationError(
            "vendored parser C does not match the immutable parser_ref"
        )
    if not filecmp.cmp(actual_h, expected_h, shallow=False):
        raise VerificationError(
            "vendored parser header does not match the immutable parser_ref"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer-root", type=Path, required=True)
    parser.add_argument("--canonical-root", type=Path, required=True)
    parser.add_argument("--parser-c-path", default="")
    parser.add_argument("--parser-h-path", default="")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        verify_vendored_parser(
            args.consumer_root,
            args.canonical_root,
            args.parser_c_path,
            args.parser_h_path,
        )
    except (OSError, VerificationError) as error:
        print(f"flags2env vendored parser identity: {error}", file=sys.stderr)
        return 1

    if args.parser_c_path:
        print("flags2env vendored parser identity: ok")
    else:
        print("flags2env vendored parser identity: not requested")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
