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


def _renderer_template(template):
    """Translate schema-validated binder pairs to the renderer's lookup table."""
    return {**template, "binders": {str(index): count for index, count in template["binders"]}}


def interpret(values: dict) -> EffectiveConfiguration:
    """Adapt frozen values without merging events, deriving defaults, or mutating input."""
    registry = MacroRegistry()
    variable_prefixes = {}
    parameter_templates = {}
    for (category, target), fields in values.items():
        if category == "definition":
            if isinstance(fields.get("declaration"), dict):
                registry.declarations[target] = fields["declaration"]
            variable_prefixes[target] = fields["var_name"]
            if fields.get("parameter_template") is not None:
                parameter_templates[target] = (fields["parameter_template"], fields.get("parameter_argument_indices", fields.get("argument_indices", [])))
            kind = fields["kind"]
            if kind == "relation":
                registry.relations[target] = fields["relation_info"]["symbol"]
            if kind == "alias":
                if fields["alias_info"]["target"] is not None:
                    registry.aliases[target] = fields["alias_info"]["target"]
            elif kind == "wrapper":
                if fields["wrapper_info"]["index"] is not None:
                    registry.unwraps[target] = Unwrap(target, fields["wrapper_info"]["index"])
            elif kind in ("operator", "relation"):
                registry.add(macro_from_data({
                    "name": target, "kind": kind,
                    "argument_indices": fields.get("argument_indices", []),
                    "symbol": fields[f"{kind}_info"]["symbol"],
                    "operator_info": fields["operator_info"]}))
            elif kind == "concept" and fields["concept_info"]["templates"]:
                concept = fields["concept_info"]
                registry.add(macro_from_data({
                    "name": target, "kind": kind,
                    "argument_indices": fields.get("argument_indices", []),
                    "auto_arity": concept["auto_arity"],
                    "default": concept["default"],
                    "templates": [_renderer_template(template)
                                  for template in concept["templates"]]}))
    return EffectiveConfiguration(registry, variable_prefixes, parameter_templates)
