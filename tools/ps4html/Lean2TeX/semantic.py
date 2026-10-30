"""Convert native expressions and occurrence metadata into semantic display trees."""

from __future__ import annotations

from dataclasses import dataclass

from .expr import flatten_app, unwrap_mdata
from .macros import MacroRegistry
from .model import DisplayNode, RenderDiagnostic, RenderLimitError
from .variable import VariableAllocator, is_anonymous_name, math_name


@dataclass(frozen=True)
class _Binding:
    name: str
    bind_id: str
    generated: bool


class SemanticConverter:
    MAX_EXPANDED_NODES = 16_384
    MAX_DEPTH = 256

    def __init__(self, registry: MacroRegistry, allocator: VariableAllocator):
        self.registry = registry
        self.allocator = allocator
        self.diagnostics: list[RenderDiagnostic] = []
        self._binding_counter = 0
        self._tree_counter = 0

    def convert(self, expr: dict) -> DisplayNode:
        self.diagnostics.clear()
        self._binding_counter = 0
        self._expanded_nodes = 0
        self._depth = 0
        self._tree_counter += 1
        self._tree_scope = f"e{self._tree_counter}"
        with self.allocator.transaction():
            return self._convert(expr, (), [])

    def _convert(self, expr: object, path: tuple[int, ...], bindings: list[_Binding]) -> DisplayNode:
        self._visit()
        if self._depth >= self.MAX_DEPTH:
            raise RenderLimitError(f"Expression conversion exceeds depth limit {self.MAX_DEPTH}")
        self._depth += 1
        try:
            structural, _ = unwrap_mdata(expr, visit=self._visit)
            node = self._convert_node(structural, path, bindings, expr)
            if isinstance(structural, dict):
                node.metadata.setdefault("originalExprKind", structural.get("kind"))
                # An unwrap may reuse its argument's display node, but these
                # facts belong only to the occurrence currently being converted.
                source = _source_range(expr)
                if source is None:
                    node.metadata.pop("sourceRange", None)
                else:
                    node.metadata["sourceRange"] = source
            return node
        finally:
            self._depth -= 1

    def _visit(self) -> None:
        # A small shared DAG may denote an exponentially larger display tree.
        # Bound expanded work rather than just the number of wire-table nodes.
        self._expanded_nodes += 1
        if self._expanded_nodes > self.MAX_EXPANDED_NODES:
            raise RenderLimitError(
                f"Expression conversion exceeds {self.MAX_EXPANDED_NODES} expanded nodes; "
                "the expression requires excessive display expansion")

    def _convert_node(self, expr: object, path: tuple[int, ...], bindings: list[_Binding], occurrence: object) -> DisplayNode:
        if not isinstance(expr, dict):
            self._diagnose("L2T010", "expression occurrence is not an object", path)
            return DisplayNode("invalid", "unknown", metadata={"originalExprKind": type(expr).__name__})
        kind = expr.get("kind")
        if kind == "app":
            return self._convert_app(occurrence, path, bindings)
        if kind == "const":
            name = str(expr.get("name", ""))
            if self.registry.get(name) is None and name not in self.registry.aliases:
                self._diagnose("L2T001", "missing macro configuration", path, name, occurrence)
            return DisplayNode(name, "const", metadata={"leanName": name, "originalExprKind": kind})
        if kind == "lit":
            literal = expr.get("lit", {})
            value = literal.get("value", "?") if isinstance(literal, dict) else "?"
            literal_kind = literal.get("kind") if isinstance(literal, dict) else None
            return DisplayNode(str(value), "literal", metadata={"value": value, "literalKind": literal_kind, "originalExprKind": kind})
        if kind == "fvar":
            return self._convert_fvar(expr, occurrence)
        if kind == "bvar":
            index = expr.get("index", -1)
            if isinstance(index, int) and 0 <= index < len(bindings):
                binding = bindings[index]
                return DisplayNode(binding.name, "bvar", generated=binding.generated,
                                   metadata={"bindRef": binding.bind_id, "index": index})
            self._diagnose("L2T003", f"unbound bvar index {index}", path, expr=occurrence)
            return DisplayNode(f"bvar {index}", "unknown", metadata={"originalExprKind": kind})
        if kind in ("forall", "lam"):
            return self._convert_binder(expr, path, bindings, occurrence)
        if kind == "let":
            return self._convert_let(expr, path, bindings, occurrence)
        if kind == "proj":
            child = self._convert(expr.get("expr"), path + (0,), bindings)
            field = f"{expr.get('typeName', '?')}.{expr.get('index', '?')}"
            return DisplayNode(field, "projection", [child], metadata={"typeName": expr.get("typeName"), "index": expr.get("index")})
        if kind == "sort":
            level = expr.get("level", {})
            name = "Prop" if isinstance(level, dict) and level.get("kind") == "level.zero" else "Type"
            return DisplayNode(name, "sort", metadata={"level": level})
        if kind == "mvar":
            return DisplayNode("?", "metavariable", metadata={"id": expr["id"]})
        self._diagnose("L2T010", f"unknown expression kind {kind!r}", path, expr=occurrence)
        return DisplayNode(str(kind or "missing"), "unknown", metadata={"originalExprKind": kind})

    def _convert_app(self, expr: dict, path, bindings) -> DisplayNode:
        try:
            head, args = flatten_app(expr, visit=self._visit)
        except (AttributeError, KeyError):
            self._diagnose("L2T010", "malformed application", path)
            return DisplayNode("malformed app", "unknown")
        structural_head, _ = unwrap_mdata(head)
        head_name = structural_head.get("name") if structural_head.get("kind") == "const" else None
        if isinstance(head_name, str):
            name = head_name
            canonical_name = self.registry.resolve_alias(name)
            unwrap = self.registry.unwraps.get(name) or self.registry.unwraps.get(canonical_name)
            if unwrap is not None:
                if unwrap.argument < len(args):
                    return self._convert(args[unwrap.argument], path + (unwrap.argument,), bindings)
                self._diagnose("L2T002", f"unwrap argument index {unwrap.argument} out of range for {len(args)} arguments", path, name, expr)
            name = canonical_name
            macro = self.registry.get(name)
            if macro is not None:
                selected = list(macro.arguments)
                if not macro.auto_arity:
                    selected = list(range(len(args)))
                if any(index >= len(args) for index in selected):
                    self._diagnose("L2T002", f"macro argument index out of range for {len(args)} arguments", path, name, expr)
                    converted_head = self._convert(head, path + (0,), bindings)
                    children = [converted_head] + [self._convert(arg, path + (i + 1,), bindings) for i, arg in enumerate(args)]
                    return DisplayNode("application", "application", children, metadata={"headConst": name, "rawArgumentCount": len(args)})
                children = [self._convert(args[index], path + (index,), bindings) for index in selected]
                display = DisplayNode(name, macro.kind, children, metadata={
                    "leanName": name, "headConst": name, "rawArgumentCount": len(args),
                    "selectedArgumentIndices": selected, "originalExprKind": "app",
                })
                return display
            if name == "Exists" and len(args) == 2:
                return DisplayNode("Exists", "exists", [
                    self._convert(args[0], path + (0,), bindings),
                    self._convert(args[1], path + (1,), bindings),
                ], metadata={"headConst": name, "rawArgumentCount": len(args)})
        if head_name is not None:
            self._diagnose("L2T009", "using application fallback", path, head_name, expr)
        return self._application_fallback(head, args, path, bindings, head_name)

    def _application_fallback(self, head, args, path, bindings, name):
        converted_head = self._convert(head, path + (0,), bindings)
        children = [converted_head] + [self._convert(arg, path + (i + 1,), bindings) for i, arg in enumerate(args)]
        return DisplayNode("application", "application", children, metadata={"headConst": name, "rawArgumentCount": len(args)})

    def _convert_fvar(self, expr, occurrence) -> DisplayNode:
        fvar_id = expr["id"]
        _, data = unwrap_mdata(occurrence)
        raw_name = data.get("ProofScript.userName")
        generated = is_anonymous_name(raw_name)
        name = self.allocator.allocate(data.get("ProofScript.type"), fvar_id=fvar_id) if generated else math_name(raw_name)
        return DisplayNode(name, "fvar", generated=generated, metadata={
            "leanName": raw_name, "fvarId": fvar_id,
        })

    def _new_binding(self, expr, occurrence) -> tuple[_Binding, DisplayNode]:
        raw_name = expr.get("name", "")
        _, data = unwrap_mdata(occurrence)
        generated = is_anonymous_name(raw_name)
        name = self.allocator.allocate(data.get("ProofScript.type")) if generated else math_name(raw_name)
        bind_id = f"{self._tree_scope}:b{self._binding_counter}"
        self._binding_counter += 1
        binding = _Binding(name, bind_id, generated)
        binder = DisplayNode(name, "binder", generated=generated, metadata={
            "bindId": bind_id, "leanName": raw_name,
            "binderInfo": expr.get("binderInfo"),
        })
        return binding, binder

    def _convert_binder(self, expr, path, bindings, occurrence) -> DisplayNode:
        binding, binder = self._new_binding(expr, occurrence)
        type_display = self._convert(expr.get("type"), path + (0,), bindings)
        body = self._convert(expr.get("body"), path + (1,), [binding] + bindings)
        kind = "forall" if expr.get("kind") == "forall" else "lambda"
        return DisplayNode(kind, kind, [binder, type_display, body], metadata={
            "isArrow": kind == "forall" and not _uses_outer_bvar(expr.get("body"), visit=self._visit),
            "binderInfo": expr.get("binderInfo"),
        })

    def _convert_let(self, expr, path, bindings, occurrence) -> DisplayNode:
        binding, binder = self._new_binding(expr, occurrence)
        value = self._convert(expr.get("value"), path + (0,), bindings)
        body = self._convert(expr.get("body"), path + (1,), [binding] + bindings)
        return DisplayNode("let", "let", [binder, value, body])

    def _diagnose(self, code, message, path, constant=None, expr=None) -> None:
        self.diagnostics.append(RenderDiagnostic("warning", code, message, constant, path, _source_range(expr)))


def _uses_outer_bvar(expr: object, depth: int = 0, *, visit=None) -> bool:
    """Whether expr references the binder immediately outside it."""
    # A macro can omit a deeply nested source argument from its display tree.
    # Inspecting that source still consumes work, without Python recursion.
    pending = [(expr, depth)]
    while pending:
        current, depth = pending.pop()
        if visit is not None:
            visit()
        current, _ = unwrap_mdata(current, visit=visit)
        if not isinstance(current, dict):
            continue
        kind = current.get("kind")
        if kind == "bvar":
            if current.get("index") == depth:
                return True
            continue
        extra = 1 if kind in ("forall", "lam", "let") else 0
        for key in ("expr", "value", "body", "type", "arg", "fn"):
            value = current.get(key)
            if isinstance(value, dict):
                pending.append((value, depth + extra if key == "body" else depth))
    return False


def _source_range(expr: object) -> dict | None:
    _, data = unwrap_mdata(expr)
    file = data.get("ProofScript.sourceFile")
    start = data.get("ProofScript.sourceStart")
    stop = data.get("ProofScript.sourceStop")
    if isinstance(file, str) and file and type(start) is int and type(stop) is int and 0 <= start <= stop:
        return {"file": file, "start": start, "stop": stop}
    return None
