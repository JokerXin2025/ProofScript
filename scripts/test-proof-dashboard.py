"""Static ordinary-step dashboards honor recorded root ownership and missing data."""

from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from PS4HTML.engine import ProofEngine
from PS4HTML.render_rules import validate_record
from PS4HTML.schema import validate_document


def expr(ref):
    return {"$ref": ref}


def fixture(step, board=(), kind="tactic", language="zh"):
    roots = []
    for key, value in step.items():
        if key.startswith("$context_") and isinstance(value, dict):
            roots.extend(["proof", 0, key, name] for name in value)
        elif key.startswith("$goal_") and value is not None:
            roots.append(["proof", 0, key])
        elif key in {item["value"] for item in board} and isinstance(value, dict) and "$ref" in value:
            roots.append(["proof", 0, key])
    doc = {"module": "Test.Dashboard", "code": "",
           "statement": {"parameters": [], "conditions": [], "conclusion": expr("e0")},
           "expressions": {f"e{i}": {"kind": "lit", "lit": {"kind": "literal.nat", "value": i}}
                           for i in range(5)},
           "expressionRoots": sorted(roots + [["statement", "conclusion"]],
                                     key=lambda path: tuple((0, x) if isinstance(x, str) else (1, x) for x in path)),
           "proof": [step]}
    # Only reachable expression nodes may appear in a proof graph.
    used = {"e0"} | {value["$ref"] for key, value in step.items() if isinstance(value, dict)
                       for value in ([value] if "$ref" in value else value.values())
                       if isinstance(value, dict) and "$ref" in value}
    from PS4HTML.schema import json_path
    ordered = []
    for root in doc["expressionRoots"]:
        ref = json_path(doc, root)["$ref"]
        if ref not in ordered:
            ordered.append(ref)
    remap = {ref: f"e{index}" for index, ref in enumerate(ordered)}
    doc["expressions"] = {remap[key]: value for key, value in doc["expressions"].items() if key in used}
    for root in doc["expressionRoots"]:
        json_path(doc, root)["$ref"] = remap[json_path(doc, root)["$ref"]]
    resolver = validate_document(doc)
    rule = {"ruleId": "Test.dashboard", "kind": kind,
             "fields": {"renderer": "default", "template": [{"lang": "zh", "tag": "证明", "content": ""}],
                       "board": list(board)}}
    engine = ProofEngine([], rules={"Test.dashboard": rule}, expression_resolver=resolver, language=language)
    return doc, resolver, rule, engine


