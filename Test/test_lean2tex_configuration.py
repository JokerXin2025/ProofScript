import json
import re
import tempfile
import unittest
from pathlib import Path

from Lean2TeX.configuration import ConfigurationIndex
from Lean2TeX.core import Expr2TeX
from Lean2TeX.model import DisplayNode
from Lean2TeX.renderer import LayoutRenderer
from Lean2TeX.variable import VariableAllocator
from PS4HTML.engine import ProofEngine
from PS4HTML.make import _safe_module_name, _validate_render_inputs
from PS4HTML.project import PS4HTMLError


class ConfigurationTest(unittest.TestCase):
    def test_lake_module_names_accept_lean_quoted_and_apostrophe_segments(self):
        for name in ("Calculus_21.Limit.L'Hospital", "Calculus_21.Limit.«L'Hospital»",
                     "«Calculus_21».Limit.L'Hospital", "Example.«my module».Result"):
            with self.subTest(name=name):
                self.assertTrue(_safe_module_name(name))
        for name in ("", ".Example", "Example.", "Example..Result", "Example/../Result",
                     "Example\\Result", "Example.\x00Result", "Example.\nResult"):
            with self.subTest(name=name):
                self.assertFalse(_safe_module_name(name))

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def module(self, name, imports=(), events=()):
        path = Path(*name.split("."))
        manifest = self.root / "rendering" / "modules" / path.with_suffix(".json")
        event_file = self.root / "lean2tex" / "events" / path.with_suffix(".json")
        manifest.parent.mkdir(parents=True, exist_ok=True)
        event_file.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps({"schemaVersion": "0.0.0", "module": name, "imports": list(imports)}))
        event_file.write_text(json.dumps({"schema_version": "0.0.0", "module": name, "events": [
            {"sequence": i, "category": category, "target": target, "fields": fields}
            for i, (category, target, fields) in enumerate(events)]}))

    def effective(self, name):
        return ConfigurationIndex(self.root).effective(name)

    def test_relation_defaults_and_descendant_override(self):
        self.module("Base", events=[("definition", "LE.le", {"calc_symbol": "\\le"}),
                                    ("variable", "Real", {"default": "x", "names": ["x", "y"]})])
        self.module("Child", ["Base"], [("definition", "LE.le", {"calc_symbol": "\\leqslant"}),
                                         ("variable", "Real", {"names": ["a"]})])
        self.module("Proof", ["Child"])
        result = self.effective("Proof")
        self.assertEqual(result.registry.rel_symbol("LE.le"), "\\leqslant")
        style = result.registry.get("LE.le").styles[0]
        self.assertEqual(style.template, "#0\\leqslant #1")
        self.assertEqual((style.fixity, style.precedence, style.associativity), ("infix", 50, "none"))
        self.assertEqual(result.variables[0].var_names, ["a"])
        self.assertEqual(self.effective("Child").registry.rel_symbol("LE.le"), "\\le")

    def test_alias_unwrap_and_explicit_styles(self):
        styles = [{"template": "#0=#1", "fixity": "infix", "precedence": 45}]
        self.module("Base", events=[("definition", "Eq", {"calc_symbol": "=", "styles": styles}),
                                    ("definition", "Alias", {"alias": "Eq"}),
                                    ("definition", "Wrap", {"unwrap": 0})])
        self.module("Proof", ["Base"])
        reg = self.effective("Proof").registry
        self.assertEqual(reg.get("Alias").styles[0].precedence, 45)
        self.assertEqual(reg.unwraps["Wrap"].argument, 0)
        self.assertEqual(reg.relations["Eq"], "=")
        self.assertEqual(reg.rel_symbol("Alias"), "=")

    def test_styles_preserve_same_name_order_and_phrases_merge(self):
        styles = [{"name": "formula", "template": "@0@@0", "binders": [[0, 1]]},
                  {"name": "formula", "template": "#0"}]
        self.module("Base", events=[("definition", "Deriv", {"arguments": [0], "styles": styles}),
                                    ("phrase", "forall", {"template": [{"lang": "zh", "content": "${body}"},
                                                                       {"lang": "en", "content": "${binder}"}]})])
        self.module("Child", ["Base"], [("phrase", "forall", {"template": [
            {"lang": "zh", "content": "${type}"}]})])
        self.module("Proof", ["Child"])
        reg = self.effective("Proof").registry
        self.assertEqual([style.template for style in reg.get("Deriv").styles], ["@0@@0", "#0"])
        self.assertEqual(reg.get("Deriv").styles[0].binders, {0: 1})
        self.assertEqual(reg.phrase("forall", "zh"), "${type}")
        self.assertEqual(reg.phrase("forall", "en"), "${binder}")

    def test_conflicting_independent_imports_and_modes(self):
        self.module("A", events=[("definition", "Eq", {"alias": "Target"})])
        self.module("B", events=[("definition", "Eq", {"unwrap": 0})])
        self.module("Proof", ["A", "B"])
        with self.assertRaisesRegex(ValueError, "conflicting.*alias/unwrap"):
            self.effective("Proof")

    def test_mode_switch_requires_explicit_clear(self):
        self.module("Base", events=[("definition", "Eq", {"unwrap": 0}),
                                    ("definition", "Target", {"calc_symbol": "="})])
        self.module("Child", ["Base"], [("definition", "Eq", {"unwrap": None, "alias": "Target"})])
        self.module("Proof", ["Child"])
        self.assertEqual(self.effective("Proof").registry.resolve_alias("Eq"), "Target")
        self.assertIn("Eq", self.effective("Child").registry.unwraps)

    def test_invalid_alias_cycle_and_missing_target(self):
        self.module("Base", events=[("definition", "A", {"alias": "B"}),
                                    ("definition", "B", {"alias": "A"})])
        self.module("Proof", ["Base"])
        with self.assertRaisesRegex(ValueError, "alias cycle"):
            self.effective("Proof")

    def test_alias_target_without_usable_rule(self):
        self.module("Base", events=[("definition", "A", {"alias": "B"}),
                                    ("definition", "B", {"calc_symbol": None})])
        self.module("Proof", ["Base"])
        with self.assertRaisesRegex(ValueError, "missing styles or calc_symbol"):
            self.effective("Proof")

    def test_invalid_generated_arity_and_template(self):
        self.module("Base", events=[("definition", "Eq", {"calc_symbol": "=", "arguments": [0]})])
        self.module("Proof", ["Base"])
        with self.assertRaisesRegex(ValueError, "requires two selected arguments"):
            self.effective("Proof")

    def test_generated_relation_can_select_explicit_argument_indices(self):
        self.module("Base", events=[("definition", "Eq", {"calc_symbol": "=", "arguments": [2, 3]})])
        self.module("Proof", ["Base"])
        reg = self.effective("Proof").registry
        self.assertEqual(reg.get("Eq").arguments, (2, 3))

    def test_generated_relation_renders_without_toml(self):
        self.module("Base", events=[("definition", "Eq", {"calc_symbol": "="})])
        self.module("Proof", ["Base"])
        config = self.effective("Proof")
        engine = Expr2TeX(config.registry, VariableAllocator(list(config.variables)))
        expr = {"kind": "app", "headConstant": "Eq", "fn": {"kind": "app",
            "fn": {"kind": "const", "name": "Eq"}, "arg": {"kind": "lit", "lit": {"value": 1}}},
            "arg": {"kind": "lit", "lit": {"value": 2}},
            "arguments": [{"isExplicit": True}, {"isExplicit": True}]}
        self.assertEqual(re.sub(r"\s+", "", engine.render(expr)), "$1=2$")

    def test_proof_engine_uses_module_config_and_independent_allocators(self):
        self.module("Base", events=[("definition", "Eq", {"calc_symbol": "="}),
                                    ("variable", "Nat", {"default": "n", "names": ["n", "m"]})])
        self.module("Proof", ["Base"])
        config = self.effective("Proof")
        left = ProofEngine([], lean2tex_config=config)
        right = ProofEngine([], lean2tex_config=config)
        self.assertEqual(left.render_relation({"headConstant": "Eq"}), "=")
        self.assertEqual(left.renderer.allocator.allocate_var("Nat"), "n")
        self.assertEqual(left.renderer.allocator.allocate_var("Nat"), "m")
        self.assertEqual(right.renderer.allocator.allocate_var("Nat"), "n")
        self.assertIsNot(left.renderer.allocator, right.renderer.allocator)

    def test_build_validation_rejects_missing_config_before_publication(self):
        self.module("Base")
        self.module("Proof", ["Base"])
        proof = self.root / "proofs" / "Proof.json"
        proof.parent.mkdir(parents=True)
        proof.write_text(json.dumps({"schemaVersion": "0.0.0", "module": "Proof", "proof": []}))
        (self.root / "lean2tex" / "events" / "Base.json").unlink()
        with self.assertRaisesRegex(PS4HTMLError, "Invalid Lean2TeX configuration.*Base"):
            _validate_render_inputs(self.root)

    def test_invalid_effective_modes_and_empty_styles(self):
        self.module("Base", events=[("definition", "Eq", {"alias": "Target", "unwrap": 0}),
                                    ("definition", "Target", {"styles": [{"template": "ok"}]})])
        self.module("Proof", ["Base"])
        with self.assertRaisesRegex(ValueError, "mutually exclusive"):
            self.effective("Proof")
        self.module("Base", events=[("definition", "Eq", {"styles": []})])
        with self.assertRaisesRegex(ValueError, "no styles"):
            self.effective("Proof")

    def test_phrase_language_conflict(self):
        self.module("A", events=[("phrase", "forall", {"template": [{"lang": "zh", "content": "${body}"}]})])
        self.module("B", events=[("phrase", "forall", {"template": [{"lang": "en", "content": "${type}"}]})])
        self.module("Proof", ["A", "B"])
        self.assertEqual(self.effective("Proof").registry.phrase("forall", "en"), "${type}")
        self.module("B", events=[("phrase", "forall", {"template": [{"lang": "zh", "content": "${type}"}]})])
        with self.assertRaisesRegex(ValueError, "conflicting.*template.zh"):
            self.effective("Proof")

    def test_local_events_do_not_affect_own_module_and_missing_alias_target(self):
        self.module("Base", events=[("definition", "Eq", {"calc_symbol": "="})])
        self.module("Child", ["Base"], [("definition", "Eq", {"alias": "Missing"})])
        self.assertEqual(self.effective("Child").registry.rel_symbol("Eq"), "=")
        self.module("Proof", ["Child"])
        with self.assertRaisesRegex(ValueError, "missing alias target configuration"):
            self.effective("Proof")

    def test_bad_binder_and_noncontiguous_placeholder(self):
        self.module("Base", events=[("definition", "F", {"arguments": [0], "styles": [
            {"template": "@0", "binders": [[0, 1]]}]})])
        self.module("Proof", ["Base"])
        with self.assertRaisesRegex(ValueError, "style without @ selectors"):
            self.effective("Proof")
        self.module("Base", events=[("definition", "F", {"arguments": [0, 1, 2], "styles": [
            {"template": "#0+#2"}]})])
        with self.assertRaisesRegex(ValueError, "non-contiguous placeholders"):
            self.effective("Proof")

    def test_missing_event_file_and_corrupt_fields(self):
        self.module("Base")
        self.module("Proof", ["Base"])
        (self.root / "lean2tex" / "events" / "Base.json").unlink()
        with self.assertRaisesRegex(ValueError, "missing Lean2TeX event file"):
            self.effective("Proof")
        self.module("Base", events=[("definition", "Eq", {"unexpected": 1})])
        with self.assertRaisesRegex(ValueError, "unknown fields"):
            self.effective("Proof")

    def test_removed_child_roles_is_rejected(self):
        self.module("Base", events=[("definition", "Eq", {"styles": [
            {"template": "#0=#1", "child_roles": ["left", "right"]}]})])
        self.module("Proof", ["Base"])
        with self.assertRaisesRegex(ValueError, "unknown or missing style fields"):
            self.effective("Proof")

    def test_isolated_arguments_skip_only_their_own_parentheses(self):
        styles = [
            ("Add", "#0+#1", 65, []),
            ("Frac", "\\frac{#0}{#1}", 70, [0, 1]),
            ("Pow", "{#0}^{#1}", 80, [1]),
        ]
        self.module("Base", events=[("definition", name, {"arguments": [0, 1], "styles": [
            {"template": template, "fixity": "infix", "precedence": precedence,
             "isolated_arguments": isolated}]}) for name, template, precedence, isolated in styles])
        self.module("Proof", ["Base"])
        registry = self.effective("Proof").registry
        self.assertEqual(registry.get("Frac").styles[0].isolated_arguments, frozenset({0, 1}))
        render = LayoutRenderer(registry)
        atom = lambda name: DisplayNode(name, "literal")
        add = lambda left, right: DisplayNode("Add", "application", [left, right])
        fraction = DisplayNode("Frac", "application", [add(atom("a"), atom("b")), add(atom("c"), atom("d"))])
        power = DisplayNode("Pow", "application", [add(atom("a"), atom("b")), add(atom("c"), atom("d"))])
        self.assertEqual(render.render(fraction, parent_mode="formula"), "\\frac{a+b}{c+d}")
        self.assertEqual(render.render(power, parent_mode="formula"), "{\\left(a+b\\right)}^{c+d}")

    def test_isolated_arguments_validate_indices(self):
        for indices in ([0, 0], [-1], [True], [2]):
            with self.subTest(indices=indices):
                self.module("Base", events=[("definition", "Frac", {"arguments": [0, 1], "styles": [
                    {"template": "\\frac{#0}{#1}", "isolated_arguments": indices}]})])
                self.module("Proof", ["Base"])
                with self.assertRaisesRegex(ValueError, "isolated_arguments"):
                    self.effective("Proof")


if __name__ == "__main__":
    unittest.main()
