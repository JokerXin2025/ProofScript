"""Interpret Lean-owned Lean2TeX events at a proof module's import boundary."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .macros import ASSOCIATIVITIES, FIXITIES, MODES, MacroRegistry, macro_from_data
from .model import Unwrap
from .variable import VarTypeConfig

VERSION = "0.0.0"
DEFINITION_FIELDS = {"kind", "arguments", "dynamic_arity", "styles", "calc_symbol", "unwrap", "alias"}
STYLE_FIELDS = {"name", "mode", "template", "fixity", "precedence", "associativity", "separator", "binders", "isolated_arguments"}
FIELDS = {"definition": DEFINITION_FIELDS, "variable": {"default", "names"}, "phrase": {"template"}}
KINDS = {"const", "operator", "relation", "logic", "projection", "constructor", "type"}
_CONTROL = re.compile(r"\\[A-Za-z]+$")


@dataclass(frozen=True)
class EffectiveConfiguration:
    registry: MacroRegistry
    variables: tuple[VarTypeConfig, ...]


def _object(value, where):
    if not isinstance(value, dict):
        raise ValueError(f"{where}: expected object")
    return value


def _string(value, where):
    if not isinstance(value, str) or not value:
        raise ValueError(f"{where}: expected nonempty string")
    return value


def _nat(value, where):
    if type(value) is not int or value < 0:
        raise ValueError(f"{where}: expected non-negative integer")
    return value


def _strings(value, where):
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{where}: expected string array")
    return value


def _style(value, where):
    fields = _object(value, where)
    if set(fields) - STYLE_FIELDS or "template" not in fields:
        raise ValueError(f"{where}: unknown or missing style fields")
    result = dict(fields)
    for key in ("name", "template", "separator"):
        if key in result and not isinstance(result[key], str):
            raise ValueError(f"{where}.{key}: expected string")
    for key, options in (("mode", MODES), ("fixity", FIXITIES), ("associativity", ASSOCIATIVITIES)):
        if key in result and (not isinstance(result[key], str) or result[key] not in options):
            raise ValueError(f"{where}.{key}: invalid value")
    if "precedence" in result:
        _nat(result["precedence"], f"{where}.precedence")
        if result["precedence"] > 100:
            raise ValueError(f"{where}.precedence: exceeds 100")
    if "isolated_arguments" in result:
        indices = result["isolated_arguments"]
        if not isinstance(indices, list) or any(type(index) is not int or index < 0 for index in indices) or len(indices) != len(set(indices)):
            raise ValueError(f"{where}.isolated_arguments: expected unique natural indices")
    if "binders" in result:
        binders = result["binders"]
        if not isinstance(binders, list):
            raise ValueError(f"{where}.binders: expected pair array")
        pairs = {}
        for pair in binders:
            if not isinstance(pair, list) or len(pair) != 2:
                raise ValueError(f"{where}.binders: expected pairs")
            index, count = (_nat(part, f"{where}.binders") for part in pair)
            if not count or index in pairs:
                raise ValueError(f"{where}.binders: duplicate index or zero count")
            pairs[index] = count
        result["binders"] = {str(index): count for index, count in pairs.items()}
    return result


def _fields(category, value, where):
    fields = _object(value, where)
    if not fields or set(fields) - FIELDS[category]:
        raise ValueError(f"{where}: empty or unknown fields {set(fields) - FIELDS[category]}")
    result = dict(fields)
    if category == "definition":
        for key in ("alias", "calc_symbol"):
            if key in result and result[key] is not None:
                _string(result[key], f"{where}.{key}")
        if "unwrap" in result and result["unwrap"] is not None:
            _nat(result["unwrap"], f"{where}.unwrap")
        if "kind" in result and (not isinstance(result["kind"], str) or result["kind"] not in KINDS):
            raise ValueError(f"{where}.kind: invalid kind")
        if "dynamic_arity" in result and type(result["dynamic_arity"]) is not bool:
            raise ValueError(f"{where}.dynamic_arity: expected boolean")
        if "arguments" in result:
            args = result["arguments"]
            if args != "explicit" and (not isinstance(args, list) or
                any(type(arg) is not int or arg < 0 for arg in args)):
                raise ValueError(f"{where}.arguments: expected explicit or natural number array")
            if isinstance(args, list) and len(args) != len(set(args)):
                raise ValueError(f"{where}.arguments: duplicate index")
        if "styles" in result:
            if not isinstance(result["styles"], list):
                raise ValueError(f"{where}.styles: expected array")
            result["styles"] = [_style(style, f"{where}.styles[{i}]") for i, style in enumerate(result["styles"])]
    elif category == "variable":
        if "default" in result and not isinstance(result["default"], str):
            raise ValueError(f"{where}.default: expected string")
        if "names" in result:
            _strings(result["names"], f"{where}.names")
    else:
        templates = result.get("template")
        if not isinstance(templates, list) or not templates:
            raise ValueError(f"{where}.template: expected nonempty array")
        seen = set()
        for item in templates:
            entry = _object(item, f"{where}.template")
            if set(entry) != {"lang", "content"} or not isinstance(entry["content"], str):
                raise ValueError(f"{where}.template: invalid entry")
            lang = _string(entry["lang"], f"{where}.template.lang")
            if lang in seen:
                raise ValueError(f"{where}.template: duplicate language {lang}")
            seen.add(lang)
            if set(re.findall(r"\$\{([^}]+)\}", entry["content"])) - {"body", "binder", "type"}:
                raise ValueError(f"{where}.template: unknown placeholder")
    return result


def _module_path(name):
    return "/".join("".join(f"%{ord(char):X}" if char in "/%\\:." else char for char in part)
                    for part in name.split("."))


class ConfigurationIndex:
    """One isolated export tree; never infer configuration from the Python package."""

    def __init__(self, export_root: str | Path):
        root = Path(export_root)
        self.modules = {}
        self.events = {}
        self._event_files = {}
        self._cache = {}
        for file in (root / "rendering" / "modules").rglob("*.json"):
            document = _object(json.loads(file.read_text(encoding="utf-8")), str(file))
            module = _string(document.get("module"), str(file))
            imports = document.get("imports")
            if document.get("schemaVersion") not in {"0.0.0", "0.1.0"} or not isinstance(imports, list) or any(
                not isinstance(item, str) for item in imports):
                raise ValueError(f"{file}: invalid module manifest")
            if module in self.modules:
                raise ValueError(f"{file}: duplicate module {module}")
            if file.relative_to(root / "rendering" / "modules").as_posix() != f"{_module_path(module)}.json":
                raise ValueError(f"{file}: module path does not match {module}")
            self.modules[module] = imports
        for file in (root / "lean2tex" / "events").rglob("*.json"):
            document = _object(json.loads(file.read_text(encoding="utf-8")), str(file))
            module = _string(document.get("module"), str(file))
            if document.get("schema_version") != VERSION or module not in self.modules or module in self._event_files:
                raise ValueError(f"{file}: unsupported, missing, or duplicate module {module}")
            if file.relative_to(root / "lean2tex" / "events").as_posix() != f"{_module_path(module)}.json":
                raise ValueError(f"{file}: module path does not match {module}")
            self._event_files[module] = (file, document)

    def _events(self, module):
        if module in self.events:
            return self.events[module]
        if module not in self._event_files:
            raise ValueError(f"missing Lean2TeX event file for {module}")
        file, document = self._event_files[module]
        events = document.get("events")
        if not isinstance(events, list):
            raise ValueError(f"{file}: missing events")
        checked = []
        for sequence, event in enumerate(events):
            event = _object(event, f"{file} event {sequence}")
            if set(event) - {"sequence", "category", "target", "fields", "source"} or event.get("sequence") != sequence or type(event.get("sequence")) is not int:
                raise ValueError(f"{file}: invalid event sequence or keys at {sequence}")
            category = event.get("category")
            if category not in FIELDS:
                raise ValueError(f"{file}: invalid category {category!r}")
            target = _string(event.get("target"), f"{file} event {sequence}")
            fields = _fields(category, event.get("fields"), f"{file} {category} {target}")
            if "source" in event:
                source = _object(event["source"], f"{file} source")
                if set(source) != {"file", "start", "stop"} or not isinstance(source.get("file"), str) or not all(
                    type(source.get(key)) is int and source[key] >= 0 for key in ("start", "stop")) or source["start"] > source["stop"]:
                    raise ValueError(f"{file}: invalid source")
            checked.append((category, target, fields))
        self.events[module] = checked
        return checked

    def _order(self, module):
        if module not in self.modules:
            raise ValueError(f"missing module manifest for {module}")
        ordered, seen, visiting = [], set(), set()

        def visit(owner):
            if owner in visiting:
                raise ValueError(f"cyclic module imports at {owner}")
            if owner in seen:
                return
            if owner not in self.modules:
                raise ValueError(f"missing module manifest for {owner}")
            visiting.add(owner)
            for parent in self.modules[owner]:
                visit(parent)
            visiting.remove(owner)
            seen.add(owner)
            ordered.append(owner)

        for imported in self.modules[module]:
            visit(imported)
        return ordered

    def _visible(self, module):
        """A configuration owner can also be a transitive proof-module import."""
        return set(self._order(module)) | {module}

    def effective(self, module: str) -> EffectiveConfiguration:
        if module in self._cache:
            return self._cache[module]
        order = self._order(module)
        ancestors = {}

        def parents(owner):
            if owner not in ancestors:
                ancestors[owner] = self._visible(owner) - {owner}
            return ancestors[owner]

        values, writers = {}, {}
        for owner in order:
            for category, target, fields in self._events(owner):
                config = values.setdefault((category, target), {})
                for field, value in fields.items():
                    updates = value if category == "phrase" and field == "template" else [value]
                    for update in updates:
                        unit = f"template.{update['lang']}" if category == "phrase" else field
                        units = (unit, "alias/unwrap") if category == "definition" and field in ("alias", "unwrap") else (unit,)
                        for conflict_unit in units:
                            key = (category, target, conflict_unit)
                            previous = writers.get(key, set())
                            for other in previous:
                                if other != owner and other not in parents(owner) and owner not in parents(other):
                                    raise ValueError(f"conflicting Lean2TeX {category} {target}.{conflict_unit} in {other} and {owner}")
                            writers[key] = {old for old in previous if old not in parents(owner)} | {owner}
                        if category == "phrase":
                            entries = config.setdefault("template", [])
                            index = next((i for i, item in enumerate(entries) if item["lang"] == update["lang"]), None)
                            if index is None:
                                entries.append(dict(update))
                            else:
                                entries[index] = dict(update)
                        else:
                            config[field] = value
        configuration = interpret(values)
        self._cache[module] = configuration
        return configuration


def interpret(values: dict) -> EffectiveConfiguration:
    """Convert merged patches to the existing layout model without mutating patches."""
    definitions = {target: fields for (category, target), fields in values.items() if category == "definition"}
    registry = MacroRegistry()
    for target, fields in definitions.items():
        if fields.get("alias") is not None and fields.get("unwrap") is not None:
            raise ValueError(f"{target}: alias and unwrap are mutually exclusive")
        if fields.get("alias") is not None:
            registry.aliases[target] = fields["alias"]
        elif fields.get("unwrap") is not None:
            registry.unwraps[target] = Unwrap(target, fields["unwrap"])
        else:
            symbol = fields.get("calc_symbol")
            if symbol is not None:
                registry.relations[target] = symbol
            styles = fields.get("styles")
            if symbol is not None and styles is None:
                symbol_tex = symbol + (" " if _CONTROL.search(symbol) else "")
                styles = [{"name": "formula", "mode": "formula", "template": f"#0{symbol_tex}#1",
                           "fixity": "infix", "precedence": 50, "associativity": "none"}]
                args = fields.get("arguments", "explicit")
                if fields.get("dynamic_arity") or (args != "explicit" and len(args) != 2):
                    raise ValueError(f"{target}: generated calc style requires two selected arguments")
                if fields.get("kind", "relation") != "relation":
                    raise ValueError(f"{target}: generated calc style requires relation kind")
            if styles is not None:
                registry.add(macro_from_data({
                    "name": target, "kind": fields.get("kind", "relation" if symbol is not None else "const"),
                    "arguments": fields.get("arguments", "explicit" if symbol is not None else []),
                    "dynamic_arity": fields.get("dynamic_arity", False), "styles": styles}))
            elif symbol is None:
                raise ValueError(f"{target}: missing styles or calc_symbol")
    for name, destination in registry.aliases.items():
        if destination not in definitions:
            raise ValueError(f"{name}: missing alias target configuration {destination}")
        registry.resolve_alias(name)
    for (category, target), fields in values.items():
        if category == "phrase":
            if "template" not in fields:
                raise ValueError(f"{target}: missing phrase template")
            registry.phrases[target] = {entry["lang"]: entry["content"] for entry in fields["template"]}
    variables = []
    for (category, target), fields in values.items():
        if category == "variable":
            if "default" not in fields or "names" not in fields:
                raise ValueError(f"{target}: incomplete variable configuration")
            variables.append(VarTypeConfig(target, fields["default"], list(fields["names"])))
    return EffectiveConfiguration(registry, tuple(variables))
