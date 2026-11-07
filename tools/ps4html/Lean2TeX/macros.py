"""Semantic macro configuration, aliases, unwrap rules, and validation."""

from __future__ import annotations

import re

from .model import DisplayTemplate, Macro, Unwrap, visible_node


FIXITIES = {"atom", "prefix", "postfix", "infix", "binder", "application", "custom"}
ASSOCIATIVITIES = {"left", "right", "none"}
MODES = {"formula", "text"}
_PLACEHOLDER = re.compile(r"#(\d+)")
_BINDER = re.compile(r"(?<!@)(@+)(\d+)(?!\d)")


class MacroRegistry:
    def __init__(self, macros: dict[str, Macro] | None = None, aliases: dict[str, str] | None = None, unwraps: dict[str, Unwrap] | None = None, relations: dict[str, str] | None = None, declarations: dict[str, dict] | None = None):
        self.macros = macros or {}
        self.aliases = aliases or {}
        self.unwraps = unwraps or {}
        self.relations = relations or {}
        self.declarations = declarations or {}

    def rel_symbol(self, name: str) -> str:
        return self.relations.get(self.resolve_alias(name), name)

    def get(self, name: str) -> Macro | None:
        return self.macros.get(self.resolve_alias(name))

    def resolve_alias(self, name: str) -> str:
        return self.alias_chain(name)[-1]

    def alias_chain(self, name: str) -> tuple[str, ...]:
        seen: set[str] = set()
        current = name
        chain = [name]
        while current in self.aliases:
            if current in seen:
                raise ValueError(f"L2T007: alias cycle involving {current}")
            seen.add(current)
            current = self.aliases[current]
            chain.append(current)
        return tuple(chain)

    def add(self, macro: Macro, *, replace: bool = False) -> None:
        if macro.name in self.macros and not replace:
            raise ValueError(f"L2T005: duplicate macro {macro.name}")
        self.macros[macro.name] = macro

    def labels(self, macro: Macro, language: str) -> tuple[str, ...]:
        """Return selectable labels available in one language, preserving order."""
        result: list[str] = []
        for template in macro.templates:
            if template.language is not None and template.language != language:
                continue
            if template.label not in result:
                result.append(template.label)
        return tuple(result)

    def template_for(self, macro: Macro, requested: str | None = None, node=None,
                     language: str = "zh") -> DisplayTemplate:
        """Select a unique template by label, language, and structural guards.

        ``None`` means the configured default label. Formula is the final
        language-independent fallback when the requested label is unavailable.
        """
        label = macro.default_label if requested is None else requested
        candidates = self._templates_for(macro, label, language, node)
        if not candidates and requested is not None:
            label = macro.default_label
            candidates = self._templates_for(macro, label, language, node)
        if not candidates and label != "formula":
            candidates = self._templates_for(macro, "formula", language, node)
        if not candidates and label != "formula":
            candidates = self._templates_for(macro, label, "en", node)
        if not candidates:
            raise ValueError(f"L2T006: macro {macro.name} has no usable template")
        return candidates[0]

    def _templates_for(self, macro: Macro, label: str, language: str, node=None) -> list[DisplayTemplate]:
        return [template for template in macro.templates
                if template.label == label
                and (template.language is None or template.language == language)
                and _selectors_match(template, node)]

def _selectors_match(template: DisplayTemplate, node) -> bool:
    if node is None:
        return not template.binders
    for index, required in template.binders.items():
        if index >= len(node.children):
            return False
        child = visible_node(node.children[index])
        for _ in range(required):
            if child.kind != "lambda" or len(child.children) != 3:
                return False
            child = visible_node(child.children[2])
    return True

