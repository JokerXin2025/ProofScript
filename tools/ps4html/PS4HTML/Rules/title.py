import html

from PS4HTML.Rules.inline_text import InlineTextRenderer


class TitleRenderer(InlineTextRenderer):
    def render(self, value) -> str:
        if not isinstance(value, dict):
            return self._unsupported("title")
        level = value.get("level")
        if not isinstance(level, int) or isinstance(level, bool):
            level = 1
        level = max(1, level)
        visual_level = min(5, level)
        label = value.get("label")
        anchor = f' id="heading-{html.escape(label, quote=True)}"' if isinstance(label, str) else ""
        aria_level = f' aria-level="{level}"' if level > 5 else ""
        arrows = (
            f'<span class="page-title-depth" aria-hidden="true">{"→" * (level - 5)}</span>'
            if level > 5 else ""
        )
        content = self._inlines(value.get("content", []))
        return (
            f'<h{visual_level} class="page-title page-title-level-{visual_level} proof-text"'
            f' data-title-level="{level}"{aria_level}{anchor}>{arrows}{content}</h{visual_level}>'
        )
