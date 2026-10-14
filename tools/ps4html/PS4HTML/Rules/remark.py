import html
from PS4HTML.engine import render_annotation


def rule_remark(remark, previous, subsequent, proof, *, language):
    text = remark["text"]
    if not isinstance(text, str):
        raise ValueError("remark.text must be a string")
    return render_annotation(
        sort = "remark",
        icon = "<i class=\"codicon codicon-comment-discussion-quote\"></i>",
        content = html.escape(text)
    )
