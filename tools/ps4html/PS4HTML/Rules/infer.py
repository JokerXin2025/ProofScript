from PS4HTML.engine import render_cal_step
from PS4HTML.i18n import tr


def rule_infer(infer, previous, subsequent, proof, *, language):
    init = infer["init"]
    chain = infer["chain"]
    if init is None:
        raise ValueError("infer.init must be a recorded expression")
    if not isinstance(chain, list) or not chain:
        raise ValueError("infer.chain must be a nonempty array")
    infer_steps = []
    lhs = init
    for i, link in enumerate(chain):
        if not isinstance(link, dict) or not {"rhs", "proof"} <= link.keys():
            raise ValueError("infer chain entry requires rhs and proof")
        if link["rhs"] is None or link["proof"] is None:
            raise ValueError("infer chain entries cannot contain null values")
        rhs = link["rhs"]
        lhs_tex = proof.tex(lhs) if lhs is not None else ""
        rhs_tex = proof.tex(rhs) if rhs is not None else ""
        infer_steps.append(
            render_cal_step(
                tag = tr("strategy.inference", language) if i == 0 else "",
                lhs = lhs_tex if i == 0 else "",
                rel = "\\ \\Longrightarrow\\ ",
                rhs = rhs_tex,
            )
        )
        lhs = rhs
    return "<div>" + "\n".join(infer_steps) + "</div>"