class DashboardTests(unittest.TestCase):
    def test_context_diff_completed_goal_and_board_order(self):
        board = [{"name": "字段", "value": "foo.bar"}, {"name": "字段", "value": "missing"}]
        step = {"$ruleId": "Test.dashboard", "$context_before": {"h": expr("e1"), "gone": expr("e2")},
                "$context_after": {"h": expr("e1"), "new": expr("e3")},
                "$goal_before": expr("e4"), "$goal_after": None, "foo.bar": expr("e1")}
        _, _, _, engine = fixture(step, board)
        page = engine.render([step])
        self.assertIn("原状态", page)
        self.assertIn("新状态", page)
        self.assertIn('class="proof-step  has-dashboard"', page)
        self.assertIn('aria-expanded="false"', page)
        self.assertIn('class="proof-dashboard-reveal"', page)
        self.assertIn('aria-hidden="true" inert', page)
        self.assertIn('<span class="proof-dashboard-goal-mark proof-dashboard-complete"><i class="codicon codicon-check" aria-hidden="true"></i></span>目标已完成', page)
        self.assertIn('<span class="proof-dashboard-goal-mark">⊢</span>', page)
        self.assertIn('class="proof-dashboard-goal-mark proof-dashboard-complete"', page)
        self.assertIn('class="proof-dashboard-marker removed" aria-label="删除">－</span>', page)
        self.assertIn('class="proof-dashboard-marker added" aria-label="新增">＋</span>', page)
        self.assertIn('class="proof-dashboard-context-row" role="cell"', page)
        self.assertEqual(page.count('class="proof-dashboard-marker" aria-hidden="true"'), 2)
        self.assertEqual(page.count('class="proof-dashboard-context-row proof-dashboard-blank" role="cell" aria-hidden="true"'), 2)
        self.assertNotIn('class="proof-dashboard-goal changed"', page)
        self.assertEqual(page.count('<div class="proof-dashboard-field">'), 2)
        self.assertIn("未记录", page)

    def test_missing_context_and_goals_and_empty_board(self):
        step = {"$ruleId": "Test.dashboard"}
        _, _, _, engine = fixture(step)
        page = engine.render([step])
        self.assertEqual(page.count('class="codicon codicon-check"'), 2)
        self.assertNotIn('class="proof-dashboard-context"', page)
        self.assertNotIn('class="proof-dashboard-board"', page)

    def test_state_headings_are_translated_with_proof_language(self):
        step = {"$ruleId": "Test.dashboard"}
        _, _, _, engine = fixture(step, language="en")
        page = engine.render([step])
        self.assertIn('<h3 role="columnheader">Original state</h3>', page)
        self.assertIn('<h3 role="columnheader">New state</h3>', page)
        self.assertNotIn('>原状态</h3>', page)

    def test_one_sided_context_is_not_marked_added(self):
        step = {"$ruleId": "Test.dashboard", "$context_after": {"h": expr("e1")}}
        _, _, _, engine = fixture(step)
        page = engine.render([step])
        self.assertIn('class="proof-dashboard-context-row" role="cell"', page)
        self.assertNotIn('class="proof-dashboard-marker added"', page)
        self.assertNotIn('class="proof-dashboard-marker removed"', page)
        self.assertIn('class="proof-dashboard-context-row proof-dashboard-blank"', page)

    def test_contexts_pair_by_name_and_goal_follows_aligned_rows(self):
        step = {"$ruleId": "Test.dashboard", "$context_before": {"first": expr("e1"), "shared": expr("e2")},
                "$context_after": {"shared": expr("e3"), "last": expr("e4")},
                "$goal_before": expr("e2"), "$goal_after": expr("e3")}
        _, _, _, engine = fixture(step)
        page = engine.render([step])
        pairs = re.findall(r'<div class="proof-dashboard-pair" role="row">(.*?)</div></div>', page)
        self.assertEqual(len(pairs), 3)
        self.assertIn('proof-dashboard-name">first</span>', pairs[0])
        self.assertIn('proof-dashboard-blank', pairs[0])
        self.assertEqual(pairs[1].count('proof-dashboard-name">shared</span>'), 2)
        self.assertIn('proof-dashboard-blank', pairs[2])
        self.assertIn('proof-dashboard-name">last</span>', pairs[2])
        self.assertIn('class="proof-dashboard-pair proof-dashboard-goals"', page)

    def test_invalid_context_and_unregistered_roots(self):
        step = {"$ruleId": "Test.dashboard", "$context_before": {"h": expr("e1")}}
        _, resolver, rule, _ = fixture(step)
        with self.assertRaisesRegex(Exception, "expressionRoots"):
            resolver.roots.remove(("proof", 0, "$context_before", "h"))
            validate_record(rule, step, resolver=resolver, path=("proof", 0))
        with self.assertRaisesRegex(ValueError, "Invalid dashboard context"):
            validate_record(rule, {"$ruleId": "Test.dashboard", "$context_before": None})

    def test_metadata_does_not_acquire_dashboard(self):
        step = {"$ruleId": "Test.dashboard"}
        _, _, _, engine = fixture(step, kind="metadata")
        self.assertNotIn('class="proof-dashboard"', engine.render([step]))
        self.assertNotIn('aria-expanded="false"', engine.render([step]))


if __name__ == "__main__":
    unittest.main()
