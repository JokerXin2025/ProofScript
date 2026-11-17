"""Public Lean2TeX facade: structural expression occurrence -> DisplayTree -> TeX."""

from __future__ import annotations

from pathlib import Path
import re

from .expr import flatten_app, unwrap_mdata
from .configuration import EffectiveConfiguration
from .macros import MacroRegistry
from .model import DisplayNode, RenderDiagnostic, RenderTarget
from .renderer import LayoutRenderer
from .interactions import ExpressionInteractions
from .semantic import SemanticConverter
from .mixed import atom
from .variable import VariableAllocator
from .names import select_name


class Expr2TeX:
    """Public expression conversion, TeX rendering, and diagnostics."""

    def __init__(self, registry: MacroRegistry | None = None, allocator: VariableAllocator | None = None,
                   *, declaration_names: dict[str, list] | None = None,
                   theorem_names: dict[str, tuple[list, str | None]] | None = None,
                  declaration_info: dict[str, dict] | None = None):
        self.registry = registry or MacroRegistry()
        self.allocator = allocator or VariableAllocator()
        self.converter = SemanticConverter(self.registry, self.allocator)
        self.layout = LayoutRenderer(self.registry, declaration_names, theorem_names)
        self.diagnostics: list[RenderDiagnostic] = []
        self.parameter_templates = {}
        self.interactions: ExpressionInteractions | None = None
        self.theorem_id = ""
        self.language_panel = ""
        self.declaration_info = declaration_info or {}

    @classmethod
    def from_config(cls, config: EffectiveConfiguration) -> Expr2TeX:
        """Create independent per-proof allocation and diagnostic state."""
        renderer = cls(config.registry, VariableAllocator(config.variable_prefixes),
                        declaration_names=config.declaration_names, theorem_names=config.theorem_names,
                        declaration_info=config.declaration_info)
        renderer.parameter_templates = config.parameter_templates
        return renderer

    def render_parameter(self, variable, type_expr, *, language="zh"):
        """Render a declaration without changing ordinary expression styles.

        Substitution is single-pass: generated TeX is never parsed as a template.
        The variable goes through the ordinary fvar renderer, preserving identity.
        """
        diagnostics = []
        # A parameter template may reorder or repeat values. Retain the
        # produced fragments, but only display fragments survive page cleanup.

        def render(expr):
            if self.interactions:
                self.interactions._render_depth += 1
            try:
                result = self.render(expr, parent="Formula", language=language)
            finally:
                if self.interactions:
                    self.interactions._render_depth -= 1
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
                        # These fragments are already inside one $...$ parameter
                        # formula. Render roots here would insert HTML spans into
                        # the math delimiter and prevent auto-render from seeing it.
                        if self.interactions:
                            self.interactions._render_depth += 1
                        try:
                            domain = self.render_display(display.children[1], parent="Formula", language=language)
                            codomain = self.render_display(display.children[2], parent="Formula", language=language)
                        finally:
                            if self.interactions:
                                self.interactions._render_depth -= 1
                        result = f"${name} \\colon {domain} \\to {codomain}$"
                    else:
                        result = f"${name} \\colon {render(type_expr)}$"
                else:
                    result = f"${name} \\colon {render(type_expr)}$"
            if self.interactions:
                self.interactions.collect(result)
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
        label: str | None = None,
        *,
        parent: str = "Text",
        language: str = "zh",
        selections: dict[RenderTarget, str] | None = None,
    ) -> str:
        parent_mode = "text" if parent == "Text" else "formula"
        fragments = self.interactions.register(node, self.theorem_id, self.language_panel) if self.interactions else None
        try:
            tex = self.layout.render(node, label, parent_mode, language=language,
                                     interactions=self.interactions, fragments=fragments,
                                     selections=selections)
        except Exception:
            if self.interactions:
                self.interactions.discard(fragments)
            raise
        if self.interactions:
            self.interactions.collect(tex)
            if self.interactions.enable_render_roots and not self.interactions._render_depth:
                root = self.interactions.add_root(node, fragments, self.registry, language, parent_mode,
                                                   self.layout.declaration_names, self.layout.theorem_names,
                                                  selections=selections, label=label)
                tex = f"[[PS4HTML-ROOT-{root}]]{tex}[[PS4HTML-ENDROOT-{root}]]"
        self.diagnostics.extend(self.layout.diagnostics)
        return tex

    def render(
        self,
        node: dict,
        *,
        parent: str = "Text",
        label: str | None = None,
        language: str = "zh",
        selections: dict[RenderTarget, str] | None = None,
    ) -> str:
        """Render an expression occurrence using the requested style and language."""
        with self.allocator.transaction():
            display = self.convert(node)
            return self.render_display(display, label, parent=parent, language=language,
                                       selections=selections)

    def render_relation(self, relation: dict) -> str | None:
        """Return literal calc text, or None for the ordinary-expression fallback.

        Alias lookup uses the final frozen record, while the visible fragment
        keeps the original constant's identity. The caller must HTML-escape
        this text and exclude it from formula parsing.
        """
        display = self.converter.convert_relation_head(relation)
        self.diagnostics = list(self.converter.diagnostics)
        if display is None:
            return None
        name = self.registry.resolve_alias(display.metadata["leanName"])
        fields = self.declaration_info.get(name)
        symbol = name if fields is None else (
            fields["calc_symbol"] if fields["calc_symbol"] is not None else
            select_name(fields["names"], self.language_panel or "zh", name))
        self.layout._check_length(len(symbol), self.layout.MAX_OUTPUT_CHARACTERS, "calc symbol")
        if self.interactions:
            mapping = self.interactions.register(display, self.theorem_id, self.language_panel)
            fragment = self.interactions.new_fragment(mapping[id(display)])
            symbol = atom(symbol, "plain", fragment)
            try:
                self.layout._check_length(len(symbol), self.layout.MAX_OUTPUT_CHARACTERS, "calc symbol")
            except Exception:
                self.interactions.discard(mapping)
                raise
            self.interactions.collect(symbol)
        return symbol


def load(export_root: str | Path, module: str) -> Expr2TeX:
    """Load frozen Info from an exported module document."""
    import json
    from Lean2TeX.configuration import interpret
    from PS4HTML.info import name_text

    root = Path(export_root)
    path = root / "info" / Path(*module.split("."))
    document = json.loads(path.with_suffix(".json").read_text(encoding="utf-8"))
    values = {}
    for record in document["records"]:
        identity = record["identity"]
        kind = identity["kind"]
        if kind != "decl":
            continue
        target = name_text(identity["target"])
        fields = {key: value for key, value in record["value"].items() if key != "extra"}
        fields["name_last_component"] = name_text([identity["target"][-1]])
        if fields["alias_target"] is not None and not isinstance(fields["alias_target"], str):
            fields["alias_target"] = name_text(fields["alias_target"])
        values[kind, target] = fields
    return Expr2TeX.from_config(interpret(values))
