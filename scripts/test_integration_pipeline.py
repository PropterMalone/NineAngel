#!/usr/bin/env python3
"""End-to-end reducer-era fallback pipeline test; never calls a model."""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

D = Path(__file__).resolve().parent


class PipelineTests(unittest.TestCase):
    def test_help_is_handled_before_run_path_resolution(self):
        result = subprocess.run([str(D / "integrate-run.sh"), "--help"],
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--clone-retry", result.stdout)
        self.assertNotIn("Traceback", result.stderr)

    def test_unknown_action_is_rejected_before_run_mutation(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); run = self.make_run(root)
            result = subprocess.run([str(D / "integrate-run.sh"), str(run), "--bogus"],
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertIn("unknown action: --bogus", result.stderr)
            self.assertFalse((run / "integration-workset.json").exists())

    def make_run(self, root):
        run = root / "20260830T120000Z-pipe"
        (run / "findings").mkdir(parents=True)
        (run / "findings" / "adv.md").write_text(
            "## Adversarial Review\n\n### Findings\n\n#### Important\n"
            "- **Deadline leaks work** `[moderate]` — `src/a.py:10` — Work continues after return.\n"
            "\n#### Critical\n- None.\n")
        (run / "usage.jsonl").write_text(json.dumps({
            "phase": "persona", "name": "adv", "model": "test", "backend": "test",
            "total_tokens": 100, "tool_uses": 1, "duration_ms": 10,
            "started_at": "2026-08-30T12:00:00Z", "ended_at": "2026-08-30T12:00:01Z",
            "reader_pack": False}) + "\n")
        (run / "PROJECT_COMMIT").write_text("null\n")
        meta = {"version": 1, "integration_pipeline": "semantic-reducer-v1", "status": "ready",
                "run_dir": str(run), "project_dir": str(root), "project": "demo",
                "date": "2026-08-30", "mode": "diff", "reader_mode": "off",
                "files_reviewed": 1, "preflight": {"test": "pass", "build": "pass", "lint": "pass"},
                "multiball": None, "pass_denominators": {}, "personas_run": ["adv"],
                "personas_dropped": [], "personas_failed": [],
                "codebase": {"files": 1, "lines": 20}, "previous_run_dir": None}
        (run / "run-meta.json").write_text(json.dumps(meta))
        return run

    def test_no_qualified_runner_renders_and_finalizes_visible_union(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); run = self.make_run(root)
            env = os.environ.copy()
            env["ANGEL_REDUCER_BACKEND"] = "disabled"
            env["ANGEL_USAGE_LOG"] = str(root / "usage.log")
            env["ANGEL_RUNS_ROOT"] = str(root)
            result = subprocess.run([str(D / "integrate-run.sh"), str(run)], env=env,
                                    text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            snapshot = json.loads((run / "findings-snapshot.json").read_text())
            self.assertEqual(snapshot["version"], 3)
            self.assertTrue(snapshot["integration_degraded"])
            self.assertEqual(snapshot["integration_degraded_reason"], "no-qualified-runner")
            self.assertEqual(len(snapshot["findings"]), 1)
            self.assertIn("DEGRADED INTEGRATION", (run / "report.md").read_text())
            self.assertTrue((run / "dispositions.json").is_file())

    def test_clone_retry_creates_fresh_run_with_preintegration_evidence(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); run = self.make_run(root)
            env = os.environ.copy()
            env["ANGEL_REDUCER_BACKEND"] = "disabled"
            env["ANGEL_USAGE_LOG"] = str(root / "usage.log")
            env["ANGEL_RUNS_ROOT"] = str(root)
            first = subprocess.run([str(D / "integrate-run.sh"), str(run)], env=env,
                                   text=True, capture_output=True, timeout=30)
            self.assertEqual(first.returncode, 0, first.stderr)
            retry = subprocess.run([str(D / "integrate-run.sh"), str(run), "--clone-retry"],
                                   env=env, text=True, capture_output=True, timeout=30)
            self.assertEqual(retry.returncode, 0, retry.stderr)
            clones = [p for p in root.iterdir() if p.is_dir() and p != run]
            self.assertEqual(len(clones), 1)
            clone = clones[0]
            meta = json.loads((clone / "run-meta.json").read_text())
            self.assertEqual(meta["previous_run_dir"], str(run))
            self.assertTrue((clone / "findings-snapshot.json").is_file())
            phases = [json.loads(line)["phase"] for line in
                      (clone / "usage.jsonl").read_text().splitlines()]
            self.assertEqual(phases.count("persona"), 1)
            self.assertEqual(phases.count("integrator"), 1)


if __name__ == "__main__": unittest.main()
