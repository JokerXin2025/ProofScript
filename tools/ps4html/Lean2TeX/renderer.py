"""DisplayTree to TeX rendering with layout-aware parenthesization."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass

from .macros import MacroRegistry
from .builtin_styles import STYLE_BY_KEY, target_for_node
from .numerals import numeral_styles
from .universes import sort_styles
from .mixed import atom, eligible_literals, split_math
from .interactions import TEXT_MARKER
from .model import DisplayNode, DisplayTemplate, RenderDiagnostic, RenderLimitError, RenderTarget, visible_node


_SELECTOR = re.compile(r"(?<!@)(@+)(\d+)(?!\d)|#(\d+|\*)")
_PHRASE_PLACEHOLDER = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")
_FORALL_PHRASES = {
    "zh": "${body}对一切 $${binder}\\in ${type}$ 成立",
    "en": "${body} holds for every $${binder}\\in ${type}$",
}


@dataclass(frozen=True)
class _Rendered:
    tex: str
    mode: str = "formula"
    fixity: str = "atom"
    precedence: int = 100
    associativity: str = "none"


class LayoutRenderer:
    MAX_EXPANDED_NODES = 32_768
    MAX_DEPTH = 256
    MAX_OUTPUT_CHARACTERS = 1_048_576
    MAX_INTERMEDIATE_CHARACTERS = 8_388_608

    def __init__(self, registry: MacroRegistry):
        self.registry = registry
        self.diagnostics: list[RenderDiagnostic] = []

    def render(
        self,
        node: DisplayNode,
        label: str | None = None,
        parent_mode: str = "text",
        language: str = "zh",
        interactions=None,
        fragments=None,
        selections: dict[RenderTarget, str] | None = None,
    ) -> str:
        self.diagnostics.clear()
        self._expanded_nodes = 0
        self._depth = 0
        self._characters = 0
        self.language = language
        self.interactions = interactions
        self.fragments = fragments or {}
        self.selections = selections or {}
        self.root_node = visible_node(node)
        self.html_literals = (eligible_literals(self.root_node, self.registry, language, self.selections)
                              if parent_mode == "text" and self.interactions is not None else set())
        self.mixed_root = bool(self.html_literals and self.root_node.kind != "literal")
        self.literal_fragments = {}
        rendered = self._render(node, label)
        if "[[PS4HTML-LITERAL-" in rendered.tex:
            def wrap_math(part):
                fragment = self.interactions.new_fragment(self.fragments[id(self.root_node)])
                return f"\\htmlData{{ps-expr-fragment={fragment}}}{{{part}}}"
            tex = split_math(rendered.tex, wrap_math if self.mixed_root else None)
            self._check_length(len(tex), self.MAX_OUTPUT_CHARACTERS, "TeX output")
            return tex
        tex = self._switch_mode(rendered.tex, rendered.mode, parent_mode)
        self._check_length(len(tex), self.MAX_OUTPUT_CHARACTERS, "TeX output")
        return tex

    def _render(self, node: DisplayNode, requested: str | None) -> _Rendered:
        self._visit()
        if self._depth >= self.MAX_DEPTH:
            raise RenderLimitError(f"Expression layout exceeds depth limit {self.MAX_DEPTH}")
        self._depth += 1
        try:
            rendered = self._render_node(node, requested)
            if (self.interactions is not None and id(node) in self.fragments and
                    node.kind not in ("wrapper", "expression") and
                    not (id(node) == id(self.root_node) and self.mixed_root) and
                    not (node.kind == "let" and self._builtin_style(node, requested) == "stacked") and
                    r"\begin{aligned}" not in rendered.tex and
                    not (node.kind == "literal" and id(node) in self.html_literals)):
                rendered = self._tag(node, rendered)
            self._account_text(rendered.tex, self.MAX_OUTPUT_CHARACTERS, "TeX output")
            return rendered
        finally:
            self._depth -= 1

    def _visit(self) -> None:
        self._expanded_nodes += 1
        if self._expanded_nodes > self.MAX_EXPANDED_NODES:
            raise RenderLimitError(f"Expression layout exceeds {self.MAX_EXPANDED_NODES} expanded nodes")

    @staticmethod
    def _check_length(length: int, limit: int, label: str) -> None:
        if length > limit:
            raise RenderLimitError(f"Expression {label} exceeds {limit} characters")

    def _account_text(self, text: str, limit: int, label: str) -> None:
        self._check_length(len(text), limit, label)
        self._characters += len(text)
        self._check_length(self._characters, self.MAX_INTERMEDIATE_CHARACTERS, "layout work")

    def _bounded_join(self, parts: list[str], separator: str, limit: int, label: str) -> str:
        length = sum(map(len, parts)) + len(separator) * max(0, len(parts) - 1)
        self._check_length(length, limit, label)
        return separator.join(parts)

    def _render_node(self, node: DisplayNode, requested: str | None) -> _Rendered:
        kind = node.kind
        if kind in ("wrapper", "expression"):
            # Transparent semantic parents introduce no math atom.
            return self._render(node.children[0], requested)
        if kind in ("fvar", "bvar", "binder"):
            tex = f"\\textcolor{{gray}}{{{node.macro_name}}}" if node.generated else node.macro_name
            key = {"fvar": "fvarId", "binder": "bindId", "bvar": "bindRef"}[kind]
            identity = node.metadata.get(key)
            if identity is not None:
                tex = self._html_data(tex, kind, "f" if kind == "fvar" else "b",
                                      str(identity), generated=node.generated)
            return _Rendered(tex)
        if kind == "metavariable":
            return _Rendered(r"\textcolor{gray}{?}" if self._builtin_style(node, requested) == "question"
                             else r"\operatorname{未知}")
        # A built-in display kind must not accidentally use a same-named declaration.
        macro = self.registry.get(node.macro_name) if kind == "const" or (
            kind not in ("application", "lambda", "forall", "let", "sort", "literal", "metavariable")
            and node.metadata.get("headConst")) else None
        if macro is not None:
            if macro.kind in ("operator", "relation"):
                if node.metadata.get("originalExprKind") == "const":
                    return _Rendered(self._constant(node.macro_name))
                return self._render_symbolic(node, macro, requested)
            try:
                key = RenderTarget("constant", node.metadata.get("leanName", node.macro_name))
                label = self.selections.get(key, requested if node is self.root_node else None)
                style = self.registry.template_for(macro, label, node, language=self.language)
            except ValueError:
                self.diagnostics.append(RenderDiagnostic("error", "L2T006", "no template matches expression structure", node.macro_name))
                return _Rendered(f"\\operatorname{{{self._short_name(node.macro_name)}}}")
            # Bare function constants, including fallback application heads,
            # cannot fill argument selectors. Constant templates remain valid.
            if node.metadata.get("originalExprKind") == "const" and _SELECTOR.search(style.content):
                return _Rendered(self._constant(node.macro_name))
            return self._render_macro(node, style, requested)
        if kind in ("const", "literal"):
            if kind == "const":
                return _Rendered(self._constant(node.macro_name))
            if kind == "literal" and node.metadata.get("literalKind") == "literal.str":
                if id(node) in self.html_literals:
                    fragment = self.literal_fragments.get(id(node))
                    if fragment is None:
                        fragment = self.interactions.new_fragment(self.fragments[id(node)])
                        self.literal_fragments[id(node)] = fragment
                    return _Rendered(atom(node.macro_name, self._builtin_style(node, requested), fragment), mode="text")
                return _Rendered(self._escape_text(node.macro_name), mode="text")
            if kind == "literal" and node.metadata.get("literalKind") == "literal.nat":
                return _Rendered(numeral_styles(node.macro_name)[self._builtin_style(node, requested)])
            return _Rendered(node.macro_name)
        if kind == "sort":
            return _Rendered(sort_styles(node.metadata["level"])[self._builtin_style(node, requested)])
        if kind == "application":
            style = self._builtin_style(node, requested)
            rendered = [self._render(child, requested) for child in node.children]
            if not rendered:
                return _Rendered("\\operatorname{app}\\left(\\right)", precedence=90, fixity="application")
            layout = DisplayTemplate("call", "formula", "", "application", 90, "left")
            head = self._child_tex(rendered[0], layout, 0)
            args = [self._child_tex(item, layout, 1) for item in rendered[1:]]
            if style == "juxtaposed":
                # f (g x) must not become the left-associated f g x.
                args = [f"\\left({arg}\\right)" if item.mode == "formula" and
                        item.fixity == "application" and item.precedence == 90 else arg
                        for item, arg in zip(rendered[1:], args)]
                return _Rendered(self._bounded_join([head, *args], r"\,", self.MAX_OUTPUT_CHARACTERS, "TeX output"),
                                 precedence=90, fixity="application", associativity="left")
            args = self._bounded_join([self._switch_mode(item.tex, item.mode, "formula")
                                       for item in rendered[1:]], ",", self.MAX_OUTPUT_CHARACTERS, "TeX output")
            return _Rendered(f"{head}\\left({args}\\right)", precedence=90, fixity="application", associativity="left")
        if kind == "lambda":
            return self._render_chain(node, requested)
        if kind == "forall":
            return self._render_chain(node, requested)
        if kind == "let":
            return self._render_chain(node, requested)
        if kind == "projection":
            source = self._render(node.children[0], requested)
            source_tex = f"\\left({source.tex}\\right)" if source.precedence < 90 else source.tex
            return _Rendered(f"{source_tex}.\\operatorname{{{self._escape_text(node.macro_name)}}}", precedence=90, fixity="postfix")
        self.diagnostics.append(RenderDiagnostic("warning", "L2T010", f"unknown display node {node.macro_name}"))
        return _Rendered(f"\\texttt{{[unknown: {self._escape_text(node.macro_name)}]}}", mode="text")

    def _tag(self, node: DisplayNode, rendered: _Rendered) -> _Rendered:
        fragment = self.interactions.new_fragment(self.fragments[id(node)])
        if rendered.mode == "formula":
            tex = f"\\htmlData{{ps-expr-fragment={fragment}}}{{{rendered.tex}}}"
        else:
            tex = self._tag_text(rendered.tex, self.fragments[id(node)], fragment)
        return _Rendered(tex, rendered.mode, rendered.fixity, rendered.precedence, rendered.associativity)

    def _tag_text(self, tex: str, occurrence: str, fragment: str) -> str:
        # Text-mode expressions may contain inline math. Existing child
        # sentinels remain properly nested in their containing text run.
        chunks = []
        for index, part in enumerate(tex.split("$")):
            if index % 2:
                math_fragment = self.interactions.new_fragment(occurrence)
                chunks.append(f"$\\htmlData{{ps-expr-fragment={math_fragment}}}{{{part}}}$")
            elif part:
                chunks.append(f"[[PS4HTML-START-{fragment}]]{part}[[PS4HTML-END-{fragment}]]")
        return "".join(chunks)

    def _render_symbolic(self, node, macro, requested) -> _Rendered:
        arity = 2 if macro.fixity == "infix" else 1
        if len(node.children) != arity:
            self.diagnostics.append(RenderDiagnostic("error", "L2T006", f"{macro.kind} requires {arity} operands", node.macro_name))
            return _Rendered(f"\\operatorname{{{self._short_name(node.macro_name)}}}")
        layout = DisplayTemplate("formula", "formula", "", macro.fixity,
                                 macro.precedence, macro.associativity)
        children = [self._child_tex(self._render(child, requested), layout, index)
                    for index, child in enumerate(node.children)]
        symbol = macro.symbol
        self._check_length(len(symbol), self.MAX_OUTPUT_CHARACTERS, "operator symbol")
        if symbol.startswith("\\") and symbol[-1:].isalpha():
            symbol += " "
        if macro.fixity == "prefix":
            tex = symbol + children[0]
        elif macro.fixity == "postfix":
            tex = children[0] + symbol
        else:
            tex = children[0] + symbol + children[1]
        self._check_length(len(tex), self.MAX_OUTPUT_CHARACTERS, "symbolic layout")
        return _Rendered(tex, "formula", macro.fixity, macro.precedence, macro.associativity)

    def _render_macro(self, node, style: DisplayTemplate, requested) -> _Rendered:
        self._check_length(len(style.content), self.MAX_OUTPUT_CHARACTERS, "macro template")
        # Binder selectors render only the referenced binder/body. Rendering all
        # arguments first would create a hidden lambda occurrence for Exists.
        children: dict[int, _Rendered] = {}
        result_length = len(style.content)

        def checked_replacement(match, replacement):
            nonlocal result_length
            result_length += len(replacement) - len(match.group())
            self._check_length(result_length, self.MAX_OUTPUT_CHARACTERS, "TeX output")
            return replacement

        def replace(match: re.Match) -> str:
            index = int(match.group(2) or match.group(3))
            if index >= len(node.children):
                self.diagnostics.append(RenderDiagnostic("error", "L2T004", "template references a missing child", node.macro_name))
                return checked_replacement(match, f"[missing {match.group()}]")
            child = visible_node(node.children[index]) if match.group(1) else node.children[index]
            # A text template can contain inline $...$ math. Selectors inside
            # that run must use formula mode, otherwise they insert another
            # pair of dollar delimiters into the existing math run.
            layout = (DisplayTemplate(style.label, "formula", style.content, style.fixity,
                                      style.precedence, style.associativity, style.binders,
                                      style.isolated_arguments, style.language) if style.mode == "text" and
                      style.content[:match.start()].count("$") % 2 else style)
            if match.group(1):
                depth = len(match.group(1))
                required = style.binders.get(index)
                if required is None or depth > required + 1:
                    self.diagnostics.append(RenderDiagnostic("error", "L2T004", "invalid @ selector", node.macro_name))
                    return checked_replacement(match, f"[missing {match.group()}]")
                for _ in range(depth - 1):
                    if child.kind != "lambda" or len(child.children) != 3:
                        self.diagnostics.append(RenderDiagnostic("error", "L2T004", "binder selector requires a lambda", node.macro_name))
                        return checked_replacement(match, f"[missing {match.group()}]")
                    child = visible_node(child.children[2])
                if depth == required + 1:
                    if child.kind == "lambda" and len(child.children) == 3:
                        return checked_replacement(match, self._child_tex(self._render(child.children[0], requested), layout, index))
                    return checked_replacement(match, self._child_tex(self._render(child, requested), layout, index))
                if child.kind == "lambda" and len(child.children) == 3:
                    return checked_replacement(match, self._child_tex(self._render(child.children[0], requested), layout, index))
                self.diagnostics.append(RenderDiagnostic("error", "L2T004", "binder selector requires a lambda", node.macro_name))
                return checked_replacement(match, f"[missing {match.group()}]")
            if index not in children:
                children[index] = self._render(node.children[index], requested)
            return checked_replacement(match, children[index].tex if id(child) in self.html_literals
                                       else self._child_tex(children[index], layout, index))

        result = _SELECTOR.sub(replace, style.content)
        return _Rendered(result, style.mode, style.fixity, style.precedence, style.associativity)

    def _child_tex(self, child: _Rendered, parent: DisplayTemplate, position: int) -> str:
        tex = self._switch_mode(child.tex, child.mode, parent.mode)
        if position in parent.isolated_arguments:
            return tex
        if child.mode != parent.mode:
            return tex
        if parent.mode == "text":
            return tex
        parenthesize = child.precedence < parent.precedence
        if child.precedence == parent.precedence and parent.fixity == "infix" and child.fixity == "infix":
            if parent.associativity == "none":
                parenthesize = True
            elif parent.associativity == "left" and position > 0:
                parenthesize = True
            elif parent.associativity == "right" and position == 0:
                parenthesize = True
        return f"\\left({tex}\\right)" if parenthesize else tex

    def _builtin_style(self, node, requested):
        target = target_for_node(node)
        family = STYLE_BY_KEY[target.key]
        selected = self.selections.get(target, requested if node is self.root_node else None)
        return selected if selected in family.labels else family.default

    def _render_chain(self, node, requested) -> _Rendered:
        kind = node.kind
        arrow = node.metadata.get("isArrow") if kind == "forall" else None
        chain = [node]
        terminal = node.children[2]
        while True:
            inner = visible_node(terminal)
            if inner.kind != kind or (kind == "forall" and inner.metadata.get("isArrow") != arrow):
                break
            if inner is not terminal:
                # Keep an independently addressable transparent wrapper's
                # occurrence and source by rendering it as the chain body.
                break
            if len(chain) >= self.MAX_DEPTH - self._depth:
                raise RenderLimitError(f"Expression layout exceeds depth limit {self.MAX_DEPTH}")
            chain.append(inner)
            terminal = inner.children[2]
        style = self._builtin_style(node, requested)
        entries = []
        for member in chain:
            binder = self._render(member.children[0], requested) if kind != "forall" or not arrow else None
            type_node = self._render(member.children[1], requested) if kind != "let" else None
            value = self._render(member.children[1], requested) if kind == "let" else None
            entries.append((binder, type_node, value))
        body = self._render(terminal, requested)
        if kind == "let" and style == "where":
            clauses = []
            for index in range(len(entries) - 1, -1, -1):
                binder, _, value = entries[index]
                clause = f"{binder.tex}={self._switch_mode(value.tex, value.mode, 'formula')}"
                if index and self.interactions is not None and id(chain[index]) in self.fragments:
                    fragment = self.interactions.new_fragment(self.fragments[id(chain[index])])
                    clause = f"\\htmlData{{ps-expr-fragment={fragment}}}{{{clause}}}"
                clauses.append(clause)
            word = "其中" if self.language == "zh" else "where"
            return _Rendered(f"{self._switch_mode(body.tex, body.mode, 'formula')},\\ \\text{{{word}}}\\ " +
                             r",\ ".join(clauses), precedence=20, fixity="binder")
        if kind == "let" and style == "stacked":
            declarations = [f"\\operatorname{{let}}\\ {binder.tex} := {self._switch_mode(value.tex, value.mode, 'formula')}"
                            for binder, _, value in entries]
            # Alignment separators must remain outside KaTeX htmlData groups.
            # The inner occurrence is anchored to its declaration line.
            for index in range(len(chain) - 1, 0, -1):
                inner = chain[index]
                if self.interactions is not None and id(inner) in self.fragments:
                    fragment = self.interactions.new_fragment(self.fragments[id(inner)])
                    declarations[index] = f"\\htmlData{{ps-expr-fragment={fragment}}}{{{declarations[index]}}}"
            if self.interactions is not None and id(node) in self.fragments:
                # KaTeX aligns each row independently. A single htmlData group
                # around the aligned environment only decorates its middle row.
                occurrence = self.fragments[id(node)]
                first = self.interactions.new_fragment(occurrence)
                last = self.interactions.new_fragment(occurrence)
                declarations[0] = f"\\htmlData{{ps-expr-fragment={first}}}{{{declarations[0]}}}"
                for index in range(1, len(declarations)):
                    middle = self.interactions.new_fragment(occurrence)
                    declarations[index] = f"\\htmlData{{ps-expr-fragment={middle}}}{{{declarations[index]}}}"
                body = _Rendered(f"\\htmlData{{ps-expr-fragment={last}}}{{\\operatorname{{in}}\\ {self._switch_mode(body.tex, body.mode, 'formula')}}}")
                return _Rendered(r"\begin{aligned}" + r"\\".join(declarations) + r"\\" + body.tex +
                                 r"\end{aligned}", precedence=20, fixity="binder")
            return _Rendered(r"\begin{aligned}" + r"\\".join(declarations) +
                             r"\\\operatorname{in}\ " + self._switch_mode(body.tex, body.mode, "formula") +
                             r"\end{aligned}", precedence=20, fixity="binder")
        for index in range(len(chain) - 1, -1, -1):
            binder, type_node, value = entries[index]
            if kind == "lambda":
                name = binder.tex
                if style == "typed":
                    name = f"({name}:{self._switch_mode(type_node.tex, type_node.mode, 'formula')})"
                if style == "fun":
                    body = _Rendered(f"\\operatorname{{fun}}\\ {name} \\Rightarrow {self._switch_mode(body.tex, body.mode, 'formula')}",
                                     precedence=20, fixity="binder")
                else:
                    body = _Rendered(f"{name} \\mapsto {self._switch_mode(body.tex, body.mode, 'formula')}",
                                     precedence=20, fixity="binder")
            elif kind == "let":
                name = binder.tex
                body = _Rendered(f"\\operatorname{{let}}\\ {name} := {self._switch_mode(value.tex, value.mode, 'formula')}"
                                 f"\\ \\operatorname{{in}}\\ {self._switch_mode(body.tex, body.mode, 'formula')}",
                                 precedence=20, fixity="binder")
            elif arrow:
                symbol = r"\to" if style == "arrow" else r"\implies"
                layout = DisplayTemplate("formula", "formula", "", "infix", 30, "right")
                body = _Rendered(f"{self._child_tex(type_node, layout, 0)}{symbol} {self._child_tex(body, layout, 1)}",
                                 "formula", "infix", 30, "right")
            elif style == "symbol":
                body = _Rendered(f"\\forall {binder.tex}\\in {self._switch_mode(type_node.tex, type_node.mode, 'formula')},\\ "
                                 f"{self._switch_mode(body.tex, body.mode, 'formula')}",
                                 precedence=20, fixity="binder")
            else:
                phrase = _FORALL_PHRASES.get(self.language, _FORALL_PHRASES["en"])
                body = _Rendered(self._format_phrase(phrase,
                    body=self._switch_mode(body.tex, body.mode, "text"), binder=binder.tex, type=type_node.tex),
                    "text", "binder", 20)
            if index:
                inner = chain[index]
                if self.interactions is not None and id(inner) in self.fragments:
                    body = self._tag(inner, body)
                self._account_text(body.tex, self.MAX_OUTPUT_CHARACTERS, "TeX output")
        return body


    @staticmethod
    def _switch_mode(tex: str, source: str, target: str) -> str:
        if source == target:
            return tex
        if source == "formula" and target == "text":
            return f" ${tex}$ "
        parts = tex.split("$")
        if len(parts) == 1:
            return LayoutRenderer._text_to_formula(tex)
        converted = []
        for index, part in enumerate(parts):
            if not part:
                continue
            converted.append(part if index % 2 else LayoutRenderer._text_to_formula(part))
        return "".join(converted)

    @staticmethod
    def _text_to_formula(text: str) -> str:
        if not TEXT_MARKER.search(text):
            return f"\\text{{{text}}}"
        # Keep literal text inside one \text group; nested \htmlData is
        # understood by KaTeX's text parser and avoids splitting its spacing.
        converted = TEXT_MARKER.sub(lambda marker: (
            f"\\htmlData{{ps-expr-fragment={marker[2]}}}{{" if marker[1] == "START" else "}"), text)
        return f"\\text{{{converted}}}"

    @classmethod
    def _constant(cls, name: str) -> str:
        return f"\\operatorname{{{cls._short_name(name)}}}"

    @staticmethod
    def _short_name(name: str) -> str:
        return name.rsplit(".", 1)[-1]

    @staticmethod
    def _html_data(tex: str, kind: str, prefix: str, identity: str, *, generated: bool = False) -> str:
        digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]
        marker = ",l2t-generated=true" if generated else ""
        return f"\\htmlData{{l2t-kind={kind},l2t-ref={prefix}-{digest}{marker}}}{{{tex}}}"

    def _format_phrase(self, template: str, **values: str) -> str:
        length = len(template)
        self._check_length(length, self.MAX_OUTPUT_CHARACTERS, "phrase template")

        def replace(match):
            nonlocal length
            value = values.get(match.group(1), match.group(0))
            length += len(value) - len(match.group(0))
            self._check_length(length, self.MAX_OUTPUT_CHARACTERS, "TeX output")
            return value

        return _PHRASE_PLACEHOLDER.sub(replace, template)

    @staticmethod
    def _escape_text(value: str) -> str:
        replacements = {
            "\\": "\\textbackslash{}", "{": "\\{", "}": "\\}", "_": "\\_",
            "%": "\\%", "#": "\\#", "&": "\\&", "$": "\\$",
        }
        return "".join(replacements.get(char, char) for char in value)
