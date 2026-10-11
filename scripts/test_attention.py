"""Offline attention-persona selection and mandate contracts; no model calls."""
# pattern: imperative shell
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("validate_personas", ROOT / "scripts/validate-personas.py")
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class AttentionContract(unittest.TestCase):
    def test_opt_in_frontmatter_supports_both_modes(self):
        path = ROOT / "personas/attention.md"
        self.assertTrue(path.is_file(), "shared attention persona must exist")
        self.assertEqual(validator.check_frontmatter(path), [])
        fm = path.read_text().split("---", 2)[1].splitlines()
        self.assertEqual(validator._top_value(fm, "name"), "attention")
        self.assertEqual(validator._top_value(fm, "default"), "opt-in")
        self.assertEqual(validator._top_value(fm, "experimental"), "true")
        self.assertEqual(validator._modes_values(fm), {"diff", "full"})
        self.assertIn("  project_claude_md: yes", fm)

    def test_registry_and_explicit_selection_on_both_legacy_paths(self):
        for filename, cell in [("SKILL.md", "Attention"), ("unattended.md", "attention.md")]:
            with self.subTest(path=filename):
                text = (ROOT / filename).read_text()
                rows, problems = validator.parse_rows(text, filename)
                self.assertEqual(problems, [])
                attention = [row for row in rows if row[0] == "attention"]
                self.assertEqual(len(attention), 1)
                self.assertEqual(attention[0][1], cell)
                self.assertEqual(attention[0][2], "sonnet")
                table_rows = [line for line in text.splitlines()
                              if line.strip().startswith("| attention |")]
                self.assertEqual(len(table_rows), 1)
                cells = [value.strip().strip("`")
                         for value in table_rows[0].strip().strip("|").split("|")]
                file_column = 2 if filename == "SKILL.md" else 1
                self.assertEqual(cells[file_column], "attention.md")
                self.assertIn("Attention is experimental and opt-in", text)
                self.assertIn("attention.md", text)
                self.assertIn("excluded from", text)

    def test_mandate_has_two_tests_evidence_and_protected_constraints(self):
        text = (ROOT / "personas/attention.md").read_text()
        for required in ["Equally good result, less burden", "Worthwhile quality/burden tradeoff",
                         "notice, read, choose, remember, configure, copy, switch, monitor, re-enter, and maintain",
                         "disengage", "stated user purpose", "workflow evidence", "retained", "lost",
                         "Safety, privacy, consent, irreversible-action approval, and accuracy requirements",
                         "necessary authorization", "Do not diagnose", "ADHD", "Abstain",
                         "unmeasured hypothesis", "User", "Naive", "Coach", "Hypercritical", "Pennypincher"]:
            with self.subTest(clause=required):
                self.assertIn(required, text)

    def test_examples_and_existing_finding_shape(self):
        text = (ROOT / "personas/attention.md").read_text()
        self.assertGreaterEqual(text.count("**Flag this**"), 3)
        self.assertGreaterEqual(text.count("**Don't flag this**"), 4)
        self.assertIn("#### Important (should fix)", text)
        self.assertIn("#### Noted (awareness only)", text)
        self.assertIn("`[moderate]`", text)
        self.assertIn("No findings", text)
        self.assertIn("existing finding schema", text)
        for heading in ["Your goal", "Your perspective", "What you're looking for",
                        "Examples", "How to work", "What you are NOT looking for"]:
            self.assertIn("## " + heading, text)


if __name__ == "__main__":
    unittest.main()
