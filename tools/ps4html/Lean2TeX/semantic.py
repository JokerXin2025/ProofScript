"""Conversion from ProofScript ExprJSON to the internal DisplayTree."""

from __future__ import annotations

from dataclasses import dataclass

from .expr import flatten_app
from .macros import MacroRegistry
from .model import DisplayNode, RenderDiagnostic
from .variable import VariableAllocator


@dataclass(frozen=True)
class _Binding:
    name: str
    bind_id: str


class SemanticConverter:
    def __init__(self, registry: MacroRegistry, allocator: VariableAllocator):
        self.registry = registry
        self.allocator = allocator
        self.diagnostics: list[RenderDiagnostic] = []
        self._binding_counter = 0
        self._tree_counter = 0

    def convert(
        self,
        expr: dict,
        fvars: dict[str, str] | None = None,
        bvar_env: list[str] | None = None,
    ) -> DisplayNode:
        self.diagnostics.clear()
        self._binding_counter = 0
        self._tree_counter += 1
        self._tree_scope = f"e{self._tree_counter}"
        self._fvar_overrides = fvars or {}
        bindings = [_Binding(name, f"{self._tree_scope}:external:{index}") for index, name in enumerate(bvar_env or [])]
        return self._convert(expr, (), bindings, ())

    def _convert(self, expr: object, path: tuple[int, ...], bindings: list[_Binding], raw_bindings: tuple[dict, ...]) -> DisplayNode:
        node = self._convert_node(expr, path, bindings, raw_bindings)
        if isinstance(expr, dict):
            node.metadata.setdefault("originalExprKind", expr.get("kind"))
            if isinstance(expr.get("isProp"), bool):
                node.metadata.setdefault("isProp", expr["isProp"])
            if _source_range(expr) is not None:
                node.metadata.setdefault("sourceRange", _source_range(expr))
        return node

    def _convert_node(self, expr: object, path: tuple[int, ...], bindings: list[_Binding], raw_bindings: tuple[dict, ...]) -> DisplayNode:
        if not isinstance(expr, dict):
            self._diagnose("L2T010", "ExprJSON node is not an object", path)
            return DisplayNode("invalid", "unknown", metadata={"originalExprKind": type(expr).__name__})
        kind = expr.get("kind")
        if kind == "mdata":
            return self._convert(expr.get("expr"), path, bindings, raw_bindings)
        if kind == "app":
            return self._convert_app(expr, path, bindings, raw_bindings)
        if kind == "const":
            name = str(expr.get("name", ""))
            if self.registry.get(name) is None and name not in self.registry.aliases:
                self._diagnose("L2T001", "missing macro configuration", path, name, expr)
            return DisplayNode(name, "const", metadata={"leanName": name, "originalExprKind": kind})
        if kind == "lit":
            literal = expr.get("lit", {})
            value = literal.get("value", "?") if isinstance(literal, dict) else "?"
            literal_kind = literal.get("kind") if isinstance(literal, dict) else None
            return DisplayNode(str(value), "literal", metadata={"value": value, "literalKind": literal_kind, "originalExprKind": kind})
        if kind == "fvar":
            return self._convert_fvar(expr, path, bindings, raw_bindings)
        if kind == "bvar":
            index = expr.get("index", -1)
            if isinstance(index, int) and 0 <= index < len(bindings):
                binding = bindings[index]
                return DisplayNode(binding.name, "bvar", metadata={"bindRef": binding.bind_id, "index": index})
            self._diagnose("L2T003", f"unbound bvar index {index}", path, expr=expr)
            return DisplayNode(f"bvar {index}", "unknown", metadata={"originalExprKind": kind})
        if kind in ("forall", "lam"):
            return self._convert_binder(expr, path, bindings, raw_bindings)
        if kind == "let":
            return self._convert_let(expr, path, bindings, raw_bindings)
        if kind == "proj":
            child = self._convert(expr.get("expr"), path + (0,), bindings, raw_bindings)
            field = expr.get("fieldName") or f"proj{expr.get('index', '?')}"
            return DisplayNode(str(field), "projection", [child], metadata={"structName": expr.get("structName"), "index": expr.get("index")})
        if kind == "sort":
            level = expr.get("level", {})
            name = "Prop" if isinstance(level, dict) and level.get("kind") == "level.zero" else "Type"
            return DisplayNode(name, "sort", metadata={"level": level})
        if kind == "mvar":
            return DisplayNode(str(expr.get("name") or expr.get("id") or "?"), "metavariable", metadata={"id": expr.get("id")})
        self._diagnose("L2T010", f"unknown ExprJSON kind {kind!r}", path, expr=expr)
        return DisplayNode(str(kind or "missing"), "unknown", metadata={"originalExprKind": kind})

    def _convert_app(self, expr: dict, path, bindings, raw_bindings) -> DisplayNode:
        try:
            head, args = flatten_app(expr)
        except (AttributeError, KeyError):
            self._diagnose("L2T010", "malformed application", path)
            return DisplayNode("malformed app", "unknown")
        exported_head = expr.get("headConstant")
        head_name = exported_head if isinstance(exported_head, str) else head.get("name") if head.get("kind") == "const" else None
        if isinstance(head_name, str):
            name = head_name
            canonical_name = self.registry.resolve_alias(name)
            unwrap = self.registry.unwraps.get(name) or self.registry.unwraps.get(canonical_name)
            if unwrap is not None:
                if unwrap.argument < len(args):
                    return self._convert(args[unwrap.argument], path + (unwrap.argument,), bindings, raw_bindings)
                self._diagnose("L2T002", f"unwrap argument index {unwrap.argument} out of range for {len(args)} arguments", path, name, expr)
            name = canonical_name
            macro = self.registry.get(name)
            if macro is not None:
                if macro.dynamic_arity:
                    selected, unknown = self._explicit_indices(expr, args)
                elif macro.arguments == "explicit":
                    selected, unknown = self._explicit_indices(expr, args)
                else:
                    selected = list(macro.arguments)
                    unknown = []
                if any(index >= len(args) for index in selected):
                    self._diagnose("L2T002", f"macro argument index out of range for {len(args)} arguments", path, name, expr)
                    converted_head = self._convert(head, path + (0,), bindings, raw_bindings)
                    children = [converted_head] + [self._convert(arg, path + (i + 1,), bindings, raw_bindings) for i, arg in enumerate(args)]
                    return DisplayNode("application", "application", children, metadata={"headConst": name, "rawArgumentCount": len(args)})
                children = [self._convert(args[index], path + (index,), bindings, raw_bindings) for index in selected]
                display = DisplayNode(name, macro.kind, children, metadata={
                    "leanName": name, "headConst": name, "rawArgumentCount": len(args),
                    "selectedArgumentIndices": selected, "originalExprKind": "app",
                })
                if unknown:
                    trailing = [self._convert(args[index], path + (index,), bindings, raw_bindings) for index in unknown]
                    return DisplayNode("application", "application", [display, *trailing], metadata={"headConst": name, "rawArgumentCount": len(args)})
                return display
            if name == "Exists" and len(args) == 2:
                return DisplayNode("Exists", "exists", [
                    self._convert(args[0], path + (0,), bindings, raw_bindings),
                    self._convert(args[1], path + (1,), bindings, raw_bindings),
                ], metadata={"headConst": name, "rawArgumentCount": len(args)})
        converted_head = self._convert(head, path + (0,), bindings, raw_bindings)
        children = [converted_head] + [self._convert(arg, path + (i + 1,), bindings, raw_bindings) for i, arg in enumerate(args)]
        if head_name is not None:
            self._diagnose("L2T009", "using application fallback", path, head_name, expr)
        return DisplayNode("application", "application", children, metadata={"headConst": head_name, "rawArgumentCount": len(args)})

    @staticmethod
    def _explicit_indices(expr: dict, args: list[dict]) -> tuple[list[int], list[int]]:
        descriptors = expr.get("arguments")
        if not isinstance(descriptors, list) or len(descriptors) != len(args):
            return [], list(range(len(args)))
        explicit = [index for index, item in enumerate(descriptors) if isinstance(item, dict) and item.get("isExplicit") is True]
        unknown = [index for index, item in enumerate(descriptors) if not isinstance(item, dict) or item.get("isExplicit") is None]
        return explicit, unknown

    def _convert_fvar(self, expr, path, bindings, raw_bindings) -> DisplayNode:
        if expr.get("value") is not None:
            return self._convert(expr["value"], path, bindings, raw_bindings)
        fvar_id = str(expr.get("id") or f"missing@{'.'.join(map(str, path))}")
        if fvar_id in self._fvar_overrides:
            return DisplayNode(self._fvar_overrides[fvar_id], "fvar", metadata={"leanName": expr.get("name"), "fvarId": fvar_id})
        type_node = expr.get("type")
        type_name = self.allocator.type_to_name(type_node)
        if expr.get("isProp") is True:
            type_name = "Prop"
            classification = "proposition"
        elif isinstance(type_node, dict) and type_node.get("isProp") is True:
            type_name = "Proof"
            classification = "proof"
        elif type_name == "Type":
            classification = "type"
        elif isinstance(expr.get("isProp"), bool):
            classification = "data"
        elif type_name == "Prop":
            classification = "proposition"
        elif _is_prop_expression(type_node):
            type_name = "Proof"
            classification = "proof"
        else:
            classification = "type"
        if not type_name:
            type_name = "Expr"
            classification = "unknown"
        raw_name = str(expr.get("name") or "")
        if fvar_id in self.allocator.cache:
            name = self.allocator.cache[fvar_id]
        elif raw_name and not is_anonymous_name(raw_name):
            name = self.allocator.reserve(_math_name(raw_name))
            self.allocator.cache[fvar_id] = name
        else:
            name = self.allocator.allocate_fvar(fvar_id, type_name)
        return DisplayNode(name, "fvar", metadata={
            "leanName": expr.get("name"), "fvarId": fvar_id, "typeName": type_name,
            "isProp": expr.get("isProp"), "classification": classification,
        })

    def _convert_binder(self, expr, path, bindings, raw_bindings) -> DisplayNode:
        type_node = expr.get("type")
        raw_name = str(expr.get("name", ""))
        generated = is_anonymous_name(raw_name) or raw_name == "_"
        name = self.allocator.allocate_var(self.allocator.type_to_name(type_node)) if generated else self.allocator.reserve(_math_name(raw_name))
        bind_id = f"{self._tree_scope}:b{self._binding_counter}"
        self._binding_counter += 1
        binding = _Binding(name, bind_id)
        binder = DisplayNode(name, "binder", metadata={
            "bindId": bind_id, "leanName": raw_name, "typeName": self.allocator.type_to_name(type_node),
            "binderInfo": expr.get("binderInfo"),
            "classification": "proof" if isinstance(type_node, dict) and type_node.get("isProp") is True else "data",
        })
        type_display = self._convert(type_node, path + (0,), bindings, raw_bindings)
        body = self._convert(expr.get("body"), path + (1,), [binding] + bindings, (expr,) + raw_bindings)
        self.allocator.release_var(name)
        kind = "forall" if expr.get("kind") == "forall" else "lambda"
        return DisplayNode(kind, kind, [binder, type_display, body], metadata={
            "isArrow": kind == "forall" and not _uses_outer_bvar(expr.get("body")),
            "binderInfo": expr.get("binderInfo"),
        })

    def _convert_let(self, expr, path, bindings, raw_bindings) -> DisplayNode:
        raw_name = str(expr.get("name", ""))
        name = self.allocator.reserve(raw_name) if raw_name and raw_name != "_" else self.allocator.allocate_var(self.allocator.type_to_name(expr.get("type")))
        bind_id = f"{self._tree_scope}:b{self._binding_counter}"
        self._binding_counter += 1
        binder = DisplayNode(name, "binder", metadata={"bindId": bind_id, "leanName": raw_name})
        value = self._convert(expr.get("value"), path + (0,), bindings, raw_bindings)
        body = self._convert(expr.get("body"), path + (1,), [_Binding(name, bind_id)] + bindings, raw_bindings)
        self.allocator.release_var(name)
        return DisplayNode("let", "let", [binder, value, body])

    def _diagnose(self, code, message, path, constant=None, expr=None) -> None:
        self.diagnostics.append(RenderDiagnostic("warning", code, message, constant, path, _source_range(expr)))


