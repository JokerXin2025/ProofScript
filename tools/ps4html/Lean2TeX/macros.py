"""Frozen declaration templates, aliases, and structural/language selection."""

from __future__ import annotations

from .model import DisplayTemplate, Macro, TemplateInstruction, Unwrap, visible_node


DISPLAY_KINDS = frozenset({"concept", "relation", "operator"})
BUILTIN_LABELS = frozenset({"$relation", "$prefix", "$infix", "$infixl", "$infixr", "$postfix"})
MODES = frozenset({"formula", "text"})
BINDER_INFOS = frozenset({"explicit", "implicit", "strictImplicit", "instance"})
OBSOLETE_FIELDS = frozenset({"concept_info", "relation_info", "operator_info", "wrapper_info", "alias_info"})


class MacroRegistry:
    def __init__(self):
        self.macros: dict[str, Macro] = {}
        self.aliases: dict[str, str] = {}
        self.unwraps: dict[str, Unwrap] = {}
        self.theorems: set[str] = set()

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

    def add(self, macro: Macro) -> None:
        if macro.name in self.macros:
            raise ValueError(f"L2T005: duplicate macro {macro.name}")
        self.macros[macro.name] = macro

    def labels(self, macro: Macro, language: str, node=None) -> tuple[str, ...]:
        """Available labels in list order, including neutral and English fallback."""
        languages = _languages(language)
        return tuple(dict.fromkeys(template.label for template in macro.templates
                                   if template.language in languages and
                                   (node is None or _selectors_match(template, node))))

    def template_for(self, macro: Macro, requested: str | None = None, node=None,
                     language: str = "zh") -> DisplayTemplate | None:
        """Requested label, frozen default, then remaining labels; never guess a default.

        A label tries current language, neutral, and English, in that order.
        Unavailable languages and failed binder guards are ordinary fallbacks.
        """
        if node is not None and len(node.children) != macro.arity:
            return None
        labels = dict.fromkeys([requested, macro.default_label, *(item.label for item in macro.templates)])
        languages = _languages(language)
        templates = {template.identity: template for template in macro.templates}
        for label in labels:
            if label is None:
                continue
            for lang in languages:
                template = templates.get((label, lang))
                if template is not None and _selectors_match(template, node):
                    return template
        return None


def _languages(language: str) -> tuple[str | None, ...]:
    return tuple(dict.fromkeys((language, None, "en")))


def _selectors_match(template: DisplayTemplate, node) -> bool:
    if node is None:
        return not template.binder_requirements
    for index, required in template.binder_requirements.items():
        raw_index = template.argument_indices[index]
        if raw_index >= len(node.children):
            return False
        child = visible_node(node.children[raw_index])
        for _ in range(required):
            if child.kind != "lambda" or len(child.children) != 3:
                return False
            child = visible_node(child.children[2])
    return True


def native_binders(entry: dict) -> tuple[str, ...]:
    """Validate declaration facts without reconstructing them from template use."""
    arity = entry.get("arity")
    infos = entry.get("binder_infos")
    if (type(arity) is not int or arity < 0 or not isinstance(infos, list) or
            len(infos) != arity or any(not isinstance(info, str) or info not in BINDER_INFOS for info in infos)):
        raise ValueError(f"L2T002: invalid frozen native binders for {entry.get('name')}")
    return tuple(infos)


def macro_from_data(entry: dict) -> Macro:
    """Consume current frozen data, including instructions and per-template maps.

    Content is retained for inspection only. Python never recompiles selectors,
    infers template defaults, or accepts the old nested declaration format.
    """
    name = entry.get("name")
    kind = entry.get("kind")
    if (not isinstance(name, str) or not name or not isinstance(kind, str) or kind not in DISPLAY_KINDS or
            OBSOLETE_FIELDS.intersection(entry) or "argument_indices" in entry):
        raise ValueError(f"L2T008: invalid frozen declaration {name}")
    infos = native_binders(entry)
    if "default_template" not in entry or (entry["default_template"] is not None and
            (not isinstance(entry["default_template"], str) or not entry["default_template"])):
        raise ValueError(f"L2T008: missing or invalid frozen default_template for {name}")
    raw_templates = entry.get("templates")
    if not isinstance(raw_templates, list):
        raise ValueError(f"L2T008: missing frozen templates for {name}")
    templates = tuple(_parse_template(name, raw, infos) for raw in raw_templates)
    keys = [template.identity for template in templates]
    if len(keys) != len(set(keys)):
        raise ValueError(f"L2T008: duplicate template label and language for {name}")
    return Macro(name, kind, len(infos), templates, entry["default_template"])


