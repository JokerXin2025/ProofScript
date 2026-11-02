import html
import os
from pathlib import Path
from urllib.parse import urlparse, quote as quote_url_path


SAFE_LINK_SCHEMES = {"", "http", "https", "mailto"}


class InlineTextRenderer:
    def __init__(self, labels, build_root: Path, current_output: Path):
        self.labels = labels
        self.build_root = build_root
        self.current_output = current_output

    def _inlines(self, inlines) -> str:
        if not isinstance(inlines, list):
            return self._unsupported("inlines")
        return "".join(self._inline(inline) for inline in inlines)

    def _inline(self, inline) -> str:
        if not isinstance(inline, dict) or len(inline) != 1:
            return self._unsupported("inline")
        tag, value = next(iter(inline.items()))
        if not isinstance(value, dict):
            return self._unsupported(tag)

        if tag == "text":
            return f'<span class="proof-text-literal">{html.escape(str(value.get("value", "")))}</span>'
        if tag == "code":
            return f'<code>{html.escape(str(value.get("value", "")))}</code>'
        containers = {
            "strong": ("strong",),
            "emphasis": ("em",),
            "strongEmphasis": ("strong", "em"),
            "strike": ("s",),
            "underline": ("u",),
            "highlight": ("mark",),
            "superscript": ("sup",),
            "subscript": ("sub",),
        }
        if tag in containers:
            content = self._inlines(value.get("content", []))
            for element in reversed(containers[tag]):
                content = f'<{element}>{content}</{element}>'
            return content
        if tag == "math":
            return f'${html.escape(str(value.get("latex", "")))}$'
        if tag == "link":
            return self._link(value)
        if tag == "reference":
            return self._reference(value)
        if tag == "softBreak":
            return "\n"
        if tag == "hardBreak":
            return "<br>"
        return self._unsupported(tag)

    def _link(self, value) -> str:
        url = value.get("url", "")
        url = url if isinstance(url, str) else ""
        if urlparse(url).scheme.lower() not in SAFE_LINK_SCHEMES:
            url = "#"
        content = self._inlines(value.get("content", []))
        return f'<a href="{html.escape(url, quote = True)}">{content}</a>'

    def _reference(self, value) -> str:
        kind = value.get("kind")
        label = value.get("label")
        target = self.labels.get((kind, label))
        text = html.escape(label if isinstance(label, str) else "")
        if target is None:
            title = html.escape(f"Unresolved {kind} reference", quote = True)
            return f'<span class="unresolved-reference" title="{title}">{text}</span>'
        target_file = self.build_root / target.output_path
        current_dir = (self.build_root / self.current_output).parent
        href = f'{quote_url_path(os.path.relpath(target_file, current_dir))}#{quote_url_path(target.anchor)}'
        return f'<a class="page-reference reference-{html.escape(str(kind), quote = True)}" href="{html.escape(href, quote = True)}">{text}</a>'

    @staticmethod
    def _unsupported(tag) -> str:
        return f'<span class="unsupported-inline">Unsupported {html.escape(str(tag))}</span>'
