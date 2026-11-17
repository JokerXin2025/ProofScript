"""Check server-side binder ownership and reverse-order where clauses."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from Lean2TeX.interactions import ExpressionInteractions
from Lean2TeX.macros import MacroRegistry, macro_from_data
from Lean2TeX.model import DisplayNode
from Lean2TeX.renderer import LayoutRenderer

def argument(index, mode="formula"):
    return {"kind": "argument", "index": index, "mode": mode, "max_precedence": False}


def binder(index, depth, mode="formula"):
    return {"kind": "binder", "index": index, "depth": depth, "mode": mode, "max_precedence": False}


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
    return {"name": name, "var_name": "", "kind": kind, "wrapper_index": None, "alias_target": None,
            "templates": list(templates), "default_template": default_template, "calc_symbol": None,
            "parameter_template": None, "extra": {}, "arity": len(infos), "binder_infos": infos,
            "parameter_argument_indices": [index for index, info in enumerate(infos) if info == "explicit"],
            **fields}


def leaf(name, kind="const"):
    return DisplayNode(name, kind)


registry = MacroRegistry()
registry.add(macro_from_data(definition("Exists", arity=2, templates=[
    template(r"\exists\ ", binder(1, 1), r"\in ", argument(0), r",\ ",
             {**binder(1, 2), "kind": "body", "depth": 1},
             indices=[0, 1], auto_arity=False),
    template("Exists(", argument(0), ",", argument(1), ")", indices=[0, 1], label="function", lang="en"),
])))
exists = DisplayNode("Exists", "concept", [leaf("T"), DisplayNode("lambda", "lambda", [
    leaf("x", "binder"), leaf("T"), leaf("P"),
])], metadata={"headConst": "Exists"})
interactions = ExpressionInteractions()
mapping = interactions.register(exists, "test", "zh")
tex = LayoutRenderer(registry).render(exists, parent_mode="formula", interactions=interactions, fragments=mapping)
assert "\\exists" in tex and "\\mapsto" not in tex, tex
assert not any(owner == mapping[id(exists.children[1])] for owner in interactions.fragments.values()), tex

registry.add(macro_from_data(definition("Add", arity=2, kind="operator", default_template="$infixl", templates=[
    template(argument(0), "+", argument(1), indices=[0, 1], label="$infixl", precedence=65)],
)))
registry.add(macro_from_data(definition("Eq", arity=2, kind="relation", default_template="$relation", templates=[
    template(argument(0), "=", argument(1), indices=[0, 1], label="$relation", precedence=50)],
)))
registry.add(macro_from_data(definition("Neg", arity=1, kind="operator", default_template="$prefix", templates=[
    template("-", argument(0), indices=[0], label="$prefix", precedence=75)],
)))
sum_node = DisplayNode("Add", "operator", [leaf("a", "fvar"), leaf("b", "fvar")],
                       metadata={"headConst": "Add", "originalExprKind": "app"})
eq_node = DisplayNode("Eq", "relation", [sum_node, leaf("c", "fvar")],
                      metadata={"headConst": "Eq", "originalExprKind": "app"})
neg_node = DisplayNode("Neg", "operator", [sum_node],
                       metadata={"headConst": "Neg", "originalExprKind": "app"})
assert LayoutRenderer(registry).render(eq_node, parent_mode="formula") == "a+b=c"
assert LayoutRenderer(registry).render(neg_node, parent_mode="formula") == r"-\left(a+b\right)"

def nested(label, left):
    operator = macro_from_data(definition("Assoc", arity=2, kind="operator", default_template=label,
        templates=[template(argument(0), "+", argument(1), indices=[0, 1], label=label, precedence=65)]))
    local = MacroRegistry()
    local.add(operator)
    inner = DisplayNode("Assoc", "operator", [leaf("a", "fvar"), leaf("b", "fvar")],
                        metadata={"headConst": "Assoc"})
    outer = DisplayNode("Assoc", "operator",
                        [inner, leaf("c", "fvar")] if left else [leaf("c", "fvar"), inner],
                        metadata={"headConst": "Assoc"})
    return LayoutRenderer(local).render(outer, parent_mode="formula")

assert nested("$infixl", True) == "a+b+c"
assert nested("$infixl", False) == r"c+\left(a+b\right)"
assert nested("$infixr", True) == r"\left(a+b\right)+c"
assert nested("$infixr", False) == "c+a+b"
assert nested("$infix", True) == r"\left(a+b\right)+c"
assert nested("$infix", False) == r"c+\left(a+b\right)"

outer = DisplayNode("let", "let", [leaf("a", "binder"), leaf("A"),
    DisplayNode("let", "let", [leaf("b", "binder"), leaf("B"), leaf("R")])])
interactions = ExpressionInteractions()
mapping = interactions.register(outer, "test", "zh")
where = LayoutRenderer(registry).render(outer, parent_mode="formula", interactions=interactions, fragments=mapping)
assert where.index("{b}") < where.index("{a}"), where
print("Server renderer binder ownership and let clause order OK")
