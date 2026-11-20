"""Cross-runtime template instruction semantics, including interaction ownership."""
import copy
import json
import re
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/ps4html"))
from Lean2TeX.macros import MacroRegistry, macro_from_data
from Lean2TeX.model import DisplayNode
from Lean2TeX.renderer import LayoutRenderer
from Lean2TeX.mixed import linear_template
from Lean2TeX.interactions import ExpressionInteractions


def arg(index=0, mode="formula", maximum=False):
    return dict(kind="argument", index=index, mode=mode, max_precedence=maximum)


def selector(kind, depth, mode="formula", maximum=False):
    return dict(kind=kind, index=0, depth=depth, mode=mode, max_precedence=maximum)


def lit(content):
    return dict(kind="literal", content=content)


def switch(mode, *parts):
    return dict(kind="mode_switch", mode=mode, instructions=list(parts))


def definition(instructions, mode="formula", precedence=100):
    return dict(name="F", kind="concept", arity=1, binder_infos=["explicit"],
                default_template="main", templates=[dict(
                     label="main", lang=None, mode=mode, content="inspection",
                    auto_arity=True, precedence=precedence,
                    argument_indices=[0], instructions=instructions)])


def wire(node, counter=None):
    counter = counter if counter is not None else [0]
    counter[0] += 1
    occurrence = str(counter[0])
    return dict(name=node.macro_name, kind=node.kind, metadata=node.metadata, occurrence=occurrence,
                children=[wire(child, counter) for child in node.children])


