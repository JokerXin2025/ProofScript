import html
import os
import re
from pathlib import Path
from string import Template
from urllib.parse import urlparse

from PS4HTML.highlight import highlight_code


LANGUAGE_CLASS = re.compile(r"[^A-Za-z0-9_+.-]")
SAFE_LINK_SCHEMES = {"", "http", "https", "mailto"}
TEMPLATE_PROOF_TEXT = Template(
    (Path(__file__).absolute().parent.parent / "Templates" / "proof_text.html").read_text()
)


class ProofTextRenderer:
    def __init__(self, labels, build_root: Path, current_output: Path):
        self.labels = labels
        self.build_root = build_root
        self.current_output = current_output

    def render(self, value) -> str:
        blocks = value.get("blocks", []) if isinstance(value, dict) else []
        source = value.get("source", "") if isinstance(value, dict) else ""
        source = source if isinstance(source, str) else str(source)
        highlighted, _applied = highlight_code(source, "markdown", theme="light")
        return TEMPLATE_PROOF_TEXT.substitute(
            content=self._blocks(blocks),
            source=highlighted,
        )

    def _blocks(self, blocks) -> str:
        if not isinstance(blocks, list):
            return self._unsupported("blocks")
        return "\n".join(self._block(block) for block in blocks)

    def _block(self, block) -> str:
        if not isinstance(block, dict) or len(block) != 1:
            return self._unsupported("block")
        tag, value = next(iter(block.items()))
        if not isinstance(value, dict):
            return self._unsupported(tag)

        if tag == "paragraph":
            return f'<p>{self._inlines(value.get("content", []))}</p>'
        if tag == "heading":
            level = value.get("level")
            if not isinstance(level, int) or isinstance(level, bool):
                level = 1
            level = min(4, max(1, level))
            label = value.get("label")
            anchor = f' id="heading-{html.escape(label, quote = True)}"' if isinstance(label, str) else ""
            return f'<h{level}{anchor}>{self._inlines(value.get("content", []))}</h{level}>'
        if tag == "code":
            language = value.get("language")
            source = value.get("source", "")
            language = language if isinstance(language, str) else ""
            source = source if isinstance(source, str) else str(source)
            language_class = LANGUAGE_CLASS.sub("-", language)
            class_name = f' class="language-{html.escape(language_class, quote = True)}"' if language_class else ""
            data_language = f' data-language="{html.escape(language, quote = True)}"' if language else ""
            highlighted, applied = highlight_code(source, language, theme = "dark")
            highlighted_class = " code-highlighted" if applied else ""
            return f'<pre class="page-code{highlighted_class}"{data_language}><code{class_name}>{highlighted}</code></pre>'
        if tag == "orderedList":
            return self._list(value, ordered = True)
        if tag == "unorderedList":
            return self._list(value, ordered = False)
        if tag == "quote":
            return f'<blockquote>{self._blocks(value.get("content", []))}</blockquote>'
        if tag == "displayMath":
            latex = value.get("latex", "")
            return f'<div class="display-math">$${html.escape(str(latex))}$$</div>'
        return self._unsupported(tag)

    def _list(self, value, ordered: bool) -> str:
        element = "ol" if ordered else "ul"
        start = value.get("start")
        start_attr = f' start="{start}"' if ordered and isinstance(start, int) and not isinstance(start, bool) and start != 1 else ""
        items = value.get("items", [])
        if not isinstance(items, list):
            return self._unsupported(f"{element} items")
        rendered = []
        for item in items:
            if not isinstance(item, dict):
                rendered.append(f'<li>{self._unsupported("list item")}</li>')
                continue
            ordinal = item.get("ordinal")
            item_value = (
                f' value="{ordinal}"'
                if ordered and isinstance(ordinal, int) and not isinstance(ordinal, bool)
                else ""
            )
            rendered.append(f'<li{item_value}>{self._blocks(item.get("content", []))}</li>')
        return f'<{element}{start_attr}>{"".join(rendered)}</{element}>'

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
        href = f'{os.path.relpath(target_file, current_dir)}#{target.anchor}'
        return f'<a class="page-reference reference-{html.escape(str(kind), quote = True)}" href="{html.escape(href, quote = True)}">{text}</a>'

    @staticmethod
    def _unsupported(tag) -> str:
        return f'<span class="unsupported-inline">Unsupported {html.escape(str(tag))}</span>'