def macro_from_data(entry: dict) -> Macro:
    """Validate one macro independently of its configuration source."""
    arguments = entry.get("argument_indices", [])
    if not isinstance(arguments, list) or not all(type(i) is int and i >= 0 for i in arguments):
        raise ValueError(f"L2T002: invalid arguments for macro {entry.get('name')}")
    arguments = tuple(arguments)
    kind = entry.get("kind", "concept")
    if kind in ("operator", "relation"):
        symbol = entry.get("symbol")
        layout = entry.get("operator_info") or {}
        fixity = layout.get("fixity", "infix") if kind == "operator" else "infix"
        precedence = layout.get("precedence", 100) if kind == "operator" else 50
        associativity = layout.get("associativity", "none") if kind == "operator" else "none"
        if not isinstance(symbol, str) or not symbol or fixity not in ("prefix", "postfix", "infix") or type(precedence) is not int or not 0 <= precedence <= 100 or associativity not in ASSOCIATIVITIES:
            raise ValueError(f"L2T008: invalid symbolic {kind} configuration for macro {entry['name']}")
        return Macro(entry["name"], kind, arguments, (), True, symbol, "formula",
                     fixity, precedence, associativity)
    if kind != "concept":
        raise ValueError(f"L2T008: invalid macro kind {kind}")
    auto_arity = bool(entry.get("auto_arity", True))
    templates = tuple(_parse_template(entry["name"], raw, auto_arity)
                      for raw in entry.get("templates", []))
    if not templates:
        raise ValueError(f"L2T004: macro {entry['name']} has no templates")
    default = entry["default"]
    if not isinstance(default, str) or not default:
        raise ValueError(f"L2T008: missing default template label for macro {entry['name']}")
    keys = [(template.label, template.language) for template in templates]
    if len(keys) != len(set(keys)):
        raise ValueError(f"L2T008: duplicate template label and language for macro {entry['name']}")
    if not any(template.label == "formula" or template.language == "en" for template in templates):
        raise ValueError(f"L2T008: macro {entry['name']} needs a formula or en template")
    if not any(template.label == default and (default == "formula" or template.language == "en")
               for template in templates):
        raise ValueError(f"L2T008: invalid default template label for macro {entry['name']}")
    if any(_BINDER.search(template.content) for template in templates) and not any(
        not _BINDER.search(template.content) for template in templates
    ):
        raise ValueError(f"L2T004: macro {entry['name']} needs a template without @ selectors")
    for template in templates:
        refs = [int(value) for value in _PLACEHOLDER.findall(template.content)]
        binders = [(len(prefix), int(index)) for prefix, index in _BINDER.findall(template.content)]
        if any(index not in template.binders or depth > template.binders[index] + 1 for depth, index in binders):
            raise ValueError(f"L2T004: @ selector needs a matching binder count in macro {entry['name']}")
        if auto_arity:
            if any(index >= len(arguments) for index in refs) or any(index >= len(arguments) for _, index in binders):
                raise ValueError(f"L2T004: template references a missing child in macro {entry['name']}")
            if any(index >= len(arguments) for index in template.isolated_arguments):
                raise ValueError(f"L2T004: isolated_arguments references a missing child in macro {entry['name']}")
        referenced = set(refs) | {index for _, index in binders}
        if auto_arity and any(index not in referenced for index in template.isolated_arguments):
            raise ValueError(f"L2T004: isolated_arguments must reference a template argument in macro {entry['name']}")
    return Macro(entry["name"], kind, arguments, templates,
                 auto_arity, None,
                 default)


def _parse_template(macro_name: str, raw: dict, auto_arity: bool) -> DisplayTemplate:
    mode = raw.get("mode", "formula")
    content = raw.get("content", "")
    if not isinstance(content, str):
        raise ValueError(f"L2T008: invalid template for macro {macro_name}")
    binder_counts = raw.get("binders", {})
    isolated = raw.get("isolated_arguments", [])
    if not isinstance(isolated, list) or any(type(index) is not int or index < 0 for index in isolated) or len(isolated) != len(set(isolated)):
        raise ValueError(f"L2T008: invalid isolated_arguments for macro {macro_name}")
    if not isinstance(binder_counts, dict) or any(
        not isinstance(key, str) or not key.isdecimal() or type(value) is not int or value < 1
        for key, value in binder_counts.items()
    ):
        raise ValueError(f"L2T008: invalid binder counts for macro {macro_name}")
    if mode not in MODES:
        raise ValueError(f"L2T008: invalid mode for macro {macro_name}")
    label = raw.get("label")
    language = raw.get("lang")
    if not isinstance(label, str) or not label or any(ord(char) < 32 or ord(char) > 126 for char in label):
        raise ValueError(f"L2T008: invalid template label for macro {macro_name}")
    if language is not None and (not isinstance(language, str) or not language):
        raise ValueError(f"L2T008: invalid template language for macro {macro_name}")
    if label == "formula" and language is not None:
        raise ValueError(f"L2T008: formula template must not specify lang for macro {macro_name}")
    if label != "formula" and language is None:
        raise ValueError(f"L2T008: non-formula template must specify lang for macro {macro_name}")
    if "#*" in content:
        raise ValueError(f"L2T004: dynamic placeholder is no longer supported for macro {macro_name}")
    refs = sorted({int(value) for value in _PLACEHOLDER.findall(content)} | {
        int(index) for _, index in _BINDER.findall(content)
    })
    if refs and auto_arity and refs != list(range(refs[-1] + 1)):
        raise ValueError(f"L2T004: non-contiguous placeholders for macro {macro_name}")
    return DisplayTemplate(
        label, mode, content,
        "atom", 100, "none",
        {int(key): value for key, value in binder_counts.items()},
        frozenset(isolated),
        language,
    )
