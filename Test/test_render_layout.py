import unittest
import json
import tempfile
from pathlib import Path

from PS4HTML.engine import ProofEngine
from PS4HTML.make import load_project_info
from PS4HTML.page import Page, build_label_index, load_page
from PS4HTML.project import PS4HTMLError
from PS4HTML.render_rules import validate_record, validate_rules, validate_template, render_rule
from PS4HTML.Rules.proof_text import ProofTextRenderer
from PS4HTML.Rules.references import render_references
from PS4HTML.Rules.strategy import rule_strategy


GOAL = {"_goal_": {"kind": "const", "name": "True"}}


def plain(rule_id, label):
    return {"_ruleId": rule_id}


class RenderLayoutTest(unittest.TestCase):
    def setUp(self):
        self.rules = {
            "leaf": {"ruleId": "leaf", "strategy": False, "fields": {
                "template": [{"lang": "zh", "tag": "子步骤", "content": "<安全>"}]}},
            "split": {"ruleId": "split", "strategy": True, "fields": {
                "color": ["#123456", None, "#abcdef"],
                "template": [{"lang": "zh", "tag": "分类", "introducer": {
                    "tag": "引言", "content": "关于 ${subject}"}, "cases": [
                        {"name": "right", "tag": "右", "title": "第二支", "introducer": {
                            "tag": "分支引言", "content": "${subject}"}},
                        {"name": "left", "tag": "左", "title": "第一支"}]},
                    {"lang": "en", "tag": "Cases", "cases": [
                        {"name": "right", "tag": "Right", "title": "Second"},
                        {"name": "left", "tag": "Left", "title": "First"}]}]}},
        }
        self.branches = [
            {"name": "left", "proof": [GOAL, plain("leaf", "left")]},
            {"name": "right", "proof": [GOAL, plain("leaf", "right")]},
        ]

    def test_project_metadata_is_separate_from_pages_and_unique_per_site(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            projects = root / "projects"
            projects.mkdir()
            (projects / "First.json").write_text(json.dumps({
                "module": "First", "ProjectInfo": {"title": "One"}}))
            (projects / "Second.json").write_text(json.dumps({
                "module": "Second", "ProjectInfo": {"title": "Two"}}))
            page_path = root / "page.json"
            page_path.write_text(json.dumps({"module": "First", "source": "First.lean", "components": []}))
            self.assertEqual(load_page(page_path, root).module, "First")
            self.assertEqual(load_project_info(root, {"First"})["title"], "One")
            project = json.loads((root / "project.json").read_text())
            self.assertEqual(project, {"schemaVersion": "0.0.0", "ProjectInfo": {"title": "One"}})
            with self.assertRaisesRegex(PS4HTMLError, "project_info may only be configured once"):
                load_project_info(root, {"First", "Second"})

    def test_theorem_links_use_fully_qualified_declaration_names(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            page = Page(root / "Library.json", "Paper.Library", root / "Library.lean", [
                {"data": {"theorem": {"value": {
                    "name": "A display title", "proof": ".ProofScript/proofs/Paper/Library/result.json",
                    "sorryAx": False}}}, "source": {"start": 0}},
            ])
            labels = build_label_index([page])
            self.assertEqual(labels[("theorem", "Paper.Library.result")].anchor,
                             "theorem-Paper.Library.result")
            reference = {"kind": "theorem", "label": "Paper.Library.result"}
            text = ProofTextRenderer(labels, root, Path("Paper/Main.html"))._reference(reference)
            self.assertIn("Library.html#theorem-Paper.Library.result", text)
            references = render_references([{"name": "Paper.Library.result", "info": {
                "name": "A display title", "project": {"title": "A project",
                    "description": "A description", "base_url": "https://example.org"}}}],
                labels, root, Path("Paper/Main.html"), "en")
            self.assertIn("Library.html#theorem-Paper.Library.result", references)
            self.assertIn("A description", references)
            self.assertIn("https://example.org", references)

    def test_order_introducers_escaping_and_palette(self):
        step = {"_ruleId": "split", "subject": "<P>",
                "branches": self.branches}
        rendered = ProofEngine([GOAL, step], rules=self.rules).render([GOAL, step])
        self.assertLess(rendered.index("第二支"), rendered.index("第一支"))
        self.assertIn("关于 &lt;P&gt;", rendered)
        self.assertIn("分支引言", rendered)
        self.assertIn('class="step-block introducer"', rendered)
        self.assertIn("&lt;安全&gt;", rendered)
        self.assertIn("--rule-tag-color: #123456", rendered)
        self.assertIn("--rule-tag-border: var(--cases-color-light)", rendered)
        self.assertIn("--rule-tag-color: var(--text-color)", rendered)
        self.assertIn("--rule-left-border: var(--border-color)", rendered)
        self.assertIn("--rule-background: #abcdef", rendered)

    def test_inline_renders_proof_without_details(self):
        step = {"_ruleId": "split",
                "branches": [{"name": "proof", "proof": [GOAL, plain("leaf", "leaf")]}]}
        # Each language's fixed case contract must be met; use a single-language rule here.
        rule = {**self.rules["split"], "fields": {"template": [{
            "lang": "en", "tag": "Cases", "inline": True,
            "cases": [{"name": "proof", "tag": "", "title": ""}]}]}}
        proof = ProofEngine([GOAL, step], language="en", rules={**self.rules, "split": rule})
        rendered = proof.render([GOAL, step])
        self.assertIn("Cases", rendered)
        self.assertIn("子步骤", rendered)
        self.assertNotIn("<details", rendered)

    def test_hidden_strategy_does_not_render_or_descend(self):
        rule = {**self.rules["split"], "fields": {"display": False,
            "renderer": "not-called"}}
        step = {"_ruleId": "split", "branches": [
            {"name": "proof", "proof": [GOAL, plain("missing", "missing")]}]}
        proof = ProofEngine([GOAL, step], rules={**self.rules, "split": rule})
        self.assertEqual(proof.render([GOAL, step]), "")
        self.assertEqual(render_rule(rule, step, GOAL, {}, proof, (), 1), "")

    def test_missing_extra_and_duplicate_cases_fail(self):
        step = {"_ruleId": "split", "subject": "P",
                "branches": self.branches[:1]}
        with self.assertRaisesRegex(ValueError, "branches do not match"):
            validate_record(self.rules["split"], step, GOAL)
        step["branches"] = self.branches + [{"name": "other", "proof": [GOAL, plain("leaf", "x")]}]
        with self.assertRaisesRegex(ValueError, "branches do not match"):
            validate_record(self.rules["split"], step, GOAL)
        step["branches"] = self.branches + [self.branches[0]]
        with self.assertRaisesRegex(ValueError, "Duplicate recorded"):
            validate_record(self.rules["split"], step, GOAL)

    def test_missing_strategy_info_field_fails(self):
        step = {"_ruleId": "split", "branches": self.branches}
        with self.assertRaisesRegex(ValueError, "Missing recorded template field 'subject'"):
            validate_record(self.rules["split"], step, GOAL)

    def test_template_rejects_missing_cases_and_inline_misuse(self):
        with self.assertRaisesRegex(ValueError, "Invalid template fields"):
            validate_template([{"lang": "zh", "tag": "Missing"}], True)
        with self.assertRaisesRegex(ValueError, "Invalid template cases"):
            validate_template([{"lang": "zh", "tag": "Many", "inline": True, "cases": [
                {"name": "left", "tag": "", "title": ""},
                {"name": "right", "tag": "", "title": ""}]}], True)
        with self.assertRaisesRegex(ValueError, "Inline case"):
            validate_template([{"lang": "zh", "tag": "Nonempty", "inline": True, "cases": [
                {"name": "proof", "tag": "Discarded", "title": ""}]}], True)

    def test_unknown_renderer_fails(self):
        document = {"schemaVersion": "0.0.0", "module": "Test", "imports": [],
                    "rules": [{"ruleId": "unknown", "strategy": False,
                               "fields": {"renderer": "unknown"}}]}
        with self.assertRaisesRegex(ValueError, "Unknown renderer"):
            validate_rules(document, "Test")

    def test_missing_rule_or_unresolvable_expression_fails(self):
        with self.assertRaisesRegex(ValueError, "No rendering rule"):
            ProofEngine([GOAL, plain("missing", "missing")], rules=self.rules).render(
                [GOAL, plain("missing", "missing")])
        rule = {"ruleId": "leaf", "strategy": False, "fields": {
            "template": [{"lang": "zh", "tag": "引用", "content": "${expression}"}]}}
        record = {**plain("leaf", "leaf"), "expression": {"kind": "const", "name": "True"}}
        proof = ProofEngine([GOAL, record], rules={"leaf": rule})
        with self.assertRaisesRegex(ValueError, "recorded expression reference"):
            proof.render([GOAL, record])

    def test_flat_snapshots_render_independently_and_null_is_visible(self):
        rule = {"ruleId": "leaf", "strategy": False, "fields": {
            "template": [{"lang": "zh", "tag": "变化",
                          "content": "${arg_before} → ${arg_after}"}]}}
        record = {**plain("leaf", "leaf"), "arg_before": "旧值", "arg_after": "新值"}
        proof = ProofEngine([GOAL, record], rules={"leaf": rule})
        rendered = proof.render([GOAL, record])
        self.assertIn("旧值 → 新值", rendered)
        record["arg_after"] = None
        self.assertIn("旧值 → —", proof.render([GOAL, record]))
        del record["arg_after"]
        with self.assertRaisesRegex(ValueError, "Missing recorded template field 'arg_after'"):
            proof.render([GOAL, record])

    def test_color_rejects_css_injection(self):
        document = {"schemaVersion": "0.0.0", "module": "Test", "imports": [],
                    "rules": [{"ruleId": "leaf", "strategy": False, "fields": {
                        "color": ["red; position:fixed", None, None],
                        "template": [{"lang": "zh", "tag": "标签", "content": ""}]}}]}
        with self.assertRaisesRegex(ValueError, "Invalid color"):
            validate_rules(document, "Test")

    def test_hidden_step_between_visible_steps_leaves_no_blank_block(self):
        rules = {**self.rules, "hidden": {"ruleId": "hidden", "strategy": False,
            "fields": {"display": False, "template": [{"lang": "zh", "tag": "秘密",
                "content": "不应出现"}]}}}
        steps = [GOAL, plain("leaf", "first"), GOAL, plain("hidden", "skip"),
                 GOAL, plain("leaf", "last")]
        rendered = ProofEngine(steps, rules=rules).render(steps)
        self.assertEqual(rendered.count('class="step-block '), 2)
        self.assertNotIn("秘密", rendered)

    def test_legacy_triple_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Invalid template entry"):
            validate_template([["zh", "old", ""]], False)

    def test_dynamic_renderer_uses_explicit_language_and_recorded_order(self):
        step = {"name": "split_and!", "_ruleId": "ProofScript.Script.Basic.split_and!",
                "branches": self.branches}
        proof = ProofEngine([GOAL, step], rules=self.rules)
        rendered = rule_strategy(step, GOAL, {}, proof, language="en", index=1)
        self.assertIn("To split the conjunction recursively,", rendered)
        self.assertLess(rendered.index("Subgoal I,"), rendered.index("Subgoal II,"))
        self.assertEqual(rendered.count('class="goal-block"'), 2)

    def test_unconfigured_strategy_has_plain_fallback(self):
        step = {"name": "custom", "_ruleId": "Test.custom", "branches": self.branches}
        proof = ProofEngine([GOAL, step], rules=self.rules)
        rendered = rule_strategy(step, GOAL, {}, proof, language="zh", index=1)
        self.assertIn("custom", rendered)
        self.assertIn("left", rendered)
        self.assertIn("right", rendered)


if __name__ == "__main__":
    unittest.main()
