"""The frozen board wire format preserves order and duplicate display names."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from PS4HTML.render_rules import validate_record, validate_rules
from PS4HTML.Rules.admit import rule_admit


def document(board):
    return {"module": "Test.ScriptBoard", "imports": [],
            "rules": [{"ruleId": "Test.board", "kind": "tactic",
                        "fields": {"renderer": "default", "display": True,
                                  "template": [{"lang": "zh", "tag": "步骤", "content": ""}],
                                  "board": board}}]}


class ScriptBoardProtocolTest(unittest.TestCase):
    def test_default_renderer_rejects_old_none_value(self):
        rules = document([])
        rules["rules"][0]["fields"]["renderer"] = "none"
        with self.assertRaisesRegex(ValueError, "Unknown renderer 'none'"):
            validate_rules(rules, "Test.ScriptBoard")

    def test_admit_with_empty_reason_is_visible(self):
        rendered = rule_admit({"reason": ""}, None, language="zh")
        self.assertIn('class="proof-strategy admit"', rendered)
        self.assertNotIn("Silent Step", rendered)

    def test_duplicate_names_and_literal_dotted_keys(self):
        board = [{"name": "使用的假设", "value": "h"},
                 {"name": "使用的假设", "value": "foo.bar"}]
        rules = validate_rules(document(board), "Test.ScriptBoard")
        self.assertEqual(rules["Test.board"]["fields"]["board"], board)

    def test_invalid_board_entries(self):
        for board in ({"name": "h"}, [{"name": "h"}],
                      [{"name": "h", "value": 2}],
                      [{"name": "h", "value": "x", "extra": "y"}]):
            with self.subTest(board=board), self.assertRaisesRegex(ValueError, "Invalid board"):
                validate_rules(document(board), "Test.ScriptBoard")

    def test_svg_source_must_be_a_complete_optional_object(self):
        rule = {"kind": "metadata", "fields": {"renderer": "svg"}}
        step = {"metadata": {"title": "Example", "label": None, "extra": []},
                "code": '<svg xmlns="http://www.w3.org/2000/svg"/>'}
        validate_record(rule, step)
        validate_record(rule, {**step, "source": {"lang": "latex", "code": "P"}})
        for source in (None, "P", {"lang": "latex"}, {"lang": 1, "code": "P"}):
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, "Invalid recorded svg fields"):
                validate_record(rule, {**step, "source": source})

    def test_dynamic_strategy_indices_shadow_recorded_fields_only_in_cases(self):
        rule = {"kind": "strategy", "fields": {"renderer": "default", "template": [{
            "lang": "zh", "tag": "动态", "case": {"tag": "分支 ${index}",
                "title": "序号 ${index'}"}}]}}
        step = {"$branches": [{"name": "first", "proof": []}, {"name": "second", "proof": []}],
                "index": "recorder value", "index'": "recorder value"}
        validate_record(rule, step)
        validate_record(rule, {key: value for key, value in step.items() if key not in ("index", "index'")})
        rule["fields"]["template"][0]["tag"] = "顶层 ${index}"
        with self.assertRaisesRegex(ValueError, "Missing recorded template field"):
            validate_record(rule, {"$branches": step["$branches"]})

    def test_dynamic_case_introducer_indices_and_static_case_names(self):
        rule = {"kind": "strategy", "fields": {"renderer": "default", "template": [{
            "lang": "zh", "tag": "动态", "case": {"tag": "分支 ${index}", "title": "",
                "introducer": {"tag": "序号 ${index'}", "content": "数据 ${value}"}}}]}}
        validate_rules({"module": "Test.ScriptBoard", "imports": [],
                        "rules": [{"ruleId": "Test.dynamic", **rule}]}, "Test.ScriptBoard")
        step = {"$branches": [{"name": "a", "proof": []}, {"name": "b", "proof": []}], "value": 3}
        validate_record(rule, step)
        with self.assertRaisesRegex(ValueError, "Missing recorded template field"):
            validate_record(rule, {"$branches": step["$branches"]})
        rule["fields"]["template"] = [{"lang": "zh", "tag": "静态", "cases": [
            {"name": "a", "tag": "一", "title": ""}]}]
        with self.assertRaisesRegex(ValueError, "Strategy branches do not match"):
            validate_record(rule, step)


if __name__ == "__main__":
    unittest.main()
