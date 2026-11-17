#!/usr/bin/env python3
"""Frozen names, zero-arity templates, and theorem/application fallback names."""

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

def argument(index, mode="formula"):
    return {"kind": "argument", "index": index, "mode": mode, "max_precedence": False}


def template(*parts, indices=(), label="formula", lang=None, mode="formula", precedence=60,
              auto_arity=True):
    instructions = [{"kind": "literal", "content": part} if isinstance(part, str) else dict(part)
                    for part in parts]
    content = "".join(part["content"] if part["kind"] == "literal" else
                      ("#" if part["kind"] == "argument" else "@" * part["depth"]) + str(part["index"])
                      for part in instructions)
    return {"label": label, "lang": lang, "mode": mode, "content": content,
            "precedence": precedence,
            "auto_arity": auto_arity,
            "argument_indices": list(indices), "instructions": instructions}


def definition(name, *, arity=0, binder_infos=None, kind="concept", templates=(), default_template="formula", **fields):
    infos = list(binder_infos) if binder_infos is not None else ["explicit"] * arity
    return {"name": name, "names": [], "tags": [], "var_name": "", "kind": kind, "wrapper_index": None, "alias_target": None,
            "templates": list(templates), "default_template": default_template, "calc_symbol": None,
            "parameter_template": None, "extra": {}, "arity": len(infos), "binder_infos": infos,
            "parameter_argument_indices": [index for index, info in enumerate(infos) if info == "explicit"],
            **fields}


def constant(name, kind=None):
    node = {"kind": "const", "name": name, "levels": []}
    return ({"kind": "mdata", "data": {"ProofScript.declarationKind": kind}, "expr": node}
            if kind else node)


def app(fn, arg):
    return {"kind": "app", "fn": fn, "arg": arg}


def localized(value, lang="zh"):
    return [{"lang": lang, "value": value}]


class ConstantNamesTest(unittest.TestCase):
    def setUp(self):
        registry = MacroRegistry()
        registry.add(macro_from_data(definition("Names.fun", arity=2, templates=[
            template(argument(0), "+", argument(1), indices=[0, 1]),
            template(argument(0), r"\cdot ", argument(1), indices=[0, 1], label="alternate", lang="en")],
        )))
        registry.add(macro_from_data(definition("Names.token", templates=[
            template(r"\tau"), template("T", label="alternate")],
        )))
        registry.add(macro_from_data(definition("Names.thm", arity=2,
            templates=[template("WRONG", indices=[0, 1])],
        )))
        registry.aliases["Names.alias"] = "Names.atomic"
        registry.aliases["Names.tokenAlias"] = "Names.token"
        registry.theorems.add("Names.thm")
        self.renderer = Expr2TeX(registry, declaration_names={
            "Names.fun": localized("Function"), "Names.atomic": localized("A_B"), "Names.alias": localized("Alias"),
            "Names.proofDef": localized("Proof definition"), "Names.thm": localized("Definition title"),
        }, theorem_names={"Names.thm": (localized("Theorem title"), "thm")})

    def render(self, expr):
        return self.renderer.render(expr, parent="Formula")

    def test_bare_and_partially_applied_constants(self):
        self.assertEqual(self.render(constant("Names.atomic")), r"\operatorname{A\_B}")
        self.assertEqual(self.render(constant("Names.alias")), r"\operatorname{A\_B}")
        self.assertEqual(self.render(app(constant("Names.fun"), constant("Names.atomic"))),
                         r"\operatorname{Function}\left(\operatorname{A\_B}\right)")
        self.assertEqual(self.render(constant("Names.unconfigured")), r"\operatorname{Names.unconfigured}")

    def test_complete_application_still_uses_template(self):
        expr = app(app(constant("Names.fun"), constant("Names.atomic")), constant("Names.alias"))
        self.assertEqual(self.render(expr), r"\operatorname{A\_B}+\operatorname{A\_B}")

    def test_zero_argument_template_and_alias_are_used_on_bare_constants(self):
        self.assertEqual(self.render(constant("Names.token")), r"\tau")
        self.assertEqual(self.render(constant("Names.tokenAlias")), r"\tau")
        self.assertEqual(self.renderer.render(constant("Names.token"), parent="Formula", label="alternate"), "T")
        self.assertEqual(self.render(app(constant("Names.token"), constant("Names.atomic"))),
                         r"\operatorname{Names.token}\left(\operatorname{A\_B}\right)")

    def test_theorem_identity_uses_frozen_info_kind_not_expression_metadata(self):
        theorem = constant("Names.thm", "theorem")
        self.assertEqual(self.renderer.convert(theorem).kind, "theorem")
        self.assertEqual(self.render(theorem), r"\operatorname{Theorem title}")
        self.assertEqual(self.renderer.convert(constant("Names.thm")).kind, "theorem")
        self.assertEqual(self.renderer.convert(constant("Names.thm", "definition")).kind, "theorem")
        self.assertEqual(self.render(app(theorem, constant("Names.atomic"))),
                         r"\operatorname{Theorem title}\left(\operatorname{A\_B}\right)")
        complete = app(app(theorem, constant("Names.atomic")), constant("Names.alias"))
        self.assertEqual(self.renderer.convert(complete).children[0].kind, "theorem")
        self.assertEqual(self.render(complete),
                          r"\operatorname{Theorem title}\left(\operatorname{A\_B},\operatorname{A\_B}\right)")
        proof_definition = constant("Names.proofDef", "definition")
        self.assertEqual(self.renderer.convert(proof_definition).kind, "const")
        self.assertEqual(self.render(proof_definition), r"\operatorname{Proof definition}")

    def test_native_theorem_with_concept_kind_uses_configured_template(self):
        configured = constant("Names.fun", "theorem")
        self.assertEqual(self.renderer.convert(configured).kind, "const")
        complete = app(app(configured, constant("Names.atomic")), constant("Names.alias"))
        self.assertEqual(self.renderer.convert(complete).kind, "concept")
        self.assertEqual(self.render(complete), r"\operatorname{A\_B}+\operatorname{A\_B}")

    def test_configuration_passes_frozen_names_to_renderer(self):
        config = EffectiveConfiguration(self.renderer.registry, {}, {},
                                         {"Names.atomic": localized("Frozen constant")},
                                         {"Names.thm": (localized("Frozen theorem"), "thm")})
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
                {"Names.atomic": localized(f"{suffix}_constant", "en"), "Names.fun": localized("Function", "en")},
                {"Names.thm": (localized(f"{suffix} theorem", "en"), "thm")})
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
                {"Names.atomic": localized(f"{suffix}_constant", "en"), "Names.fun": localized("Function", "en")},
                {"Names.thm": (localized(f"{suffix} theorem", "en"), "thm")})
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
