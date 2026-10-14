import html

from PS4HTML.engine import render_details, render_step


def rule_embed(step, previous, subsequent, proof, *, language, path=(), index=None):
    theorem = step["theorem"]
    proof_value = step["proof"]
    args = step["args"]
    arg_kinds = step["argKinds"]
    if not isinstance(theorem, str) or not isinstance(args, list) or not isinstance(arg_kinds, list) or len(args) != len(arg_kinds):
        raise ValueError("embed requires theorem, args and matching argKinds")
    if any(kind not in ("proof", "data") for kind in arg_kinds):
        raise ValueError("embed.argKinds entries must be proof or data")
    argument_text = []
    for kind, value in zip(arg_kinds, args):
        rendered = proof.tex_param(value)
        argument_text.append(f"{kind}: {rendered}" if rendered else rendered)
    summary = ", ".join(value for value in argument_text if value)

    if isinstance(proof_value, list):
        content = proof.render(proof_value, path + (f"{index}:embed",))
    else:
        if not isinstance(proof_value, dict):
            raise ValueError("embed.proof must be an expression or a proof array")
        content = render_step(
            "嵌入定理" if language == "zh" else "Embedded theorem",
            summary,
        )

    title = html.escape(theorem)
    if summary:
        title = f"{title} ({summary})"
    return render_details(
        open=True,
        tag="嵌入证明" if language == "zh" else "Embedded proof",
        title=title,
        content=content,
    )
