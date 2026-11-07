"""Page-scoped semantic identities and visible TeX fragment bookkeeping."""

from __future__ import annotations

import json
import re
import hashlib

from .model import RenderTarget
from .builtin_styles import ACTIVE_KEYS, STYLE_BY_KEY, target_for_node
from .numerals import numeral_styles
from .universes import sort_styles
from .mixed import ATOM, STYLES, eligible_literals
import html


FRAGMENT = re.compile(r"ps-expr-fragment=(p[0-9]+)")
TEXT_MARKER = re.compile(r"\[\[PS4HTML-(START|END)-(p[0-9]+)\]\]")
MARKER = re.compile(r"(ps-expr-fragment=)(p[0-9]+)|\[\[PS4HTML-(START|END)-(p[0-9]+)\]\]")


class ExpressionInteractions:
    def __init__(self):
        self.entities: dict[str, dict] = {}
        self.occurrences: dict[str, dict] = {}
        self.fragments: dict[str, str] = {}
        self._occurrence_count = 0
        self._fragment_count = 0
        self.render_roots: dict[str, dict] = {}
        self._root_count = 0
        self.enable_render_roots = False
        self._render_depth = 0

    def add_root(self, root, mapping, registry, language, parent_mode):
        self._root_count += 1
        root_id = f"r{self._root_count}"
        dependencies = set()
        html_literals = eligible_literals(root, registry, language) if parent_mode == "text" else set()

        def serialize(node):
            key = self._key(node, "")
            if key and json.loads(key)[0] in ("constant", "builtin"):
                dependencies.add(key)
            metadata = {name: value for name, value in node.metadata.items() if name in (
                "leanName", "headConst", "originalExprKind", "isArrow", "literalKind",
                "fvarId", "bindId", "bindRef")}
            if node.kind == "literal" and node.metadata.get("literalKind") == "literal.str":
                metadata["htmlEligible"] = id(node) in html_literals
                self.occurrences[mapping[id(node)]]["details"]["htmlEligible"] = metadata["htmlEligible"]
            if node.kind == "literal" and node.metadata.get("literalKind") == "literal.nat":
                metadata["styles"] = numeral_styles(node.macro_name)
            if node.kind == "sort":
                metadata["styles"] = sort_styles(node.metadata["level"])
                metadata["builtinKey"] = target_for_node(node).key
            if node.kind in ("fvar", "bvar", "binder"):
                reference = node.metadata.get({"fvar": "fvarId", "bvar": "bindRef", "binder": "bindId"}[node.kind])
                if reference is not None:
                    digest = hashlib.sha256(str(reference).encode("utf-8")).hexdigest()[:16]
                    prefix = "f" if node.kind == "fvar" else "b"
                    metadata["reference"] = f"{prefix}-{digest}"
            return {
                "name": node.macro_name, "kind": node.kind,
                "occurrence": mapping[id(node)], "generated": node.generated,
                "metadata": metadata,
                "children": [serialize(child) for child in node.children],
            }

        tree = serialize(root)
        if html_literals and root.kind != "literal":
            tree["metadata"]["mixedRoot"] = True
        catalog = {}
        for key in sorted(dependencies):
            category, name = json.loads(key)
            if category == "builtin":
                family = STYLE_BY_KEY[name]
                catalog[key] = {
                    "default": family.default, "kind": "builtin",
                    "templates": [{"label": label, "lang": None, "available": name in ACTIVE_KEYS}
                                  for label in family.labels],
                }
                continue
            macro = registry.get(name)
            if macro is None:
                continue
            catalog[key] = {
                "default": macro.default_label, "kind": macro.kind, "symbol": macro.symbol,
                "fixity": macro.fixity, "precedence": macro.precedence,
                "associativity": macro.associativity,
                "templates": [{"label": item.label, "lang": item.language,
                               "mode": item.mode, "content": item.content,
                               "fixity": item.fixity, "precedence": item.precedence,
                               "associativity": item.associativity,
                               "binders": item.binders,
                               "isolatedArguments": sorted(item.isolated_arguments)}
                              for item in macro.templates],
            }
        self.render_roots[root_id] = {
            "tree": tree, "dependencies": sorted(dependencies), "catalog": catalog,
            "language": language, "parentMode": parent_mode,
        }
        return root_id

    def discard(self, mapping: dict[int, str]) -> None:
        """Roll back IDs from a render that failed before it produced output."""
        removed = set(mapping.values())
        self.fragments = {key: value for key, value in self.fragments.items() if value not in removed}
        for identity in removed:
            self.occurrences.pop(identity, None)

    @staticmethod
    def _key(node, theorem):
        builtin = target_for_node(node)
        if builtin is not None:
            return builtin.as_key()
        name = node.metadata.get("leanName")
        if name and (node.kind == "const" or node.metadata.get("headConst") or node.kind == "wrapper"):
            return RenderTarget("constant", name).as_key()
        if node.kind == "fvar" and node.metadata.get("fvarId"):
            return json.dumps(["fvar", theorem, node.metadata["fvarId"]], ensure_ascii=False)
        if node.kind in ("bvar", "binder"):
            bind = node.metadata.get("bindRef") or node.metadata.get("bindId")
            if bind:
                return json.dumps(["bvar", theorem, bind], ensure_ascii=False)
        return None

    def register(self, root, theorem: str, language: str):
        """Allocate page-unique IDs without disturbing the semantic tree's local IDs."""
        mapping = {}
        nodes = []
        pending = [(root, None)]
        while pending:
            node, parent = pending.pop()
            self._occurrence_count += 1
            identity = f"o{self._occurrence_count}"
            mapping[id(node)] = identity
            nodes.append((node, identity, parent))
            pending.extend((child, identity) for child in reversed(node.children))
        bind_ids = {node.metadata["bindId"]: identity for node, identity, _ in nodes
                    if node.kind == "binder" and node.metadata.get("bindId")}
        for node, identity, parent in nodes:
            key = self._key(node, theorem)
            if node.kind in ("binder", "bvar") and key:
                bind = node.metadata.get("bindId") or node.metadata.get("bindRef")
                key = json.dumps(["bvar", theorem, bind_ids.get(bind, bind)], ensure_ascii=False)
            if key is not None and key not in self.entities:
                self.entities[key] = {
                    "scope": "page" if json.loads(key)[0] in ("constant", "builtin") else "theorem" if node.kind == "fvar" else "binding",
                    "kind": node.kind, "leanName": node.metadata.get("leanName"),
                    "declaration": node.metadata.get("declaration") or None,
                }
            elif key is not None and node.metadata.get("declaration"):
                current = self.entities[key].get("declaration") or {}
                new = node.metadata["declaration"]
                if not current.get("type") and new.get("type"):
                    self.entities[key]["declaration"] = new
            self.occurrences[identity] = {
                "entityKey": key, "parentId": parent, "kind": node.kind,
                "traits": list(node.metadata.get("traits", ())), "fragmentIds": [],
                "theoremId": theorem, "language": language,
                "details": {"display": node.macro_name, "generated": node.generated,
                            **{key: value for key, value in node.metadata.items()
                               if key != "declaration"}},
            }
            if node.kind == "bvar":
                bind = node.metadata.get("bindRef")
                if bind in bind_ids:
                    self.occurrences[identity]["details"]["binderOccurrenceId"] = bind_ids[bind]
        return mapping

    def new_fragment(self, occurrence_id: str) -> str:
        self._fragment_count += 1
        fragment = f"p{self._fragment_count}"
        self.fragments[fragment] = occurrence_id
        return fragment

    def collect(self, output: str):
        """Only fragments surviving template substitution become hit targets."""
        found = dict.fromkeys(FRAGMENT.findall(output) + [id for _, id in TEXT_MARKER.findall(output)] +
                              [match[2] for match in ATOM.findall(output)])
        for fragment in found:
            occurrence = self.fragments.get(fragment)
            if occurrence and fragment not in self.occurrences[occurrence]["fragmentIds"]:
                self.occurrences[occurrence]["fragmentIds"].append(fragment)
            # Transparent semantic parents share their child's visible extent.
            parent = self.occurrences[occurrence]["parentId"] if occurrence else None
            while parent and self.occurrences[parent]["kind"] in ("wrapper", "expression"):
                if fragment not in self.occurrences[parent]["fragmentIds"]:
                    self.occurrences[parent]["fragmentIds"].append(fragment)
                parent = self.occurrences[parent]["parentId"]

    def uniquify(self, html: str) -> str:
        """Repeated selectors must get distinct fragment IDs and DOM anchors."""
        seen: set[str] = set()
        # A text marker is paired with its END; duplicate STARTs need new IDs.
        text_stack: list[tuple[str, str]] = []

        def replace(match):
            prefix, fragment, side, text_fragment = match.group(1, 2, 3, 4)
            original = fragment or text_fragment
            if side == "END":
                if text_stack and text_stack[-1][0] == original:
                    return f"[[PS4HTML-END-{text_stack.pop()[1]}]]"
                return match.group()
            current = original
            if original in seen and original in self.fragments:
                current = self.new_fragment(self.fragments[original])
                occurrence = self.fragments[current]
                self.occurrences[occurrence]["fragmentIds"].append(current)
                parent = self.occurrences[occurrence]["parentId"]
                while parent and self.occurrences[parent]["kind"] in ("wrapper", "expression"):
                    self.occurrences[parent]["fragmentIds"].append(current)
                    parent = self.occurrences[parent]["parentId"]
            seen.add(original)
            if side == "START":
                text_stack.append((original, current))
                return f"[[PS4HTML-START-{current}]]"
            return f"{prefix}{current}"

        def replace_literal(match):
            style, encoded, original = match.group(5, 6, 7)
            current = original
            if original in seen and original in self.fragments:
                current = self.new_fragment(self.fragments[original])
                self.occurrences[self.fragments[current]]["fragmentIds"].append(current)
            seen.add(original)
            return f"[[PS4HTML-LITERAL-{style}-{encoded}-{current}]]"

        combined = re.compile(f"(?:{MARKER.pattern})|(?:{ATOM.pattern})")
        def replace_any(match):
            if match.group(5) is not None:
                return replace_literal(match)
            return replace(match)
        return combined.sub(replace_any, html)

    def materialize_text(self, output: str) -> str:
        """Turn text-mode sentinels into HTML after callers escape their text."""
        output = TEXT_MARKER.sub(lambda match: (
            (f'<span data-ps-expr-fragment="{match[2]}">' if match[1] == "START" else "</span>")
            if match[2] in self.fragments else match.group()), output)
        seen_literals = set()
        def literal(match):
            style, encoded, fragment = match.groups()
            if fragment not in self.fragments or len(encoded) % 6:
                return match.group()
            if fragment in seen_literals:
                fragment = self.new_fragment(self.fragments[fragment])
                self.occurrences[self.fragments[fragment]]["fragmentIds"].append(fragment)
            seen_literals.add(fragment)
            try:
                text = "".join(chr(int(encoded[i:i + 6], 16)) for i in range(0, len(encoded), 6))
            except ValueError:
                return match.group()
            tag = STYLES[style]
            return f'<{tag} data-ps-expr-fragment="{fragment}">{html.escape(text)}</{tag}>'
        return ATOM.sub(literal, output)

    def as_dict(self):
        return {"version": 2, "entities": self.entities, "occurrences": self.occurrences,
                "renderRoots": self.render_roots}

    def retain_visible(self, html: str) -> None:
        """Discard fragments produced by expressions omitted from final HTML."""
        visible = set(FRAGMENT.findall(html)) | {id for _, id in TEXT_MARKER.findall(html)} | {
            match[2] for match in ATOM.findall(html)}
        self.render_roots = {key: root for key, root in self.render_roots.items()
                             if f'[[PS4HTML-ROOT-{key}]]' in html}
        retained = set()

        def collect(node):
            retained.add(node["occurrence"])
            for child in node["children"]:
                collect(child)

        for root in self.render_roots.values():
            collect(root["tree"])
        # The initial rendering may hide children that another template exposes.
        # Their semantic occurrences must survive even without an initial fragment.
        original_parents = {key: value["parentId"] for key, value in self.occurrences.items()}
        for fragment in visible:
            occurrence = self.fragments.get(fragment)
            if occurrence and fragment not in self.occurrences[occurrence]["fragmentIds"]:
                self.occurrences[occurrence]["fragmentIds"].append(fragment)
            parent = self.occurrences[occurrence]["parentId"] if occurrence else None
            while parent and self.occurrences[parent]["kind"] in ("wrapper", "expression"):
                if fragment not in self.occurrences[parent]["fragmentIds"]:
                    self.occurrences[parent]["fragmentIds"].append(fragment)
                parent = self.occurrences[parent]["parentId"]
        self.fragments = {key: value for key, value in self.fragments.items() if key in visible}
        self.occurrences = {key: value for key, value in self.occurrences.items()
                            if key in retained or any(fragment in visible for fragment in value["fragmentIds"])}
        for occurrence in self.occurrences.values():
            occurrence["fragmentIds"] = [id for id in occurrence["fragmentIds"] if id in visible]
            while occurrence["parentId"] is not None and occurrence["parentId"] not in self.occurrences:
                occurrence["parentId"] = original_parents.get(occurrence["parentId"])
        used = {value["entityKey"] for value in self.occurrences.values()}
        self.entities = {key: value for key, value in self.entities.items() if key in used}