class TemplateProtocol(unittest.TestCase):
    def compare(self, parts, expected, *, mode="formula", child=None):
        record = definition(parts, mode)
        macro = macro_from_data(record)
        registry = MacroRegistry()
        registry.add(macro)
        child = child or DisplayNode("x", "fvar")
        root = DisplayNode("F", "concept", [child], metadata={"leanName": "F", "headConst": "F"})
        python = LayoutRenderer(registry).render(root, parent_mode=mode)
        self.assertEqual(python, expected)
        interactions = ExpressionInteractions()
        mapping = interactions.register(root, "template-protocol", "zh")
        LayoutRenderer(registry).render(root, parent_mode=mode, interactions=interactions, fragments=mapping)
        self.assertIn(mapping[id(root)], interactions.fragments.values())
        roundtrip = [item.as_dict() for item in macro.templates[0].instructions]
        self.assertEqual(roundtrip, parts)
        template = record["templates"][0]
        browser_template = {**template, "argumentIndices": [0], "autoArity": True}
        data = dict(tree=wire(root), catalog={'["constant", "F"]': dict(
            kind="concept", arity=1, default="main", templates=[browser_template])}, mode=mode)
        script = """
const fs = require('node:fs'), vm = require('node:vm');
const window = {};
vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), {window});
const d = JSON.parse(fs.readFileSync(0, 'utf8'));
const render = window.PS4HTMLRenderTree.render;
const plain = render(d.tree, d.catalog, {}, 'zh', d.mode);
const owners = [];
render(d.tree, d.catalog, {}, 'zh', d.mode, id => { owners.push(id); return 'p' + owners.length; });
process.stdout.write(JSON.stringify({plain, owners}));
"""
        result = subprocess.run(["node", "-e", script,
                                 str(ROOT / "tools/ps4html/PS4HTML/assets/js/render-tree.js")],
                                input=json.dumps(data), text=True, capture_output=True, check=True)
        browser = json.loads(result.stdout)
        self.assertEqual(browser["plain"], python)
        self.assertIn("1", browser["owners"])
        return macro

    def test_per_occurrence_maximum_at_equal_priority(self):
        self.compare([arg(maximum=True), lit("+"), arg()], r"x+\left(x\right)")

    def test_formula_to_text(self):
        self.compare([arg(maximum=True), switch("text", lit(" iff ")), arg(maximum=True)],
                     r"x\text{ iff }x")

    def test_text_to_formula(self):
        self.compare([lit("value:"), switch("formula", arg(maximum=True))], "value: $x$ ", mode="text")

    def test_formula_child_inside_text_switch(self):
        self.compare([switch("text", lit("value "), arg(mode="text", maximum=True))],
                     r"\text{value  }x\text{ }")

    def test_binder_and_body_maximum(self):
        child = DisplayNode("lambda", "lambda", [DisplayNode("x", "binder"),
                            DisplayNode("T", "fvar"), DisplayNode("y", "fvar")])
        binder = dict(kind="binder", index=0, depth=1, mode="formula", max_precedence=True)
        body = {**binder, "kind": "body", "depth": 1}
        self.compare([switch("text", lit("bind ")), binder, lit(":"), body],
                     r"\text{bind }x:y", child=child)

    def test_body_zero_and_unconsumed_lambda(self):
        inner = DisplayNode("lambda", "lambda", [DisplayNode("y", "binder"),
                            DisplayNode("T", "fvar"), DisplayNode("z", "fvar")])
        outer = DisplayNode("lambda", "lambda", [DisplayNode("x", "binder"),
                            DisplayNode("T", "fvar"), inner])
        self.compare([selector("body", 0, maximum=True)], "x \\mapsto y \\mapsto z", child=outer)
        self.compare([selector("body", 1, maximum=True)], "y \\mapsto z", child=outer)
        self.compare([selector("body", 2, maximum=True)], "z", child=outer)
        self.compare([selector("body", 0, maximum=True)], "x", child=DisplayNode("x", "fvar"))

    def test_guards_derive_maximum_across_mode_switch(self):
        instructions = [selector("binder", 1), switch("text", selector("body", 2, "text"))]
        macro = macro_from_data(definition(instructions))
        self.assertEqual(macro.templates[0].binder_requirements, {0: 2})
        registry = MacroRegistry()
        registry.add(macro)
        for depth, matched in [(0, False), (1, False), (2, True), (3, True)]:
            child = DisplayNode("x", "fvar")
            for n in range(depth):
                child = DisplayNode("lambda", "lambda", [DisplayNode(str(n), "binder"),
                                    DisplayNode("T", "fvar"), child])
            root = DisplayNode("F", "concept", [child], metadata={"headConst": "F"})
            self.assertEqual(registry.template_for(macro, node=root) is not None, matched)

    def test_guard_fallback_matches_browser(self):
        parts = [selector("body", 2)]
        record = definition(parts)
        record["templates"].append({**record["templates"][0], "label": "fallback", "instructions": [arg()]})
        macro = macro_from_data(record)
        root = DisplayNode("F", "concept", [DisplayNode("x", "fvar")],
                           metadata={"leanName": "F", "headConst": "F"})
        registry = MacroRegistry()
        registry.add(macro)
        expected = LayoutRenderer(registry).render(root, parent_mode="formula")
        self.assertEqual(expected, r"\left(x\right)")
        data = dict(tree=wire(root), catalog={'["constant", "F"]': dict(
            kind="concept", arity=1, default="main", templates=[
                {**template, "argumentIndices": [0]} for template in record["templates"]])})
        script = """
const fs = require('node:fs'), vm = require('node:vm');
const window = {};
vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), {window});
const d = JSON.parse(fs.readFileSync(0, 'utf8'));
process.stdout.write(window.PS4HTMLRenderTree.render(d.tree, d.catalog, {}, 'zh', 'formula'));
"""
        result = subprocess.run(["node", "-e", script,
                                 str(ROOT / "tools/ps4html/PS4HTML/assets/js/render-tree.js")],
                                input=json.dumps(data), text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, expected)

    def test_independent_argument_requirements(self):
        record = definition([selector("binder", 1), {**selector("body", 2), "index": 1}])
        record["arity"] = 2
        record["binder_infos"] = ["explicit", "explicit"]
        record["templates"][0]["argument_indices"] = [0, 1]
        macro = macro_from_data(record)
        self.assertEqual(macro.templates[0].binder_requirements, {0: 1, 1: 2})
        registry = MacroRegistry()
        registry.add(macro)
        def chain(depth):
            child = DisplayNode("result", "fvar")
            for n in range(depth):
                child = DisplayNode("lambda", "lambda", [DisplayNode(str(n), "binder"),
                                    DisplayNode("T", "fvar"), child])
            return child
        for depths, matched in [((0, 2), False), ((1, 1), False),
                                ((1, 2), True), ((2, 3), True)]:
            root = DisplayNode("F", "concept", [chain(depth) for depth in depths])
            self.assertEqual(registry.template_for(macro, node=root) is not None, matched)

    def test_mode_switch_disables_html_atom_splitting(self):
        macro = macro_from_data(definition([switch("text", lit("prefix")), arg()]))
        self.assertFalse(linear_template(macro.templates[0], [DisplayNode("s", "literal")]))

    def test_mixed_template_owns_html_literals_in_both_runtimes(self):
        record = definition([arg(0), lit("+"), arg(1), lit("+"), arg(2)])
        record["arity"] = 3
        record["binder_infos"] = ["explicit"] * 3
        record["templates"][0]["argument_indices"] = [0, 1, 2]
        registry = MacroRegistry()
        registry.add(macro_from_data(record))
        literal = DisplayNode('加<&>', "literal", metadata={"literalKind": "literal.str"})
        root = DisplayNode("F", "concept", [DisplayNode("x", "fvar"), literal, DisplayNode("y", "fvar")],
                           metadata={"leanName": "F", "headConst": "F"})
        interactions = ExpressionInteractions()
        mapping = interactions.register(root, "mixed-template", "zh")
        python = LayoutRenderer(registry).render(root, interactions=interactions, fragments=mapping)
        root_id = interactions.add_root(root, mapping, registry, "zh", "text")
        frozen = interactions.render_roots[root_id]
        script = """
const fs = require('node:fs'), vm = require('node:vm'), window = {};
vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), {window});
const d = JSON.parse(fs.readFileSync(0, 'utf8')), outputs = [];
for (const style of ['plain', 'strong', 'code']) {
    const owners = {};
    const tex = window.PS4HTMLRenderTree.render(d.tree, d.catalog,
        {'["builtin", "literal.str"]': style}, 'zh', 'text',
        owner => { const id = 'p' + (Object.keys(owners).length + 1); owners[id] = owner; return id; });
    outputs.push({tex, owners});
}
process.stdout.write(JSON.stringify(outputs));
"""
        result = subprocess.run(["node", "-e", script,
                                 str(ROOT / "tools/ps4html/PS4HTML/assets/js/render-tree.js")],
                                input=json.dumps(frozen), text=True, capture_output=True, check=True)
        for output in [{"tex": python, "owners": interactions.fragments}, *json.loads(result.stdout)]:
            with self.subTest(tex=output["tex"]):
                match = re.search(r"\[\[PS4HTML-START-(p\d+)\]\]"
                                  r"\[\[PS4HTML-LITERAL-(?:plain|strong|code)-[0-9a-f]*-(p\d+)\]\]"
                                  r"\[\[PS4HTML-END-\1\]\]", output["tex"])
                self.assertIsNotNone(match, "HTML atom needs its own containing-template anchor")
                self.assertEqual(output["owners"][match[1]], mapping[id(root)])
                self.assertEqual(output["owners"][match[2]], mapping[id(literal)])
                math_anchors = re.findall(r"ps-expr-fragment=(p\d+)", output["tex"])
                self.assertEqual(sum(output["owners"][fragment] == mapping[id(root)] for fragment in math_anchors), 2)
        interactions.collect(python)
        html = interactions.materialize_text(python)
        self.assertIn('加&lt;&amp;&gt;', html)
        self.assertEqual(len(interactions.occurrences[mapping[id(root)]]["fragmentIds"]), 3)

    def test_reject_invalid_wire_data(self):
        valid = definition([arg()])
        invalid = [switch("formula", lit("same mode")),
                   switch("text", switch("formula", arg())),
                   switch("text", arg(mode="formula")),
                   switch("text", arg(index=2, mode="text")),
                    {**arg(), "max_precedence": 1}, selector("binder", 0),
                    {**selector("body", 0), "depth": -1}, {**selector("body", 0), "depth": True}]
        for instruction in invalid:
            record = copy.deepcopy(valid)
            record["templates"][0]["instructions"] = [instruction]
            with self.subTest(instruction=instruction), self.assertRaises(ValueError):
                macro_from_data(record)


if __name__ == "__main__":
    unittest.main()
