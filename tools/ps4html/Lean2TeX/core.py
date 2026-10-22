"""Public Lean2TeX facade: structural expression occurrence -> DisplayTree -> TeX."""

from __future__ import annotations

from pathlib import Path

from .expr import flatten_app
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

    @classmethod
    def from_config(cls, config: EffectiveConfiguration) -> Expr2TeX:
        """Create independent per-proof allocation and diagnostic state."""
        return cls(config.registry, VariableAllocator(list(config.variables)))

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
        display = self.convert(node)
        return self.render_display(display, style, parent=parent, language=language)

    def render_relation(self, relation: object) -> str:
        """Render a calc relation through a stable public API."""
        if not isinstance(relation, dict):
            return "" if relation is None else str(relation)
        head, _ = flatten_app(relation)
        if head.get("kind") == "const":
            return self.registry.rel_symbol(str(head.get("name", "")))
        return self.render(relation)


def load(export_root: str | Path, module: str, *, snapshot_id=None) -> Expr2TeX:
    """Load a consumed module view, or explicitly select one persisted snapshot."""
    from PS4HTML.info import InfoBundle
    return Expr2TeX.from_config(InfoBundle(export_root).configuration(module, snapshot_id))
