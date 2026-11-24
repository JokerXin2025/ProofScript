"""The frozen board wire format preserves order and duplicate display names."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from PS4HTML.render_rules import validate_record, validate_rules
from PS4HTML.Rules.calc import rule_calc
from PS4HTML.Rules.infer import rule_infer
from PS4HTML.Rules.media import render_svg
from PS4HTML.Rules.admit import rule_admit
from PS4HTML.engine import ProofEngine


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
        plain = lambda value: {"kind": "plain", "value": value}
        step = {"metadata_title": plain("Example"), "metadata_label": plain("null"),
                "metadata_extra_names": {"kind": "array", "value": []},
                "metadata_extra_values": {"kind": "array", "value": []},
                "code": plain('<svg xmlns="http://www.w3.org/2000/svg"/>')}
        validate_record(rule, step)
        validate_record(rule, {**step, "source_language": plain("latex"), "source_code": plain("P")})
        for extra in ({"source_language": plain("latex")},
                      {"source_code": plain("P")},
                      {"source_language": plain(1), "source_code": plain("P")}):
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, "Invalid recorded svg fields"):
                validate_record(rule, {**step, **extra})

    def test_calc_and_infer_allow_only_hole_proof_slots(self):
        expression = {"kind": "expression", "value": {"$ref": "e0"}}
        column = lambda *items: {"kind": "array", "value": list(items)}
        for renderer in ("calc", "infer"):
            rule = {"kind": "tactic", "fields": {"renderer": renderer}}
            step = {"init": expression, "chain_rhs": column(expression),
                    "chain_proof": column({"kind": "plain", "value": "hole"})}
            if renderer == "calc":
                step["chain_relation"] = column(expression)
            with self.subTest(renderer=renderer):
                validate_record(rule, step)
                with self.assertRaisesRegex(ValueError, "proof state"):
                    validate_record(rule, {**step, "chain_proof": column({"kind": "plain", "value": "null"})})
                with self.assertRaisesRegex(ValueError, "chain"):
                    validate_record(rule, {**step, "chain_rhs": column()})

    def test_hidden_special_renderers_still_validate_fields(self):
        expression = {"kind": "expression", "value": {"$ref": "e0"}}
        column = lambda *items: {"kind": "array", "value": list(items)}
        for renderer in ("calc", "infer"):
            rule = {"kind": "tactic", "fields": {"renderer": renderer, "display": False}}
            step = {"init": expression, "chain_rhs": column(expression),
                    "chain_proof": column({"kind": "plain", "value": "hole"})}
            if renderer == "calc":
                step["chain_relation"] = column(expression)
            validate_record(rule, step)
            with self.subTest(renderer=renderer), self.assertRaisesRegex(ValueError, "chain"):
                validate_record(rule, {**step, "chain_proof": column()})
        svg_rule = {"kind": "metadata", "fields": {"renderer": "svg", "display": False}}
        with self.assertRaisesRegex(ValueError, "Missing recorded svg field"):
            validate_record(svg_rule, {})
        hidden_strategy = {"kind": "strategy", "fields": {"renderer": "svg", "display": False}}
        with self.assertRaisesRegex(ValueError, "Missing recorded svg field"):
            validate_record(hidden_strategy, {"$branches": []})

    def test_special_renderers_reject_truncated_columns_before_zip(self):
        class Proof:
            pass

        proof = Proof()
        for renderer, value in (
                (rule_calc, {"init": "x", "chain_relation": ["r"], "chain_rhs": ["y", "z"],
                             "chain_proof": ["hole"]}),
                (rule_infer, {"init": "x", "chain_rhs": ["y", "z"], "chain_proof": ["hole"]})):
            with self.subTest(renderer=renderer.__name__), self.assertRaisesRegex(ValueError, "aligned"):
                renderer(value, proof, language="en")
        with self.assertRaisesRegex(ValueError, "aligned"):
            render_svg({"metadata_extra_names": ["a"], "metadata_extra_values": [],
                        "metadata_title": "title", "metadata_label": "null", "code": ""},
                       proof, language="en")

    def test_aligned_special_renderers_keep_every_row_and_svg_metadata(self):
        class Proof:
            diagnostics = []

            def tex(self, value):
                return value

            def render_relation(self, value):
                return value

        proof = Proof()
        calc = {"init": "x", "chain_relation": ["=", "="],
                "chain_rhs": ["middle", "last"], "chain_proof": ["hole", "proof"]}
        infer = {"init": "x", "chain_rhs": ["middle", "last"],
                 "chain_proof": ["proof", "hole"]}
        for renderer, value in ((rule_calc, calc), (rule_infer, infer)):
            rendered = renderer(value, proof, language="en")
            with self.subTest(renderer=renderer.__name__):
                self.assertIn("middle", rendered)
                self.assertIn("last", rendered)
        media = {"metadata_title": "<figure>", "metadata_label": "null",
                 "metadata_extra_names": ["key"], "metadata_extra_values": ["<value>"],
                 "code": '<svg xmlns="http://www.w3.org/2000/svg"/>'}
        rendered = render_svg(media, proof, language="en")
        self.assertIn("&lt;figure&gt;", rendered)
        self.assertIn("&lt;value&gt;", rendered)

    def test_hidden_strategy_still_validates_branch_structure(self):
        rule = {"kind": "strategy", "fields": {"renderer": "default", "display": False,
                                               "template": []}}
        with self.assertRaisesRegex(ValueError, "Invalid recorded strategy branches"):
            validate_record(rule, {"$branches": []})
        validate_record(rule, {"$branches": [{"name": "case", "proof": []}]})

    def test_dynamic_strategy_indices_shadow_recorded_fields_only_in_cases(self):
        rule = {"kind": "strategy", "fields": {"renderer": "default", "template": [{
            "lang": "zh", "tag": "动态", "case": {"tag": "分支 ${index}",
                "title": "序号 ${index'}"}}]}}
        step = {"$branches": [{"name": "first", "proof": []}, {"name": "second", "proof": []}],
                "index": {"kind": "plain", "value": "recorder value"},
                "index'": {"kind": "plain", "value": "recorder value"}}
        validate_record(rule, step)
        validate_record(rule, {key: value for key, value in step.items() if key not in ("index", "index'")})
        rule["fields"]["template"][0]["tag"] = "顶层 ${index}"
        with self.assertRaisesRegex(ValueError, "Missing recorded template field"):
            validate_record(rule, {"$branches": step["$branches"]})

    def test_dynamic_strategy_indices_render_from_branch_position(self):
        rule = {"ruleId": "Test.dynamic", "kind": "strategy", "fields": {"renderer": "default",
            "template": [{"lang": "zh", "tag": "顶层 ${index}", "case": {
                "tag": "分支 ${index}", "title": "序号 ${index'}"}}]}}
        step = {"$ruleId": "Test.dynamic", "index": {"kind": "plain", "value": "top"},
                "$branches": [{"name": "left", "proof": [{"$ruleId": "Test.hidden"}]},
                              {"name": "right", "proof": [{"$ruleId": "Test.hidden"}]}]}
        hidden = {"ruleId": "Test.hidden", "kind": "tactic", "fields": {
            "renderer": "default", "display": False, "template": []}}
        rendered = ProofEngine([], language="zh", rules={"Test.dynamic": rule,
                                                          "Test.hidden": hidden}).render([step])
        self.assertIn("顶层 top", rendered)
        self.assertNotIn("分支 top", rendered)
        for text in ("分支  $0$", "序号  $1$", "分支  $1$", "序号  $2$"):
            self.assertIn(text, rendered)

    def test_dynamic_case_introducer_indices_and_static_case_names(self):
        rule = {"kind": "strategy", "fields": {"renderer": "default", "template": [{
            "lang": "zh", "tag": "动态", "case": {"tag": "分支 ${index}", "title": "",
                "introducer": {"tag": "序号 ${index'}", "content": "数据 ${value}"}}}]}}
        validate_rules({"module": "Test.ScriptBoard", "imports": [],
                        "rules": [{"ruleId": "Test.dynamic", **rule}]}, "Test.ScriptBoard")
        step = {"$branches": [{"name": "a", "proof": []}, {"name": "b", "proof": []}],
                "value": {"kind": "plain", "value": 3}}
        validate_record(rule, step)
        with self.assertRaisesRegex(ValueError, "Missing recorded template field"):
            validate_record(rule, {"$branches": step["$branches"]})
        rule["fields"]["template"] = [{"lang": "zh", "tag": "静态", "cases": [
            {"name": "a", "tag": "一", "title": ""}]}]
        with self.assertRaisesRegex(ValueError, "Strategy branches do not match"):
            validate_record(rule, step)


if __name__ == "__main__":
    unittest.main()
