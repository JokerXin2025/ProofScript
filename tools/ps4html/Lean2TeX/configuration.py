"""Adapt validated, normalized Info snapshots to the expression rendering model."""

from __future__ import annotations

from dataclasses import dataclass

from .macros import MacroRegistry, macro_from_data
from .model import Unwrap
from .variable import VarTypeConfig


@dataclass(frozen=True)
class EffectiveConfiguration:
    registry: MacroRegistry
    variables: tuple[VarTypeConfig, ...]


def _renderer_style(style):
    """Translate schema-validated binder pairs to the renderer's lookup table."""
    return {**style, "binders": {str(index): count for index, count in style["binders"]}}


def interpret(values: dict) -> EffectiveConfiguration:
    """Adapt frozen values without merging events, deriving defaults, or mutating input."""
    registry = MacroRegistry()
    variables = []
    for (category, target), fields in values.items():
        if category == "definition":
            if fields["alias"] is not None:
                registry.aliases[target] = fields["alias"]
            elif fields["unwrap"] is not None:
                registry.unwraps[target] = Unwrap(target, fields["unwrap"])
            else:
                if fields["calc_symbol"] is not None:
                    registry.relations[target] = fields["calc_symbol"]
                registry.add(macro_from_data({
                    "name": target, "kind": fields["kind"],
                    "arguments": fields["arguments"], "dynamic_arity": fields["dynamic_arity"],
                    "styles": [_renderer_style(style) for style in fields["styles"]]}))
        elif category == "phrase":
            registry.phrases[target] = {entry["lang"]: entry["content"] for entry in fields["template"]}
        elif category == "variable":
            variables.append(VarTypeConfig(target, fields["default"], list(fields["names"])))
    return EffectiveConfiguration(registry, tuple(variables))
