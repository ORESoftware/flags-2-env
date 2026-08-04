#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "verify-vendored-parser.py"
SPEC = importlib.util.spec_from_file_location("verify_vendored_parser", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class VendoredParserIdentityTests(unittest.TestCase):
    def fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path, Path]:
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        consumer = root / "consumer"
        canonical = root / "canonical"
        (consumer / "vendor").mkdir(parents=True)
        (canonical / "src").mkdir(parents=True)
        (canonical / "src" / "parser.c").write_text("canonical-c\n", encoding="utf-8")
        (canonical / "src" / "parser.h").write_text("canonical-h\n", encoding="utf-8")
        (consumer / "vendor" / "parser.c").write_text("canonical-c\n", encoding="utf-8")
        (consumer / "vendor" / "parser.h").write_text("canonical-h\n", encoding="utf-8")
        return temp, consumer, canonical

    def test_exact_parser_bytes_pass(self) -> None:
        temp, consumer, canonical = self.fixture()
        self.addCleanup(temp.cleanup)
        MODULE.verify_vendored_parser(
            consumer,
            canonical,
            "vendor/parser.c",
            "vendor/parser.h",
        )

    def test_both_paths_are_optional_together(self) -> None:
        temp, consumer, canonical = self.fixture()
        self.addCleanup(temp.cleanup)
        MODULE.verify_vendored_parser(consumer, canonical, "", "")
        with self.assertRaisesRegex(
            MODULE.VerificationError,
            "must be supplied together",
        ):
            MODULE.verify_vendored_parser(
                consumer,
                canonical,
                "vendor/parser.c",
                "",
            )

    def test_parser_c_byte_drift_fails_without_dumping_content(self) -> None:
        temp, consumer, canonical = self.fixture()
        self.addCleanup(temp.cleanup)
        secret = "consumer-only-runtime-secret"
        (consumer / "vendor" / "parser.c").write_text(secret, encoding="utf-8")
        with self.assertRaisesRegex(
            MODULE.VerificationError,
            "vendored parser C does not match the immutable parser_ref",
        ) as caught:
            MODULE.verify_vendored_parser(
                consumer,
                canonical,
                "vendor/parser.c",
                "vendor/parser.h",
            )
        self.assertNotIn(secret, str(caught.exception))

    def test_parser_header_byte_drift_fails(self) -> None:
        temp, consumer, canonical = self.fixture()
        self.addCleanup(temp.cleanup)
        (consumer / "vendor" / "parser.h").write_text("drift\n", encoding="utf-8")
        with self.assertRaisesRegex(
            MODULE.VerificationError,
            "vendored parser header does not match the immutable parser_ref",
        ):
            MODULE.verify_vendored_parser(
                consumer,
                canonical,
                "vendor/parser.c",
                "vendor/parser.h",
            )

    def test_path_traversal_is_rejected_before_file_access(self) -> None:
        temp, consumer, canonical = self.fixture()
        self.addCleanup(temp.cleanup)
        outside = consumer.parent / "outside.c"
        outside.write_text("canonical-c\n", encoding="utf-8")
        with self.assertRaisesRegex(
            MODULE.VerificationError,
            "safe relative file path",
        ):
            MODULE.verify_vendored_parser(
                consumer,
                canonical,
                "../outside.c",
                "vendor/parser.h",
            )

    def test_missing_file_is_rejected(self) -> None:
        temp, consumer, canonical = self.fixture()
        self.addCleanup(temp.cleanup)
        (consumer / "vendor" / "parser.c").unlink()
        with self.assertRaisesRegex(
            MODULE.VerificationError,
            "readable regular file inside its checkout",
        ):
            MODULE.verify_vendored_parser(
                consumer,
                canonical,
                "vendor/parser.c",
                "vendor/parser.h",
            )

    @unittest.skipIf(os.name == "nt", "symlink semantics differ on Windows")
    def test_symlink_escape_is_rejected(self) -> None:
        temp, consumer, canonical = self.fixture()
        self.addCleanup(temp.cleanup)
        outside = consumer.parent / "outside.c"
        outside.write_text("canonical-c\n", encoding="utf-8")
        (consumer / "vendor" / "parser.c").unlink()
        (consumer / "vendor" / "parser.c").symlink_to(outside)
        with self.assertRaisesRegex(
            MODULE.VerificationError,
            "inside its checkout",
        ):
            MODULE.verify_vendored_parser(
                consumer,
                canonical,
                "vendor/parser.c",
                "vendor/parser.h",
            )


if __name__ == "__main__":
    unittest.main()
