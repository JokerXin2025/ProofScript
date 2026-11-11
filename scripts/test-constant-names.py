#!/usr/bin/env python3
"""Bare constants and fallback heads use frozen names without constant templates."""

from pathlib import Path
import json
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from Lean2TeX.configuration import EffectiveConfiguration
from Lean2TeX.core import Expr2TeX
from Lean2TeX.interactions import ExpressionInteractions
from Lean2TeX.macros import MacroRegistry, macro_from_data
from Lean2TeX.model import RenderTarget


def constant(name, kind=None):
    node = {"kind": "const", "name": name, "levels": []}
    return ({"kind": "mdata", "data": {"ProofScript.declarationKind": kind}, "expr": node}
            if kind else node)


def app(fn, arg):
    return {"kind": "app", "fn": fn, "arg": arg}


class ConstantNamesTest(unittest.TestCase):
    def setUp(self):
        registry = MacroRegistry()
        registry.add(macro_from_data({
            "name": "Names.fun", "kind": "concept", "argument_indices": [0, 1],
            "default": "formula", "templates": [
                {"label": "formula", "content": "#0+#1"},
                {"label": "alternate", "lang": "en", "content": "#0\\cdot #1"}],
        }))
        registry.add(macro_from_data({
            "name": "Names.atomic", "kind": "concept", "argument_indices": [],
            "default": "formula", "templates": [{"label": "formula", "content": "WRONG"}],
        }))
        registry.add(macro_from_data({
            "name": "Names.thm", "kind": "concept", "argument_indices": [0, 1],
            "default": "formula", "templates": [{"label": "formula", "content": "WRONG"}],
        }))
        registry.aliases["Names.alias"] = "Names.atomic"
        registry.declarations["Names.thm"] = {"kind": "theorem"}
        self.renderer = Expr2TeX(registry, definition_names={
            "Names.fun": "Function", "Names.atomic": "A_B", "Names.alias": "Alias",
            "Names.proofDef": "Proof definition", "Names.thm": "Definition title",
        }, theorem_names={"Names.thm": "Theorem title"})

    def render(self, expr):
        return self.renderer.render(expr, parent="Formula")

    def test_bare_and_partially_applied_constants(self):
        self.assertEqual(self.render(constant("Names.atomic")), r"\operatorname{A\_B}")
        self.assertEqual(self.render(constant("Names.alias")), r"\operatorname{Alias}")
        self.assertEqual(self.render(app(constant("Names.fun"), constant("Names.atomic"))),
                         r"\operatorname{Function}\left(\operatorname{A\_B}\right)")
        self.assertEqual(self.render(constant("Names.unconfigured")), r"\operatorname{Names.unconfigured}")

    def test_complete_application_still_uses_template(self):
        expr = app(app(constant("Names.fun"), constant("Names.atomic")), constant("Names.alias"))
        self.assertEqual(self.render(expr), r"\operatorname{A\_B}+\operatorname{Alias}")

    def test_theorem_identity_uses_declaration_kind_not_proof_type(self):
        theorem = constant("Names.thm", "theorem")
        self.assertEqual(self.renderer.convert(theorem).kind, "theorem")
        self.assertEqual(self.render(theorem), r"\operatorname{Theorem title}")
        self.assertEqual(self.renderer.convert(constant("Names.thm")).kind, "theorem")
        self.assertEqual(self.render(app(theorem, constant("Names.atomic"))),
                         r"\operatorname{Theorem title}\left(\operatorname{A\_B}\right)")
        complete = app(app(theorem, constant("Names.atomic")), constant("Names.alias"))
        self.assertEqual(self.renderer.convert(complete).children[0].kind, "theorem")
        self.assertEqual(self.render(complete),
                         r"\operatorname{Theorem title}\left(\operatorname{A\_B},\operatorname{Alias}\right)")
        proof_definition = constant("Names.proofDef", "definition")
        self.assertEqual(self.renderer.convert(proof_definition).kind, "const")
        self.assertEqual(self.render(proof_definition), r"\operatorname{Proof definition}")

    def test_configuration_passes_frozen_names_to_renderer(self):
        config = EffectiveConfiguration(self.renderer.registry, {}, {},
                                        {"Names.atomic": "Frozen constant"},
                                        {"Names.thm": "Frozen theorem"})
        renderer = Expr2TeX.from_config(config)
        self.assertEqual(renderer.render(constant("Names.atomic"), parent="Formula"),
                         r"\operatorname{Frozen constant}")
        self.assertEqual(renderer.render(constant("Names.thm", "theorem"), parent="Formula"),
                         r"\operatorname{Frozen theorem}")

    def test_browser_repaint_uses_each_roots_frozen_names(self):
        interactions = ExpressionInteractions()
        interactions.enable_render_roots = True
        cases = []
        for suffix in ("First", "Second"):
            config = EffectiveConfiguration(self.renderer.registry, {}, {},
                {"Names.atomic": f"{suffix}_constant", "Names.fun": "Function"},
                {"Names.thm": f"{suffix} theorem"})
            renderer = Expr2TeX.from_config(config)
            renderer.interactions = interactions
            expressions = [constant("Names.atomic"), constant("Names.thm", "theorem"),
                           app(constant("Names.fun"), constant("Names.atomic")),
                           app(app(constant("Names.fun"), constant("Names.atomic")),
                               constant("Names.thm", "theorem")),
                           app(app(constant("Names.thm", "theorem"), constant("Names.atomic")),
                               constant("Names.alias"))]
            for expr in expressions:
                displayed = renderer.convert(expr)
                initial = renderer.render_display(displayed, parent="Formula", language="en")
                root_id = f"r{len(interactions.render_roots)}"
                self.assertIn(f"[[PS4HTML-ROOT-{root_id}]]", initial)
                cases.append((root_id, Expr2TeX.from_config(config).render(
                    expr, parent="Formula", language="en")))
        roots = interactions.as_dict()["renderRoots"]
        self.assertEqual(roots["r1"]["catalog"], {})
        self.assertEqual(roots["r2"]["tree"]["kind"], "theorem")
        self.assertEqual(roots["r3"]["tree"]["children"][0]["kind"], "const")
        self.assertIn(RenderTarget("constant", "Names.fun").as_key(), roots["r4"]["catalog"])
        self.assertNotIn(RenderTarget("constant", "Names.atomic").as_key(), roots["r4"]["catalog"])
        self.assertEqual(roots["r5"]["tree"]["children"][0]["kind"], "theorem")
        self.assertNotIn(RenderTarget("constant", "Names.thm").as_key(), roots["r5"]["catalog"])
        self.assertNotEqual(roots["r1"]["names"], roots["r6"]["names"])
        js = Path(__file__).resolve().parents[1] / "tools/ps4html/PS4HTML/assets/js/render-tree.js"
        driver = """const fs = require('fs');
global.window = {};
require(process.argv[1]);
const roots = JSON.parse(fs.readFileSync(0, 'utf8'));
process.stdout.write(JSON.stringify(Object.fromEntries(Object.entries(roots).map(([id, root]) =>
  [id, window.PS4HTMLRenderTree.render(root.tree, root.catalog, {}, root.language,
                                      root.parentMode, null, root.names)]))));"""
        output = subprocess.run(["node", "-e", driver, str(js)], input=json.dumps(roots),
                                text=True, capture_output=True, check=True)
        browser = json.loads(output.stdout)
        for root_id, expected in cases:
            self.assertEqual(browser[root_id], expected, root_id)
        choice = RenderTarget("constant", "Names.fun")
        for root_id, suffix in (("r4", "First"), ("r9", "Second")):
            config = EffectiveConfiguration(self.renderer.registry, {}, {},
                {"Names.atomic": f"{suffix}_constant", "Names.fun": "Function"},
                {"Names.thm": f"{suffix} theorem"})
            expr = app(app(constant("Names.fun"), constant("Names.atomic")),
                       constant("Names.thm", "theorem"))
            expected = Expr2TeX.from_config(config).render(
                expr, parent="Formula", language="en", selections={choice: "alternate"})
            selected = subprocess.run(["node", "-e", driver.replace("{}, root.language", "{[JSON.stringify(['constant', 'Names.fun']).replace(',', ', ')]: 'alternate'}, root.language"), str(js)],
                                      input=json.dumps({root_id: roots[root_id]}),
                                      text=True, capture_output=True, check=True)
            self.assertEqual(json.loads(selected.stdout)[root_id], expected)


if __name__ == "__main__":
    unittest.main()
