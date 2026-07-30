#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "verify-consumer-compliance.py"
SPEC = importlib.util.spec_from_file_location("verify_consumer_compliance", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ConsumerCompliancePolicyTests(unittest.TestCase):
    def test_token_metadata_is_not_secret_material(self) -> None:
        for env in [
            "AUTH_TOKEN_TTL_SECS",
            "API_TOKEN_EXPIRY_SECONDS",
            "ACCESS_TOKEN_LIFETIME_MINUTES",
            "JWT_TOKEN_ISSUER",
            "JWT_TOKEN_AUDIENCE",
        ]:
            with self.subTest(env=env):
                self.assertFalse(MODULE.is_secret_bearing_env(env))

    def test_secret_values_and_compound_connection_strings_remain_blocked(self) -> None:
        for env in [
            "API_TOKEN",
            "ACCESS_TOKEN_VALUE",
            "AUTH_SIGNING_KEY_PEM",
            "CLIENT_SECRET",
            "AUTH_DATABASE_URL",
            "REDIS_URL",
            "OTEL_EXPORTER_OTLP_HEADERS",
            "SESSION_COOKIE",
        ]:
            with self.subTest(env=env):
                self.assertTrue(MODULE.is_secret_bearing_env(env))

    def test_metadata_exception_does_not_hide_a_second_secret_marker(self) -> None:
        for env in [
            "AUTH_TOKEN_TTL_SECRET",
            "API_TOKEN_EXPIRY_PASSWORD",
            "ACCESS_TOKEN_LIFETIME_KEY",
        ]:
            with self.subTest(env=env):
                self.assertTrue(MODULE.is_secret_bearing_env(env))


if __name__ == "__main__":
    unittest.main()
