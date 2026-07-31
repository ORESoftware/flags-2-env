from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "audit-core-workflow-actions.py"
SPEC = importlib.util.spec_from_file_location("workflow_action_policy", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)

PINNED_CHECKOUT = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"


def workflow(*, top_permissions: str = "permissions:\n  contents: read", job_permissions: str = "") -> str:
    job_permissions = f"\n{job_permissions}" if job_permissions else ""
    return f"""name: fixture

on:
  pull_request:

{top_permissions}

concurrency:
  group: fixture-${{{{ github.ref }}}}
  cancel-in-progress: true

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10{job_permissions}
    steps:
      - uses: {PINNED_CHECKOUT}
        with:
          persist-credentials: false
      - run: true
"""


class WorkflowActionPolicyTests(unittest.TestCase):
    def audit(self, text: str) -> list[str]:
        return policy.audit_workflow_text(Path("fixture.yml"), text)

    def test_read_only_canonical_workflow_passes(self) -> None:
        self.assertEqual([], self.audit(workflow()))

    def test_extra_top_level_write_scope_is_rejected(self) -> None:
        findings = self.audit(
            workflow(top_permissions="permissions:\n  contents: read\n  packages: write")
        )
        self.assertTrue(any("packages: write" in finding for finding in findings))

    def test_top_level_inline_map_is_rejected(self) -> None:
        findings = self.audit(workflow(top_permissions="permissions: {contents: read, packages: write}"))
        self.assertTrue(any("canonical block mapping" in finding for finding in findings))

    def test_top_level_write_all_is_rejected(self) -> None:
        findings = self.audit(workflow(top_permissions="permissions: write-all"))
        self.assertTrue(any("write-all" in finding for finding in findings))

    def test_job_level_write_scope_is_rejected(self) -> None:
        findings = self.audit(workflow(job_permissions="    permissions:\n      packages: write"))
        self.assertTrue(any("prohibited packages: write" in finding for finding in findings))

    def test_job_level_inline_map_is_rejected(self) -> None:
        findings = self.audit(workflow(job_permissions="    permissions: {packages: write}"))
        self.assertTrue(any("canonical block mapping" in finding for finding in findings))

    def test_job_level_write_all_is_rejected(self) -> None:
        findings = self.audit(workflow(job_permissions="    permissions: write-all"))
        self.assertTrue(any("write-all" in finding for finding in findings))

    def test_quoted_write_is_rejected(self) -> None:
        findings = self.audit(workflow(job_permissions='    permissions:\n      packages: "write"'))
        self.assertTrue(any("unquoted" in finding for finding in findings))

    def test_yaml_permission_alias_is_rejected(self) -> None:
        findings = self.audit(workflow(job_permissions="    permissions: *release_permissions"))
        self.assertTrue(any("aliases" in finding for finding in findings))

    def test_mutable_action_is_rejected(self) -> None:
        findings = self.audit(workflow().replace(PINNED_CHECKOUT, "actions/checkout@v4"))
        self.assertTrue(any("full commit SHA" in finding for finding in findings))

    def test_checkout_credentials_must_be_disabled(self) -> None:
        findings = self.audit(workflow().replace("persist-credentials: false", "fetch-depth: 1"))
        self.assertTrue(any("persist-credentials: false" in finding for finding in findings))


if __name__ == "__main__":
    unittest.main()
