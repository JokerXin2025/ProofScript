"""Theorem statements share the proof's renderer, allocator and hover scope."""

import html


def render_statement(statement, engine):
    if statement is None:
        raise ValueError("Missing reserved theorem statement; rebuild the proof")
    statement = engine.resolve(statement)
    parameters = []
    instance_conditions = []
    for parameter in statement["parameters"]:
        # Keep class assumptions without exposing implementation instance names.
        if parameter["instance"]:
            instance_conditions.append(f"<li>{html.escape(engine.tex(parameter['type']))}</li>")
            continue
        text = engine.renderer.render_parameter(parameter["variable"], parameter["type"], language=engine.language)
        engine.diagnostics.extend(engine.renderer.diagnostics_dict())
        parameters.append(f"<span>{html.escape(text)}</span>")
    conditions = [f"<li>{html.escape(engine.tex(condition))}</li>" for condition in statement["conditions"]]
    conditions = instance_conditions + conditions
    conclusion = html.escape(engine.tex(statement["conclusion"]))
    zh = engine.language == "zh"
    parameter_html = ('<div class="statement-parameters"><i class="statement-parameter-mark" aria-hidden="true"></i>'
                      + "".join(parameters) + '</div>') if parameters else ""
    condition_html = (f'<ul class="statement-conditions" aria-label="{"条件" if zh else "Conditions"}">'
                      + "".join(conditions) + '</ul>') if conditions else ""
    return (f'<div class="theorem-statement" data-language="{engine.language}" aria-label="{"定理表述" if zh else "Theorem statement"}">'
            + parameter_html + '<div class="statement-implication">' + condition_html
            + f'<div class="statement-conclusion">{conclusion}</div></div></div>'
            + f'<h3 class="statement-proof-divider">{"证明" if zh else "Proof"}</h3>')
