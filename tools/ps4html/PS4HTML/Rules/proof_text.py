import html
import re
from pathlib import Path
from string import Template

from PS4HTML.highlight import highlight_code
from PS4HTML.Rules.inline_text import InlineTextRenderer


LANGUAGE_CLASS = re.compile(r"[^A-Za-z0-9_+.-]")
TEMPLATE_PROOF_TEXT = Template(
    (Path(__file__).absolute().parent.parent / "Templates" / "proof_text.html").read_text()
)


class ProofTextRenderer(InlineTextRenderer):
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
