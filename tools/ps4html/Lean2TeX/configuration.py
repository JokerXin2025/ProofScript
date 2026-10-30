"""Adapt validated, normalized Info snapshots to the expression rendering model."""

from __future__ import annotations

from dataclasses import dataclass, field

from .macros import MacroRegistry, macro_from_data
from .model import Unwrap


@dataclass(frozen=True)
class EffectiveConfiguration:
    registry: MacroRegistry
    variable_prefixes: dict[str, str]
    parameter_templates: dict = field(default_factory=dict)


def _renderer_style(style):
    """Translate schema-validated binder pairs to the renderer's lookup table."""
    return {**style, "binders": {str(index): count for index, count in style["binders"]}}


def interpret(values: dict) -> EffectiveConfiguration:
    """Adapt frozen values without merging events, deriving defaults, or mutating input."""
    registry = MacroRegistry()
    variable_prefixes = {}
    parameter_templates = {}
    for (category, target), fields in values.items():
        if category == "definition":
            variable_prefixes[target] = fields["var_name"]
            if fields.get("parameter_template") is not None:
                parameter_templates[target] = (fields["parameter_template"], fields.get("argument_indices", []))
            if fields["alias"] is not None:
                registry.aliases[target] = fields["alias"]
            elif fields["unwrap"] is not None:
                registry.unwraps[target] = Unwrap(target, fields["unwrap"])
            else:
                if fields["styles"]:
                    registry.add(macro_from_data({
                        "name": target, "kind": fields["kind"],
                        "argument_indices": fields.get("argument_indices", []),
                        "auto_arity": fields.get("auto_arity", True),
                        "calc_symbol": fields.get("calc_symbol"),
                        "styles": [_renderer_style(style) for style in fields["styles"]]}))
                elif fields.get("calc_symbol") is not None:
                    registry.add(macro_from_data({
                        "name": target, "kind": fields["kind"],
                        "argument_indices": fields.get("argument_indices", []),
                        "auto_arity": fields.get("auto_arity", True),
                        "calc_symbol": fields["calc_symbol"],
                        "styles": []}))
        elif category == "phrase":
            registry.phrases[target] = {entry["lang"]: entry["content"] for entry in fields["template"]}
    return EffectiveConfiguration(registry, variable_prefixes, parameter_templates)
