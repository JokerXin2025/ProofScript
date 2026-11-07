"""Check server-side binder ownership and reverse-order where clauses."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from Lean2TeX.interactions import ExpressionInteractions
from Lean2TeX.macros import MacroRegistry, macro_from_data
from Lean2TeX.model import DisplayNode
from Lean2TeX.renderer import LayoutRenderer


def leaf(name, kind="const"):
    return DisplayNode(name, kind)


registry = MacroRegistry()
registry.add(macro_from_data({
    "name": "Exists", "kind": "concept", "auto_arity": False, "default": "formula",
    "templates": [
        {"label": "formula", "content": r"\exists\ @1\in #0,\ @@1", "binders": {"1": 1}},
        {"label": "function", "lang": "en", "content": "Exists(#0,#1)"},
    ],
}))
exists = DisplayNode("Exists", "concept", [leaf("T"), DisplayNode("lambda", "lambda", [
    leaf("x", "binder"), leaf("T"), leaf("P"),
])], metadata={"headConst": "Exists"})
interactions = ExpressionInteractions()
mapping = interactions.register(exists, "test", "zh")
tex = LayoutRenderer(registry).render(exists, parent_mode="formula", interactions=interactions, fragments=mapping)
assert "\\exists" in tex and "\\mapsto" not in tex, tex
assert not any(owner == mapping[id(exists.children[1])] for owner in interactions.fragments.values()), tex

registry.add(macro_from_data({"name": "Add", "kind": "operator", "argument_indices": [0, 1],
                              "symbol": "+", "operator_info": {"fixity": "infix", "precedence": 65,
                                                                "associativity": "left"}}))
registry.add(macro_from_data({"name": "Eq", "kind": "relation", "argument_indices": [0, 1],
                              "symbol": "="}))
registry.add(macro_from_data({"name": "Neg", "kind": "operator", "argument_indices": [0],
                              "symbol": "-", "operator_info": {"fixity": "prefix", "precedence": 75}}))
sum_node = DisplayNode("Add", "operator", [leaf("a", "fvar"), leaf("b", "fvar")],
                       metadata={"headConst": "Add", "originalExprKind": "app"})
eq_node = DisplayNode("Eq", "relation", [sum_node, leaf("c", "fvar")],
                      metadata={"headConst": "Eq", "originalExprKind": "app"})
neg_node = DisplayNode("Neg", "operator", [sum_node],
                       metadata={"headConst": "Neg", "originalExprKind": "app"})
assert LayoutRenderer(registry).render(eq_node, parent_mode="formula") == "a+b=c"
assert LayoutRenderer(registry).render(neg_node, parent_mode="formula") == r"-\left(a+b\right)"

outer = DisplayNode("let", "let", [leaf("a", "binder"), leaf("A"),
    DisplayNode("let", "let", [leaf("b", "binder"), leaf("B"), leaf("R")])])
interactions = ExpressionInteractions()
mapping = interactions.register(outer, "test", "zh")
where = LayoutRenderer(registry).render(outer, parent_mode="formula", interactions=interactions, fragments=mapping)
assert where.index("{b}") < where.index("{a}"), where
print("Server renderer binder ownership and let clause order OK")
