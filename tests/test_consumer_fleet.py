#!/usr/bin/env python3
"""Regression tests for the read-only consumer fleet matrix renderer."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "render-consumer-fleet.py"
FLEET = ROOT / "consumer-fleet.json"


class ConsumerFleetTests(unittest.TestCase):
    def load(self) -> dict[str, object]:
        return json.loads(FLEET.read_text(encoding="utf-8"))

    def run_document(self, document: dict[str, object]) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fleet.json"
            path.write_text(json.dumps(document), encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(SCRIPT), "--fleet", str(path), "--print"],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

    def test_repository_matrix_is_valid_and_has_unique_labels(self) -> None:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--fleet", str(FLEET), "--print"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        matrix = json.loads(result.stdout)
        entries = matrix["include"]
        self.assertGreaterEqual(len(entries), 20)
        self.assertEqual(len(entries), len({entry["label"] for entry in entries}))
        self.assertIn(
            "ORESoftware/k8s-cluster:remote/deployments/browser-mcp-rs/.cli-flags.toml",
            {entry["label"] for entry in entries},
        )

    def test_mutable_tooling_reference_is_rejected(self) -> None:
        document = self.load()
        document["tooling_ref"] = "main"
        result = self.run_document(document)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("full lowercase commit SHA", result.stderr)

    def test_duplicate_contract_is_rejected_case_insensitively(self) -> None:
        document = self.load()
        consumers = document["consumers"]
        assert isinstance(consumers, list)
        duplicate = deepcopy(consumers[0])
        assert isinstance(duplicate, dict)
        duplicate["repository"] = str(duplicate["repository"]).swapcase()
        consumers.insert(1, duplicate)
        result = self.run_document(document)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate consumer", result.stderr)

    def test_contract_path_cannot_escape_checkout(self) -> None:
        document = self.load()
        consumers = document["consumers"]
        assert isinstance(consumers, list)
        entry = consumers[0]
        assert isinstance(entry, dict)
        entry["contract"] = "../.cli-flags.toml"
        result = self.run_document(document)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsafe contract path", result.stderr)

    def test_unsorted_entries_are_rejected(self) -> None:
        document = self.load()
        consumers = document["consumers"]
        assert isinstance(consumers, list)
        consumers[0], consumers[1] = consumers[1], consumers[0]
        result = self.run_document(document)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be sorted", result.stderr)


if __name__ == "__main__":
    unittest.main()
