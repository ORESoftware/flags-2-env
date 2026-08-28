"""Unit tests for the cutoff half of scripts/verify-source-migration.py.

The failure mode guarded here is the one that actually happened: the
compatibility window is a dated promise, the checker never looked at a
calendar, and so it kept printing a tick after the promise expired. Every
test below therefore pins an explicit evaluation date, and two of them assert
that the *same* manifest is accepted before the window closes and rejected
after it -- a checker that ignored the date would pass both and go unnoticed.
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import unittest
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "scripts" / "verify-source-migration.py"
SUPPORT_ENDS_ON = date.fromisoformat("2026-08-19")
WITHIN_WINDOW = "2026-08-15"
AFTER_WINDOW = "2026-08-22"


def load_module():
    spec = importlib.util.spec_from_file_location("verify_source_migration", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pending(*obligations: str) -> dict:
    return {
        "state": "pending",
        "completedOn": None,
        "mirrorDisposition": "read-only-historical-source",
        "pendingObligations": list(obligations),
    }


def complete(completed_on: str) -> dict:
    return {
        "state": "complete",
        "completedOn": completed_on,
        "mirrorDisposition": "read-only-historical-source",
        "pendingObligations": [],
    }


class CutoffTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self._saved = os.environ.get("F2E_MIGRATION_TODAY")

    def tearDown(self) -> None:
        if self._saved is None:
            os.environ.pop("F2E_MIGRATION_TODAY", None)
        else:
            os.environ["F2E_MIGRATION_TODAY"] = self._saved

    def check(self, cutoff: dict, today: str) -> list[str]:
        os.environ["F2E_MIGRATION_TODAY"] = today
        return self.module.validate_cutoff(cutoff, SUPPORT_ENDS_ON)

    def test_pending_obligations_are_inert_inside_the_window(self) -> None:
        errors = self.check(pending("mirror-archived"), WITHIN_WINDOW)
        self.assertEqual(errors, [])

    def test_same_record_is_rejected_once_the_window_closes(self) -> None:
        record = pending("mirror-archived")
        self.assertEqual(self.check(dict(record), WITHIN_WINDOW), [])
        errors = self.check(dict(record), AFTER_WINDOW)
        self.assertTrue(errors, "an expired window must not pass silently")
        self.assertTrue(any("2026-08-19" in error for error in errors))
        self.assertTrue(any("3 day(s) ago" in error for error in errors))

    def test_every_outstanding_obligation_names_its_action(self) -> None:
        errors = self.check(
            pending("mirror-archived", "mirror-notice-updated"), AFTER_WINDOW
        )
        for obligation, action in self.module.CUTOFF_OBLIGATIONS.items():
            matching = [error for error in errors if obligation in error]
            self.assertTrue(matching, f"{obligation} was not reported")
            self.assertTrue(
                any(action in error for error in matching),
                f"{obligation} was reported without the action that clears it",
            )

    def test_empty_pending_list_still_requires_the_state_to_be_completed(self) -> None:
        errors = self.check(pending(), AFTER_WINDOW)
        self.assertTrue(any('"complete"' in error for error in errors))

    def test_completed_cutoff_passes(self) -> None:
        self.assertEqual(self.check(complete("2026-08-20"), AFTER_WINDOW), [])

    def test_completion_may_not_predate_the_window_closing(self) -> None:
        errors = self.check(complete("2026-08-19"), AFTER_WINDOW)
        self.assertTrue(any("after the compatibility window closes" in e for e in errors))

    def test_completion_may_not_be_in_the_future(self) -> None:
        errors = self.check(complete("2026-08-30"), AFTER_WINDOW)
        self.assertTrue(any("must not be in the future" in error for error in errors))

    def test_completed_state_may_not_keep_obligations(self) -> None:
        record = complete("2026-08-20")
        record["pendingObligations"] = ["mirror-archived"]
        errors = self.check(record, AFTER_WINDOW)
        self.assertTrue(any("still listed" in error for error in errors))

    def test_pending_state_may_not_carry_a_completion_date(self) -> None:
        record = pending("mirror-archived")
        record["completedOn"] = "2026-08-20"
        errors = self.check(record, AFTER_WINDOW)
        self.assertTrue(any("must be null while the cutoff is pending" in e for e in errors))

    def test_unknown_obligation_is_rejected(self) -> None:
        record = pending()
        record["pendingObligations"] = ["mirror-renamed"]
        errors = self.check(record, WITHIN_WINDOW)
        self.assertTrue(any("unknown entries" in error for error in errors))

    def test_missing_field_is_rejected(self) -> None:
        record = pending("mirror-archived")
        del record["mirrorDisposition"]
        errors = self.check(record, WITHIN_WINDOW)
        self.assertTrue(any("cutoff keys differ" in error for error in errors))

    def test_malformed_completion_date_is_rejected(self) -> None:
        record = complete("20th of August")
        errors = self.check(record, AFTER_WINDOW)
        self.assertTrue(any("YYYY-MM-DD" in error for error in errors))


class SupportClaimTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def test_shipped_documents_make_no_present_tense_claim_after_the_cutoff(self) -> None:
        errors = self.module.validate_support_claims(
            date.fromisoformat(AFTER_WINDOW), SUPPORT_ENDS_ON
        )
        self.assertEqual(errors, [])

    def test_claims_are_ignored_while_the_window_is_open(self) -> None:
        errors = self.module.validate_support_claims(
            date.fromisoformat(WITHIN_WINDOW), SUPPORT_ENDS_ON
        )
        self.assertEqual(errors, [])


class ShippedManifestTest(unittest.TestCase):
    def run_script(self, today: str) -> subprocess.CompletedProcess:
        environment = dict(os.environ, F2E_MIGRATION_TODAY=today)
        return subprocess.run(
            [sys.executable, str(SCRIPT)],
            capture_output=True,
            text=True,
            env=environment,
        )

    def test_shipped_manifest_is_valid_inside_the_window(self) -> None:
        result = self.run_script(WITHIN_WINDOW)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_shipped_manifest_reports_the_outstanding_cutoff(self) -> None:
        result = self.run_script(AFTER_WINDOW)
        self.assertEqual(result.returncode, 1)
        self.assertIn("cutoff is still pending", result.stderr)


class CutoffDateIsSingleSourcedTest(unittest.TestCase):
    """The cutoff date is spelled in four places; nothing asserted they agree.

    `source-migration.json` holds the contract, but the migration verifier, the
    consumer-compliance policy, and the compatibility publisher each carry their
    own literal. Moving the window in one of them would leave the others
    silently enforcing a different date -- the vendored-parser drift problem,
    applied to a date instead of a file.
    """

    def setUp(self) -> None:
        manifest = json.loads(
            (REPO_ROOT / "docs" / "source-migration.json").read_text(encoding="utf-8")
        )
        self.support_ends_on = manifest["compatibility"]["supportEndsOn"]

    def read(self, relative: str) -> str:
        return (REPO_ROOT / relative).read_text(encoding="utf-8")

    def test_manifest_matches_the_window_this_contract_reviewed(self) -> None:
        self.assertEqual(self.support_ends_on, SUPPORT_ENDS_ON.isoformat())

    def test_migration_verifier_pins_the_manifest_date(self) -> None:
        self.assertIn(
            f'end.isoformat() != "{self.support_ends_on}"',
            self.read("scripts/verify-source-migration.py"),
        )

    def test_consumer_compliance_policy_pins_the_manifest_date(self) -> None:
        year, month, day = (int(part) for part in self.support_ends_on.split("-"))
        self.assertIn(
            f"COMPATIBILITY_SUPPORT_END = date({year}, {month}, {day})",
            self.read("scripts/verify-consumer-compliance.py"),
        )

    def test_compatibility_publisher_pins_the_manifest_date(self) -> None:
        self.assertIn(
            f"support_end={self.support_ends_on}",
            self.read("scripts/publish-zed-compatibility.sh"),
        )


if __name__ == "__main__":
    unittest.main()
