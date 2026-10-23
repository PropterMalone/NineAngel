"""Selection questions follow actual ambiguity, never a numeric exclusion threshold."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BatteryPolicy(unittest.TestCase):
    def test_selection_asks_only_for_actual_ambiguity(self):
        skill = (ROOT / 'SKILL.md').read_text()
        section = skill.split('### Decision')[1].split('### Explicit override flags')[0]
        self.assertIn('regardless of count', section)
        self.assertIn('Actually ambiguous signals', section)
        self.assertNotIn('3+ candidate-drops', section)
        for choice in ('Recommended', 'Run all', 'Custom'):
            self.assertIn(choice, section)

    def test_artifact_class_and_override_consent_boundaries_remain(self):
        skill = (ROOT / 'SKILL.md').read_text()
        self.assertIn('out-of-class', skill)
        self.assertIn('Named personas', skill)
        self.assertIn('experimental: true', skill)
        self.assertIn('orgpolicy', skill)
        self.assertIn('AskUserQuestion', skill)
        unattended = (ROOT / 'unattended.md').read_text()
        self.assertIn('Unattended mode never asks', unattended)
        self.assertIn('all consent/lockout gates', unattended)

    def test_documentation_has_no_count_only_prompt(self):
        readme = (ROOT / 'README.md').read_text()
        design = (ROOT / 'DESIGN.md').read_text()
        self.assertNotIn('drop more than 2', readme)
        self.assertNotIn('3+ candidate-drops', design)
        self.assertIn('regardless of how many', readme)
        self.assertIn('Count alone is not ambiguity', design)


if __name__ == '__main__':
    unittest.main()
