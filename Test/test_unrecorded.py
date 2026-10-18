"""Run with PYTHONPATH=tools/ps4html python3 -m unittest Test/test_unrecorded.py."""

import unittest

from PS4HTML.engine import ProofEngine
from PS4HTML.recording import UNRECORDED_RULE_ID


class UnrecordedRenderingTest(unittest.TestCase):
    def test_placeholder_without_rendering_rule(self):
        steps = [{"_ruleId": UNRECORDED_RULE_ID, "name": '<script & "name">'}]
        rendered = ProofEngine(steps).render(steps)
        self.assertIn('class="proof-step unknown"', rendered)
        self.assertIn("未导出数据", rendered)
        self.assertIn("&lt;script &amp; &quot;name&quot;&gt;", rendered)
        self.assertNotIn('<script & "name">', rendered)

    def test_english_placeholder(self):
        steps = [{"_ruleId": UNRECORDED_RULE_ID, "name": "unavailable"}]
        rendered = ProofEngine(steps, language="en").render(steps)
        self.assertIn("Data not exported", rendered)

    def test_reserved_id_cannot_be_hidden_by_a_rule(self):
        steps = [{"_ruleId": UNRECORDED_RULE_ID, "name": "unavailable"}]
        rules = {UNRECORDED_RULE_ID: {"fields": {"display": False}}}
        self.assertIn("未导出数据", ProofEngine(steps, rules=rules).render(steps))

    def test_nested_branches_keep_their_contract_paths_and_continuation(self):
        steps = [{"_ruleId": UNRECORDED_RULE_ID, "name": "outer", "branches": [
            {"name": "<proof>", "proof": [
                {"_ruleId": UNRECORDED_RULE_ID, "name": "inner", "branches": [
                    {"name": "leaf", "proof": [{"_ruleId": "Demo.finish"}]}]},
                {"_ruleId": "Demo.finish"}]}]}, {"_ruleId": "Demo.finish"}]
        rule = {"ruleId": "Demo.finish", "strategy": False, "recordedFields": [], "fields": {
            "template": [{"lang": "zh", "tag": "done", "content": "completed"}]}}
        step_rules = {
            ("proof", 0, "branches", 0, "proof", 0, "branches", 0, "proof", 0): rule,
            ("proof", 0, "branches", 0, "proof", 1): rule,
            ("proof", 1): rule,
        }
        rendered = ProofEngine(steps, step_rules=step_rules).render(steps)
        self.assertEqual(rendered.count("未导出数据"), 2)
        self.assertEqual(rendered.count("completed"), 3)
        self.assertIn("&lt;proof&gt;", rendered)
        self.assertLess(rendered.index("outer"), rendered.index("inner"))

    def test_other_missing_rules_still_fail(self):
        steps = [{"_ruleId": "Demo.unknown"}]
        with self.assertRaisesRegex(ValueError, "No rendering rule"):
            ProofEngine(steps).render(steps)


if __name__ == "__main__":
    unittest.main()
