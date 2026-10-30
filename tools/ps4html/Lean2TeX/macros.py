"""Semantic macro configuration, aliases, unwrap rules, and validation."""

from __future__ import annotations

import re

from .model import Macro, MacroStyle, Unwrap


FIXITIES = {"atom", "prefix", "postfix", "infix", "binder", "application", "custom"}
ASSOCIATIVITIES = {"left", "right", "none"}
MODES = {"formula", "text"}
_PLACEHOLDER = re.compile(r"#(\d+)")
_BINDER = re.compile(r"(?<!@)(@+)(\d+)(?!\d)")


class MacroRegistry:
    def __init__(self, macros: dict[str, Macro] | None = None, aliases: dict[str, str] | None = None, unwraps: dict[str, Unwrap] | None = None, relations: dict[str, str] | None = None, phrases: dict[str, dict[str, str]] | None = None):
        self.macros = macros or {}
        self.aliases = aliases or {}
        self.unwraps = unwraps or {}
        self.relations = relations or {}
        self.phrases = phrases or {}

    def rel_symbol(self, name: str) -> str:
        return self.relations.get(self.resolve_alias(name), name)

    def get(self, name: str) -> Macro | None:
        return self.macros.get(self.resolve_alias(name))

    def resolve_alias(self, name: str) -> str:
        seen: set[str] = set()
        current = name
        while current in self.aliases:
            if current in seen:
                raise ValueError(f"L2T007: alias cycle involving {current}")
            seen.add(current)
            current = self.aliases[current]
        return current

    def add(self, macro: Macro, *, replace: bool = False) -> None:
        if macro.name in self.macros and not replace:
            raise ValueError(f"L2T005: duplicate macro {macro.name}")
        self.macros[macro.name] = macro

    def style(self, macro: Macro, requested: str, node=None) -> MacroStyle:
        for name in (requested, "formula"):
            for style in macro.styles:
                if style.name != name:
                    continue
                if not _selectors_match(style, node):
                    continue
                return style
        raise ValueError(f"L2T006: macro {macro.name} has no usable style")

    def phrase(self, name: str, language: str) -> str | None:
        values = self.phrases.get(name, {})
        return values.get(language) or values.get("en") or values.get("zh")


def _selectors_match(style: MacroStyle, node) -> bool:
    if node is None:
        return not style.binders
    for index, required in style.binders.items():
        if index >= len(node.children):
            return False
        child = node.children[index]
        for _ in range(required):
            if child.kind != "lambda" or len(child.children) != 3:
                return False
            child = child.children[2]
    return True

def macro_from_data(entry: dict) -> Macro:
    """Validate one macro independently of its configuration source."""
    arguments = entry.get("argument_indices", [])
    if not isinstance(arguments, list) or not all(type(i) is int and i >= 0 for i in arguments):
        raise ValueError(f"L2T002: invalid arguments for macro {entry.get('name')}")
    arguments = tuple(arguments)
    auto_arity = bool(entry.get("auto_arity", True))
    styles = tuple(_parse_style(entry["name"], raw, auto_arity) for raw in entry.get("styles", []))
    calc_symbol = entry.get("calc_symbol")
    if not styles and calc_symbol is None:
        raise ValueError(f"L2T004: macro {entry['name']} has no styles")
    if any(_BINDER.search(style.template) for style in styles) and not any(
        not _BINDER.search(style.template) for style in styles
    ):
        raise ValueError(f"L2T004: macro {entry['name']} needs a style without @ selectors")
    for style in styles:
        refs = [int(value) for value in _PLACEHOLDER.findall(style.template)]
        binders = [(len(prefix), int(index)) for prefix, index in _BINDER.findall(style.template)]
        if any(index not in style.binders or depth > style.binders[index] + 1 for depth, index in binders):
            raise ValueError(f"L2T004: @ selector needs a matching binder count in macro {entry['name']}")
        if auto_arity:
            if any(index >= len(arguments) for index in refs) or any(index >= len(arguments) for _, index in binders):
                raise ValueError(f"L2T004: template references a missing child in macro {entry['name']}")
            if any(index >= len(arguments) for index in style.isolated_arguments):
                raise ValueError(f"L2T004: isolated_arguments references a missing child in macro {entry['name']}")
        referenced = set(refs) | {index for _, index in binders}
        if auto_arity and any(index not in referenced for index in style.isolated_arguments):
            raise ValueError(f"L2T004: isolated_arguments must reference a template argument in macro {entry['name']}")
    return Macro(entry["name"], entry.get("kind", "const"), arguments, styles,
                 bool(entry.get("auto_arity", True)), entry.get("calc_symbol"))


def _parse_style(macro_name: str, raw: dict, auto_arity: bool) -> MacroStyle:
    mode = raw.get("mode", "formula")
    fixity = raw.get("fixity", "custom")
    associativity = raw.get("associativity", "none")
    precedence = raw.get("precedence", 100)
    template = raw.get("template", "")
    if not isinstance(template, str):
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
    if mode not in MODES or fixity not in FIXITIES or associativity not in ASSOCIATIVITIES:
        raise ValueError(f"L2T008: invalid layout for macro {macro_name}")
    if not isinstance(precedence, int) or not 0 <= precedence <= 100:
        raise ValueError(f"L2T008: invalid precedence for macro {macro_name}")
    if "#*" in template:
        raise ValueError(f"L2T004: dynamic placeholder is no longer supported for macro {macro_name}")
    refs = sorted({int(value) for value in _PLACEHOLDER.findall(template)} | {
        int(index) for _, index in _BINDER.findall(template)
    })
    if refs and auto_arity and refs != list(range(refs[-1] + 1)):
        raise ValueError(f"L2T004: non-contiguous placeholders for macro {macro_name}")
    return MacroStyle(
        raw.get("name", "formula"), mode, template, fixity, precedence,
        associativity,
        {int(key): value for key, value in binder_counts.items()},
        frozenset(isolated),
    )
