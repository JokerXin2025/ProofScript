"""DisplayTree to TeX rendering with layout-aware parenthesization."""

from __future__ import annotations

import hashlib
import base64
import re
from dataclasses import dataclass

from .macros import MacroRegistry
from .model import DisplayNode, MacroStyle, RenderDiagnostic


_SELECTOR = re.compile(r"(?<!@)(@+)(\d+)(?!\d)|#(\d+)")
_PHRASE_PLACEHOLDER = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


@dataclass(frozen=True)
class _Rendered:
    tex: str
    mode: str = "formula"
    fixity: str = "atom"
    precedence: int = 100
    associativity: str = "none"


class LayoutRenderer:
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
        self.language = language
        rendered = self._render(node, style)
        return self._switch_mode(rendered.tex, rendered.mode, parent_mode)

    def _render(self, node: DisplayNode, requested: str) -> _Rendered:
        macro = self.registry.get(node.macro_name)
        if macro is not None:
            style_name = f"prose-{self.language}" if requested == "formula" else requested
            try:
                style = self.registry.style(macro, style_name, node)
            except ValueError:
                self.diagnostics.append(RenderDiagnostic("error", "L2T006", "no style matches expression structure", node.macro_name))
                return _Rendered(f"\\operatorname{{{self._short_name(node.macro_name)}}}")
            return self._render_macro(node, style, requested)
        kind = node.kind
        if kind in ("const", "fvar", "bvar", "binder", "literal"):
            if kind == "const":
                return _Rendered(self._constant(node.macro_name))
            if kind == "literal" and node.metadata.get("literalKind") == "literal.str":
                return _Rendered(self._escape_text(node.macro_name), mode="text")
            if kind == "fvar" and node.metadata.get("fvarId"):
                return _Rendered(self._html_data(node.macro_name, "fvar", "f", str(node.metadata["fvarId"]), self._declaration_text(node)))
            if kind == "binder" and node.metadata.get("bindId"):
                return _Rendered(self._html_data(node.macro_name, "binder", "b", str(node.metadata["bindId"])))
            if kind == "bvar" and node.metadata.get("bindRef"):
                return _Rendered(self._html_data(node.macro_name, "bvar", "b", str(node.metadata["bindRef"])))
            return _Rendered(node.macro_name)
        if kind == "sort":
            return _Rendered("\\mathbb{P}" if node.macro_name == "Prop" else "\\operatorname{Type}")
        if kind == "local-definition":
            value = self._render(node.children[0], requested)
            return _Rendered(self._html_data(value.tex, "fvar", "f", str(node.metadata["fvarId"]), self._declaration_text(node)), value.mode, value.fixity, value.precedence, value.associativity)
        if kind == "application":
            rendered = [self._render(child, requested) for child in node.children]
            if not rendered:
                return _Rendered("\\operatorname{app}\\left(\\right)", precedence=90, fixity="application")
            head = rendered[0].tex
            if rendered[0].precedence < 90:
                head = f"\\left({head}\\right)"
            args = ",".join(self._switch_mode(item.tex, item.mode, "formula") for item in rendered[1:])
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
        if kind == "metavariable":
            return _Rendered("\\square")
        self.diagnostics.append(RenderDiagnostic("warning", "L2T010", f"unknown display node {node.macro_name}"))
        return _Rendered(f"\\texttt{{[unknown: {self._escape_text(node.macro_name)}]}}", mode="text")

    def _render_macro(self, node, style: MacroStyle, requested) -> _Rendered:
        children = [self._child_tex(self._render(child, requested), style, index) for index, child in enumerate(node.children)]

        def replace(match: re.Match) -> str:
            index = int(match.group(2) or match.group(3))
            if index >= len(node.children):
                self.diagnostics.append(RenderDiagnostic("error", "L2T004", "template references a missing child", node.macro_name))
                return f"[missing {match.group()}]"
            child = node.children[index]
            if match.group(1):
                depth = len(match.group(1))
                required = style.binders.get(index)
                if required is None or depth > required + 1:
                    self.diagnostics.append(RenderDiagnostic("error", "L2T004", "invalid @ selector", node.macro_name))
                    return f"[missing {match.group()}]"
                for _ in range(depth - 1):
                    if child.kind != "lambda" or len(child.children) != 3:
                        self.diagnostics.append(RenderDiagnostic("error", "L2T004", "binder selector requires a lambda", node.macro_name))
                        return f"[missing {match.group()}]"
                    child = child.children[2]
                if depth == required + 1:
                    if child.kind == "lambda" and len(child.children) == 3:
                        return self._child_tex(self._render(child.children[0], requested), style, index)
                    return self._child_tex(self._render(child, requested), style, index)
                if child.kind == "lambda" and len(child.children) == 3:
                    return self._child_tex(self._render(child.children[0], requested), style, index)
                self.diagnostics.append(RenderDiagnostic("error", "L2T004", "binder selector requires a lambda", node.macro_name))
                return f"[missing {match.group()}]"
            return children[index]

        result = style.template.replace("#*", style.separator.join(children))
        result = _SELECTOR.sub(replace, result)
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
        return _Rendered(_format_phrase(phrase, body=body_tex, binder=binder_tex, type=type_tex), "text", "binder", 20)

    def _render_exists(self, node, requested) -> _Rendered:
        type_node, predicate = node.children
        type_tex = self._render(type_node, requested).tex
        if predicate.kind == "lambda":
            binder, _, body = predicate.children
            binder_tex = self._render(binder, requested).tex
            body_rendered = self._render(body, requested)
            body_tex = self._switch_mode(body_rendered.tex, body_rendered.mode, "text")
            phrase = self.registry.phrase("exists", self.language) or "there exists ${binder} in ${type} such that ${body}"
            return _Rendered(_format_phrase(phrase, body=body_tex, binder=binder_tex, type=type_tex), "text", "binder", 20)
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
    def _html_data(tex: str, kind: str, prefix: str, identity: str, information: str | None = None) -> str:
        digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]
        extra = ""
        if information:
            encoded = base64.urlsafe_b64encode(information.encode("utf-8")).decode("ascii").rstrip("=")
            extra = f",l2t-info={encoded}"
        return f"\\htmlData{{l2t-kind={kind},l2t-ref={prefix}-{digest}{extra}}}{{{tex}}}"

    @staticmethod
    def _declaration_text(node: DisplayNode) -> str | None:
        type_node = node.metadata.get("declarationType")
        value_node = node.metadata.get("declarationValue")
        if type_node is None and value_node is None:
            return None
        name = node.metadata.get("declarationName") or node.macro_name
        result = str(name)
        if type_node is not None:
            result += " : " + _plain_expression(type_node)
        if value_node is not None:
            result += " := " + _plain_expression(value_node)
        return result

    @staticmethod
    def _escape_text(value: str) -> str:
        replacements = {
            "\\": "\\textbackslash{}", "{": "\\{", "}": "\\}", "_": "\\_",
            "%": "\\%", "#": "\\#", "&": "\\&", "$": "\\$",
        }
        return "".join(replacements.get(char, char) for char in value)


def _format_phrase(template: str, **values: str) -> str:
    return _PHRASE_PLACEHOLDER.sub(lambda match: values.get(match.group(1), match.group(0)), template)


def _plain_expression(node: DisplayNode) -> str:
    """Readable captured declaration text for the native variable tooltip."""
    if not node.children:
        return node.macro_name
    children = [_plain_expression(child) for child in node.children]
    if node.kind == "application":
        return children[0] + "(" + ", ".join(children[1:]) + ")"
    if node.kind in {"forall", "lambda"}:
        return f"({'∀' if node.kind == 'forall' else 'fun'} {children[0]} : {children[1]}, {children[2]})"
    if node.kind == "projection":
        return children[0] + "." + node.macro_name
    if node.kind == "local-definition":
        return children[0]
    return node.macro_name + "(" + ", ".join(children) + ")"
