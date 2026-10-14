"""Public Lean2TeX facade: ExprJSON -> DisplayTree -> TeX."""

from __future__ import annotations

from pathlib import Path

from .expr import flatten_app
from .configuration import ConfigurationIndex, EffectiveConfiguration
from .macros import MacroRegistry
from .model import DisplayNode, RenderDiagnostic
from .renderer import LayoutRenderer
from .semantic import SemanticConverter
from .variable import VariableAllocator


class Expr2TeX:
    """Compatibility facade over the semantic converter and layout renderer."""

    def __init__(self, registry: MacroRegistry | None = None, allocator: VariableAllocator | None = None):
        self.registry = registry or MacroRegistry()
        self.allocator = allocator or VariableAllocator()
        self.converter = SemanticConverter(self.registry, self.allocator)
        self.layout = LayoutRenderer(self.registry)
        self.diagnostics: list[RenderDiagnostic] = []

    @classmethod
    def from_config(cls, config: EffectiveConfiguration) -> Expr2TeX:
        """Create independent per-proof allocation and diagnostic state."""
        return cls(config.registry, VariableAllocator(list(config.variables)))

    @classmethod
    def from_export(cls, export_root: str | Path, module: str) -> Expr2TeX:
        """Load the Lean-owned configuration visible to a proof module."""
        return cls.from_config(ConfigurationIndex(export_root).effective(module))

    def reset(self) -> None:
        self.allocator.reset()
        self.diagnostics.clear()

    def diagnostics_dict(self) -> list[dict]:
        return [diagnostic.as_dict() for diagnostic in self.diagnostics]

    def convert(
        self,
        node: dict,
        fvars: dict[str, str] | None = None,
        bvar_env: list[str] | None = None,
    ) -> DisplayNode:
        """Convert one ExprJSON object into a renderer-independent DisplayTree."""
        display = self.converter.convert(node, fvars, bvar_env)
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
        role: str = "only",
        parent: str = "Text",
        styles: tuple[str, ...] = ("Root",),
        fvars: dict[str, str] | None = None,
        bvar_env: list[str] | None = None,
        style: str = "formula",
        language: str = "zh",
    ) -> str:
        """Render ExprJSON while retaining the historical call signature."""
        display = self.convert(node, fvars, bvar_env)
        return self.render_display(display, style, parent=parent, language=language)

    def render_relation(self, relation: object) -> str:
        """Render a calc relation through a stable public API."""
        if not isinstance(relation, dict):
            return "" if relation is None else str(relation)
        exported_head = relation.get("headConstant")
        if isinstance(exported_head, str):
            return self.registry.rel_symbol(exported_head)
        head, _ = flatten_app(relation)
        if head.get("kind") == "const":
            return self.registry.rel_symbol(str(head.get("name", "")))
        return self.render(relation)


def load(export_root: str | Path, module: str) -> Expr2TeX:
    """Load Lean-owned configuration visible to a proof module."""
    return Expr2TeX.from_export(export_root, module)