def _uses_outer_bvar(expr: object, depth: int = 0) -> bool:
    """Whether expr references the binder immediately outside it."""
    if not isinstance(expr, dict):
        return False
    kind = expr.get("kind")
    if kind == "bvar":
        return expr.get("index") == depth
    extra = 1 if kind in ("forall", "lam", "let") else 0
    for key, value in expr.items():
        if key == "type" or key == "value":
            child_depth = depth
        elif key == "body" and extra:
            child_depth = depth + 1
        else:
            child_depth = depth
        if isinstance(value, dict) and _uses_outer_bvar(value, child_depth):
            return True
    return False


def _is_prop_expression(expr: object) -> bool:
    """Use exported type/typeOf links only; do not infer from rendered names."""
    if not isinstance(expr, dict):
        return False
    annotation = expr.get("typeOf") or expr.get("type")
    if not isinstance(annotation, dict) or annotation.get("kind") != "sort":
        return False
    level = annotation.get("level", {})
    return isinstance(level, dict) and level.get("kind") == "level.zero"


def _source_range(expr: object) -> dict | None:
    if not isinstance(expr, dict):
        return None
    value = expr.get("sourceRange")
    if not isinstance(value, dict):
        return None
    if not isinstance(value.get("file"), str) or not all(isinstance(value.get(key), int) for key in ("start", "stop")):
        return None
    return {"file": value["file"], "start": value["start"], "stop": value["stop"]}


def is_anonymous_name(name: str) -> bool:
    return (
        not name
        or "._hyg." in name
        or "._@." in name
        or name.startswith("_uniq.")
        or name == "[anonymous]"
    )


def _math_name(name: str) -> str:
    """Convert common Lean identifier subscripts to TeX subscripts."""
    subscripts = str.maketrans("₀₁₂₃₄₅₆₇₈₉", "0123456789")
    suffix = len(name)
    while suffix > 0 and name[suffix - 1] in "₀₁₂₃₄₅₆₇₈₉":
        suffix -= 1
    if suffix < len(name):
        return name[:suffix] + "_" + name[suffix:].translate(subscripts)
    return name
