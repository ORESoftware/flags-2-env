#!/usr/bin/env python3
"""Unit tests for terminal-wrapped flags2env help verification."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "verify-shell-contract.py"
SPEC = importlib.util.spec_from_file_location("verify_shell_contract", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ShellContractVerifierTests(unittest.TestCase):
    def test_selected_columns_are_reconstructed_without_interleaving(self) -> None:
        output = """
+----------------------+------------+----------------+-----------------------+
| Option(s)            | Env        | Default        | Description           |
+----------------------+------------+----------------+-----------------------+
| --open-meteo-base-u  | API_URL    | https://api.op | Open-Meteo forecast   |
| rl                   |            | en-meteo.com/v | endpoint for          |
|                      |            | 1/forecast     | commercial use        |
+----------------------+------------+----------------+-----------------------+
"""
        options = MODULE.table_column(output, {"Option(s)"}).replace(" ", "")
        descriptions = MODULE.table_column(output, {"Description", "Details"})
        self.assertIn("--open-meteo-base-url", options)
        self.assertEqual(descriptions, "Open-Meteo forecast endpoint for commercial use")
        self.assertNotIn("en-meteo.com", descriptions)

    def test_compact_details_layout_reconstructs_wrapped_long_option(self) -> None:
        output = """
+------------------------+-------------------------------------------+
| Option(s)              | Details                                   |
+------------------------+-------------------------------------------+
| --agent-tasks-rds-data | env=AGENT_TASKS_RDS_DATABASE_URL;         |
| base-url               | type=string                               |
+------------------------+-------------------------------------------+
"""
        options = MODULE.table_column(output, {"Option(s)"}).replace(" ", "")
        details = MODULE.table_column(output, {"Description", "Details"})
        self.assertIn("--agent-tasks-rds-database-url", options)
        self.assertEqual(details, "env=AGENT_TASKS_RDS_DATABASE_URL; type=string")

    def test_command_basename_rejects_paths_and_shell_metacharacters(self) -> None:
        for unsafe in ["../zed", "zed completion", "zed;rm", "/usr/bin/zed"]:
            with self.assertRaises(ValueError):
                MODULE.command_basename(unsafe)
        self.assertEqual(MODULE.command_basename("zed-cli"), "zed-cli")


if __name__ == "__main__":
    unittest.main()
