"""Adapt frozen module Info to the expression rendering model."""

from __future__ import annotations

from dataclasses import dataclass, field

from .macros import DISPLAY_KINDS, OBSOLETE_FIELDS, MacroRegistry, macro_from_data, native_binders
from .model import Unwrap
from .names import validate_names


@dataclass(frozen=True)
class EffectiveConfiguration:
    registry: MacroRegistry
    variable_prefixes: dict[str, str]
    parameter_templates: dict = field(default_factory=dict)
    declaration_names: dict[str, list] = field(default_factory=dict)
    theorem_names: dict[str, tuple[list, str | None]] = field(default_factory=dict)
    declaration_info: dict[str, dict] = field(default_factory=dict)


def interpret(values: dict) -> EffectiveConfiguration:
    """Adapt frozen values without merging events, deriving defaults, or mutating input."""
    registry = MacroRegistry()
    variable_prefixes = {}
    parameter_templates = {}
    declaration_names = {}
    theorem_names = {}
    declaration_info = {}
    for (category, target), fields in values.items():
        if category == "decl":
            if OBSOLETE_FIELDS.intersection(fields):
                raise ValueError(f"L2T008: obsolete declaration fields for {target}")
            validate_names(fields, target)
            if "calc_symbol" not in fields or (fields["calc_symbol"] is not None and
                    (not isinstance(fields["calc_symbol"], str) or not fields["calc_symbol"])):
                raise ValueError(f"L2T008: invalid frozen calc_symbol for {target}")
            declaration_info[target] = dict(fields)
            declaration_names[target] = fields["names"]
            theorem_names[target] = fields["names"], fields.get("name_last_component")
            infos = native_binders(fields)
            if fields["kind"] == "theorem":
                registry.theorems.add(target)
            variable_prefixes[target] = fields["var_name"]
            if fields["kind"] == "theorem":
                continue
            if fields.get("parameter_template") is not None:
                parameter_templates[target] = (fields["parameter_template"], fields["parameter_argument_indices"])
            kind = fields["kind"]
            if kind == "alias":
                if not isinstance(fields["alias_target"], str) or not fields["alias_target"]:
                    raise ValueError(f"L2T008: missing frozen alias_target for {target}")
                registry.aliases[target] = fields["alias_target"]
            elif kind == "wrapper":
                index = fields["wrapper_index"]
                if type(index) is not int or not 0 <= index < len(infos):
                    raise ValueError(f"L2T002: invalid frozen wrapper_index for {target}")
                registry.unwraps[target] = Unwrap(target, index, len(infos))
            elif kind in DISPLAY_KINDS:
                registry.add(macro_from_data({**fields, "name": target}))
            else:
                raise ValueError(f"L2T008: invalid declaration kind {kind}")
    return EffectiveConfiguration(registry, variable_prefixes, parameter_templates,
                                  declaration_names, theorem_names, declaration_info)
