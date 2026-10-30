"""Public Lean2TeX facade: structural expression occurrence -> DisplayTree -> TeX."""

from __future__ import annotations

from pathlib import Path
import re

from .expr import flatten_app, unwrap_mdata
from .configuration import EffectiveConfiguration
from .macros import MacroRegistry
from .model import DisplayNode, RenderDiagnostic
from .renderer import LayoutRenderer
from .semantic import SemanticConverter
from .variable import VariableAllocator


class Expr2TeX:
    """Public expression conversion, TeX rendering, and diagnostics."""

    def __init__(self, registry: MacroRegistry | None = None, allocator: VariableAllocator | None = None):
        self.registry = registry or MacroRegistry()
        self.allocator = allocator or VariableAllocator()
        self.converter = SemanticConverter(self.registry, self.allocator)
        self.layout = LayoutRenderer(self.registry)
        self.diagnostics: list[RenderDiagnostic] = []
        self.parameter_templates = {}

    @classmethod
    def from_config(cls, config: EffectiveConfiguration) -> Expr2TeX:
        """Create independent per-proof allocation and diagnostic state."""
        renderer = cls(config.registry, VariableAllocator(config.variable_prefixes))
        renderer.parameter_templates = config.parameter_templates
        return renderer

    def render_parameter(self, variable, type_expr, *, language="zh"):
        """Render a declaration without changing ordinary expression styles.

        Substitution is single-pass: generated TeX is never parsed as a template.
        The variable goes through the ordinary fvar renderer, preserving identity.
        """
        diagnostics = []

        def render(expr):
            result = self.render(expr, parent="Formula", language=language)
            diagnostics.extend(self.diagnostics)
            return result

        with self.allocator.transaction():
            name = render(variable)
            head, args = flatten_app(type_expr)
            head, _ = unwrap_mdata(head)
            configured = self.parameter_templates.get(head.get("name")) if head.get("kind") == "const" else None
            if configured is not None:
                template, indices = configured
                values = {"self": name}

                def substitute(match):
                    key = match.group(1)
                    if key not in values:
                        if key == "type":
                            values[key] = render(type_expr)
                        else:
                            index = int(key)
                            if index >= len(indices) or indices[index] >= len(args):
                                raise ValueError(f"Parameter template for {head['name']} references missing #{key}")
                            values[key] = render(args[indices[index]])
                    return values[key]

                result = re.sub(r"#(self\b|type\b|[0-9]+)", substitute, template)
            else:
                structural, _ = unwrap_mdata(type_expr)
                if structural.get("kind") == "forall":
                    display = self.convert(type_expr)
                    diagnostics.extend(self.diagnostics)
                    if display.metadata.get("isArrow"):
                        domain = self.render_display(display.children[1], parent="Formula", language=language)
                        codomain = self.render_display(display.children[2], parent="Formula", language=language)
                        result = f"${name} \\colon {domain} \\to {codomain}$"
                    else:
                        result = f"${name} \\colon {render(type_expr)}$"
                else:
                    result = f"${name} \\colon {render(type_expr)}$"
            self.diagnostics = diagnostics
            return result

    def reset(self) -> None:
        self.allocator.reset()
        self.diagnostics.clear()

    def diagnostics_dict(self) -> list[dict]:
        return [diagnostic.as_dict() for diagnostic in self.diagnostics]

    def convert(self, node: dict) -> DisplayNode:
        """Convert one expression occurrence into a renderer-independent DisplayTree."""
        display = self.converter.convert(node)
        self.diagnostics = list(self.converter.diagnostics)
        return display

    def render_display(
        self,
        node: DisplayNode,
        style: str = "formula",
        *,
        parent: str = "Text",
        language: str = "zh",
    ) -> str:
        parent_mode = "text" if parent == "Text" else "formula"
        tex = self.layout.render(node, style, parent_mode, language=language)
        self.diagnostics.extend(self.layout.diagnostics)
        return tex

    def render(
        self,
        node: dict,
        *,
        parent: str = "Text",
        style: str = "formula",
        language: str = "zh",
    ) -> str:
        """Render an expression occurrence using the requested style and language."""
        with self.allocator.transaction():
            display = self.convert(node)
            return self.render_display(display, style, parent=parent, language=language)

    def render_relation(self, relation: object) -> str:
        """Render a calc relation through a stable public API."""
        if not isinstance(relation, dict):
            return "" if relation is None else str(relation)
        head, _ = flatten_app(relation)
        head, _ = unwrap_mdata(head)
        if head.get("kind") == "const":
            return self.registry.rel_symbol(str(head.get("name", "")))
        return self.render(relation)


def load(export_root: str | Path, module: str, *, snapshot_id=None) -> Expr2TeX:
    """Load a consumed module view, or explicitly select one persisted snapshot."""
    from PS4HTML.info import InfoBundle
    return Expr2TeX.from_config(InfoBundle(export_root).configuration(module, snapshot_id))