def _indices(value) -> bool:
    return isinstance(value, list) and all(type(index) is int and index >= 0 for index in value)


def _parse_template(name: str, raw: dict, infos: tuple[str, ...]) -> DisplayTemplate:
    fields = {"label", "lang", "mode", "content", "auto_arity",
               "precedence", "argument_indices", "instructions"}
    if not isinstance(raw, dict) or set(raw) != fields:
        raise ValueError(f"L2T008: incomplete or unknown frozen template fields for {name}")
    label, language, mode = raw["label"], raw["lang"], raw["mode"]
    if (not isinstance(label, str) or not label or any(ord(char) < 32 or ord(char) > 126 for char in label) or
            (label.startswith("$") and (label not in BUILTIN_LABELS or language is not None)) or
            (language is not None and (not isinstance(language, str) or not language)) or
            not isinstance(mode, str) or mode not in MODES or not isinstance(raw["content"], str) or not raw["content"] or
            type(raw["auto_arity"]) is not bool or type(raw["precedence"]) is not int or
             not 0 <= raw["precedence"] <= 100):
        raise ValueError(f"L2T008: invalid frozen template for {name}")
    indices = raw["argument_indices"]
    expected = [i for i, info in enumerate(infos) if info == "explicit"] if raw["auto_arity"] else list(range(len(infos)))
    if not _indices(indices) or indices != expected:
        raise ValueError(f"L2T002: invalid frozen template argument_indices for {name}")
    if not isinstance(raw["instructions"], list) or not raw["instructions"]:
        raise ValueError(f"L2T004: missing frozen instructions for {name}")
    instructions = tuple(_parse_instruction(name, item, len(indices), mode) for item in raw["instructions"])
    requirements: dict[int, int] = {}

    def collect(items):
        for item in items:
            if item.kind == "mode_switch":
                collect(item.instructions)
            elif item.kind in ("binder", "body") and item.depth > 0:
                requirements[item.index] = max(requirements.get(item.index, 0), item.depth)

    collect(instructions)
    return DisplayTemplate(label, mode, raw["content"], language, raw["precedence"],
                           raw["auto_arity"], tuple(indices), instructions, requirements)


def _parse_instruction(name, raw, arity, mode, allow_switch=True) -> TemplateInstruction:
    if isinstance(raw, dict):
        kind = raw.get("kind")
        if kind == "literal" and set(raw) == {"kind", "content"} and isinstance(raw["content"], str):
            return TemplateInstruction(kind, content=raw["content"])
        if (kind == "mode_switch" and allow_switch and set(raw) == {"kind", "mode", "instructions"}
                and raw["mode"] == ("text" if mode == "formula" else "formula")
                and isinstance(raw["instructions"], list) and raw["instructions"]):
            return TemplateInstruction(kind, mode=raw["mode"], instructions=tuple(
                _parse_instruction(name, item, arity, raw["mode"], False)
                for item in raw["instructions"]))
        fields = {"kind", "index", "mode", "max_precedence"} | ({"depth"} if kind in ("binder", "body") else set())
        if (kind in ("argument", "binder", "body") and set(raw) == fields and
                type(raw["index"]) is int and 0 <= raw["index"] < arity and
                raw["mode"] == mode and type(raw["max_precedence"]) is bool):
            if kind == "argument":
                return TemplateInstruction(kind, index=raw["index"], mode=raw["mode"], max_precedence=raw["max_precedence"])
            if (type(raw["depth"]) is int and raw["depth"] >= (1 if kind == "binder" else 0)):
                return TemplateInstruction(kind, index=raw["index"], depth=raw["depth"], mode=raw["mode"],
                                           max_precedence=raw["max_precedence"])
    raise ValueError(f"L2T004: invalid frozen template instruction for {name}")
