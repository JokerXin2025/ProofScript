import html
from PS4HTML.engine import render_annotation


def rule_admit(admit, previous, subsequent, proof, *, language):
    text = admit["reason"]
    if not isinstance(text, str):
        raise ValueError("admit.reason must be a string")
    if not text:
        return "<!-- Silent Step: admit (empty) -->"
    return render_annotation(
        sort="admit",
        icon="<i class=\"codicon codicon-workspace-unknown\"></i>",
        content=html.escape(text),
    )
