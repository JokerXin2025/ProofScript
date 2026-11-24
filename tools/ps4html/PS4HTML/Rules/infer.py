import html

from PS4HTML.engine import render_cal_step
from PS4HTML.i18n import tr


def rule_infer(infer, proof, *, language):
    init = infer["init"]
    rhs, proofs = infer["chain_rhs"], infer["chain_proof"]
    if init is None:
        raise ValueError("infer.init must be a recorded expression")
    if (not isinstance(rhs, list) or not isinstance(proofs, list) or
            not rhs or len(rhs) != len(proofs)):
        raise ValueError("infer.chain must be nonempty with aligned columns")
    infer_steps = []
    lhs = init
    for i, (link_rhs, proof_value) in enumerate(zip(rhs, proofs)):
        if link_rhs is None or proof_value is None:
            raise ValueError("infer chain entries cannot contain null values")
        lhs_tex = html.escape(proof.tex(lhs)) if lhs is not None else ""
        rhs_tex = html.escape(proof.tex(link_rhs)) if link_rhs is not None else ""
        infer_steps.append(
            render_cal_step(
                tag = tr("strategy.inference", language) if i == 0 else "",
                lhs = lhs_tex if i == 0 else "",
                rel = r"$\ \Longrightarrow\ $",
                rhs = rhs_tex,
            )
        )
        lhs = link_rhs
    return "<div>" + "\n".join(infer_steps) + "</div>"
