"""DisplayTree to TeX rendering with layout-aware parenthesization."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass

from .macros import MacroRegistry
from .model import DisplayNode, MacroStyle, RenderDiagnostic, RenderLimitError


_SELECTOR = re.compile(r"(?<!@)(@+)(\d+)(?!\d)|#(\d+|\*)")
_PHRASE_PLACEHOLDER = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


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
        style: str = "formula",
        parent_mode: str = "text",
        language: str = "zh",
    ) -> str:
        self.diagnostics.clear()
        self._expanded_nodes = 0
        self._depth = 0
        self._characters = 0
        self.language = language
        rendered = self._render(node, style)
        tex = self._switch_mode(rendered.tex, rendered.mode, parent_mode)
        self._check_length(len(tex), self.MAX_OUTPUT_CHARACTERS, "TeX output")
        return tex

    def _render(self, node: DisplayNode, requested: str) -> _Rendered:
        self._visit()
        if self._depth >= self.MAX_DEPTH:
            raise RenderLimitError(f"Expression layout exceeds depth limit {self.MAX_DEPTH}")
        self._depth += 1
        try:
            rendered = self._render_node(node, requested)
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

    def _render_node(self, node: DisplayNode, requested: str) -> _Rendered:
        kind = node.kind
        if kind in ("fvar", "bvar", "binder"):
            tex = f"\\textcolor{{gray}}{{{node.macro_name}}}" if node.generated else node.macro_name
            key = {"fvar": "fvarId", "binder": "bindId", "bvar": "bindRef"}[kind]
            identity = node.metadata.get(key)
            if identity is not None:
                tex = self._html_data(tex, kind, "f" if kind == "fvar" else "b",
                                      str(identity), generated=node.generated)
            return _Rendered(tex)
        if kind == "metavariable":
            return _Rendered("\\textcolor{gray}{?}")
        macro = self.registry.get(node.macro_name)
        if macro is not None:
            if macro.calc_symbol is not None and not macro.styles:
                return self._render_relation_macro(node, macro.calc_symbol, requested)
            style_name = f"prose-{self.language}" if requested == "formula" else requested
            try:
                style = self.registry.style(macro, style_name, node)
            except ValueError:
                self.diagnostics.append(RenderDiagnostic("error", "L2T006", "no style matches expression structure", node.macro_name))
                return _Rendered(f"\\operatorname{{{self._short_name(node.macro_name)}}}")
            # Bare function constants, including fallback application heads,
            # cannot fill argument selectors. Constant templates remain valid.
            if node.metadata.get("originalExprKind") == "const" and _SELECTOR.search(style.template):
                return _Rendered(self._constant(node.macro_name))
            return self._render_macro(node, style, requested)
        if kind in ("const", "literal"):
            if kind == "const":
                return _Rendered(self._constant(node.macro_name))
            if kind == "literal" and node.metadata.get("literalKind") == "literal.str":
                return _Rendered(self._escape_text(node.macro_name), mode="text")
            return _Rendered(node.macro_name)
        if kind == "sort":
            return _Rendered("\\mathbb{P}" if node.macro_name == "Prop" else "\\operatorname{Type}")
        if kind == "application":
            rendered = [self._render(child, requested) for child in node.children]
            if not rendered:
                return _Rendered("\\operatorname{app}\\left(\\right)", precedence=90, fixity="application")
            head = rendered[0].tex
            if rendered[0].precedence < 90:
                head = f"\\left({head}\\right)"
            args = self._bounded_join([self._switch_mode(item.tex, item.mode, "formula")
                                       for item in rendered[1:]], ",", self.MAX_OUTPUT_CHARACTERS, "TeX output")
            return _Rendered(f"{head}\\left({args}\\right)", precedence=90, fixity="application", associativity="left")
        if kind == "lambda":
            binder, _, body = node.children
            binder_tex = self._render(binder, requested).tex
            body_tex = self._render(body, requested).tex
            return _Rendered(f"{binder_tex} \\mapsto {body_tex}", precedence=20, fixity="binder")
        if kind == "forall":
            return self._render_forall(node, requested)
        if kind == "exists":
            return self._render_exists(node, requested)
        if kind == "let":
            binder, value, body = node.children
            binder_tex = self._render(binder, requested).tex
            value_tex = self._render(value, requested).tex
            body_tex = self._render(body, requested).tex
            return _Rendered(f"\\operatorname{{let}}\\ {binder_tex} := {value_tex}\\ \\operatorname{{in}}\\ {body_tex}", precedence=20, fixity="binder")
        if kind == "projection":
            source = self._render(node.children[0], requested)
            source_tex = f"\\left({source.tex}\\right)" if source.precedence < 90 else source.tex
            return _Rendered(f"{source_tex}.\\operatorname{{{self._escape_text(node.macro_name)}}}", precedence=90, fixity="postfix")
        self.diagnostics.append(RenderDiagnostic("warning", "L2T010", f"unknown display node {node.macro_name}"))
        return _Rendered(f"\\texttt{{[unknown: {self._escape_text(node.macro_name)}]}}", mode="text")

    def _render_relation_macro(self, node, symbol: str, requested: str) -> _Rendered:
        if len(node.children) != 2:
            self.diagnostics.append(RenderDiagnostic("error", "L2T006", "relation requires two operands", node.macro_name))
            return _Rendered(f"\\operatorname{{{self._short_name(node.macro_name)}}}")
        left = self._render(node.children[0], requested)
        right = self._render(node.children[1], requested)
        fixity = "infix"
        precedence = 50
        left_tex = self._child_tex(left, MacroStyle("formula", "formula", "", fixity, precedence, "none"), 0)
        right_tex = self._child_tex(right, MacroStyle("formula", "formula", "", fixity, precedence, "none"), 1)
        suffix = symbol[-1:] if symbol else ""
        if suffix.isalpha() and symbol.startswith("\\"):
            symbol += " "
        return _Rendered(f"{left_tex}{symbol}{right_tex}", "formula", fixity, precedence, "none")

    def _render_macro(self, node, style: MacroStyle, requested) -> _Rendered:
        self._check_length(len(style.template), self.MAX_OUTPUT_CHARACTERS, "macro template")
        children = [self._child_tex(self._render(child, requested), style, index) for index, child in enumerate(node.children)]
        result_length = len(style.template)

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
            child = node.children[index]
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
                    child = child.children[2]
                if depth == required + 1:
                    if child.kind == "lambda" and len(child.children) == 3:
                        return checked_replacement(match, self._child_tex(self._render(child.children[0], requested), style, index))
                    return checked_replacement(match, self._child_tex(self._render(child, requested), style, index))
                if child.kind == "lambda" and len(child.children) == 3:
                    return checked_replacement(match, self._child_tex(self._render(child.children[0], requested), style, index))
                self.diagnostics.append(RenderDiagnostic("error", "L2T004", "binder selector requires a lambda", node.macro_name))
                return checked_replacement(match, f"[missing {match.group()}]")
            return checked_replacement(match, children[index])

        result = _SELECTOR.sub(replace, style.template)
        return _Rendered(result, style.mode, style.fixity, style.precedence, style.associativity)

    def _child_tex(self, child: _Rendered, parent: MacroStyle, position: int) -> str:
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

    def _render_forall(self, node, requested) -> _Rendered:
        binder, type_node, body = node.children
        body_rendered = self._render(body, requested)
        if node.metadata.get("isArrow"):
            lhs = self._render(type_node, requested)
            style = MacroStyle("formula", "formula", "#0\\implies #1", "infix", 30, "right")
            return _Rendered(
                f"{self._child_tex(lhs, style, 0)}\\implies {self._child_tex(body_rendered, style, 1)}",
                "formula", "infix", 30, "right",
            )
        type_tex = self._render(type_node, requested).tex
        binder_tex = self._render(binder, requested).tex
        body_tex = self._switch_mode(body_rendered.tex, body_rendered.mode, "text")
        phrase = self.registry.phrase("forall", self.language) or "${body} for all ${binder} in ${type}"
        return _Rendered(self._format_phrase(phrase, body=body_tex, binder=binder_tex, type=type_tex), "text", "binder", 20)

    def _render_exists(self, node, requested) -> _Rendered:
        type_node, predicate = node.children
        type_tex = self._render(type_node, requested).tex
        if predicate.kind == "lambda":
            binder, _, body = predicate.children
            binder_tex = self._render(binder, requested).tex
            body_rendered = self._render(body, requested)
            body_tex = self._switch_mode(body_rendered.tex, body_rendered.mode, "text")
            phrase = self.registry.phrase("exists", self.language) or "there exists ${binder} in ${type} such that ${body}"
            return _Rendered(self._format_phrase(phrase, body=body_tex, binder=binder_tex, type=type_tex), "text", "binder", 20)
        pred_tex = self._render(predicate, requested).tex
        return _Rendered(f"\\exists\\ {pred_tex}", precedence=20, fixity="binder")

    @staticmethod
    def _switch_mode(tex: str, source: str, target: str) -> str:
        if source == target:
            return tex
        if source == "formula" and target == "text":
            return f" ${tex}$ "
        parts = tex.split("$")
        if len(parts) == 1:
            return f"\\text{{{tex}}}"
        converted = []
        for index, part in enumerate(parts):
            if not part:
                continue
            converted.append(part if index % 2 else f"\\text{{{part}}}")
        return "".join(converted)

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
