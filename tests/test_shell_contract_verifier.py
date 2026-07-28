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
        self.assertIn("Open-Meteo forecast endpoint for commercial use", descriptions)
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
        self.assertIn("env=AGENT_TASKS_RDS_DATABASE_URL; type=string", details)

    def test_literal_pipe_inside_description_does_not_split_the_column(self) -> None:
        output = """
+------------+----------+---------------------------------------+
| Option(s)  | Default  | Description                           |
+------------+----------+---------------------------------------+
| --format   | sql      | Output format: sql | json for CI      |
+------------+----------+---------------------------------------+
"""
        descriptions = MODULE.table_column(output, {"Description", "Details"})
        self.assertIn("Output format: sql json for CI", descriptions)

    def test_command_basename_normalizes_paths_and_rejects_metacharacters(self) -> None:
        self.assertEqual(MODULE.command_basename("../zed"), "zed")
        self.assertEqual(MODULE.command_basename("/usr/bin/zed"), "zed")
        for unsafe in ["zed completion", "zed;rm"]:
            with self.assertRaises(ValueError):
                MODULE.command_basename(unsafe)
        self.assertEqual(MODULE.command_basename("zed-cli"), "zed-cli")


if __name__ == "__main__":
    unittest.main()
