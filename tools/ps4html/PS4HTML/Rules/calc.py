import html

from PS4HTML.engine import render_cal_step
from PS4HTML.i18n import tr


def rule_calc(calc, proof, *, language):
    init = calc["init"]
    relation, rhs, proofs = (calc[key] for key in ("chain_relation", "chain_rhs", "chain_proof"))
    if init is None:
        raise ValueError("calc.init must be a recorded expression")
    if (not all(isinstance(items, list) for items in (relation, rhs, proofs)) or
            not relation or len(relation) != len(rhs) or len(relation) != len(proofs)):
        raise ValueError("calc.chain must be nonempty with aligned columns")
    calc_steps = []
    lhs = init
    for i, (link_relation, link_rhs, proof_value) in enumerate(zip(relation, rhs, proofs)):
        if link_rhs is None or link_relation is None or proof_value is None:
            raise ValueError("calc chain entries cannot contain null values")
        lhs_tex = html.escape(proof.tex(lhs)) if lhs is not None else ""
        rhs_tex = html.escape(proof.tex(link_rhs)) if link_rhs is not None else ""
        calc_steps.append(
            render_cal_step(
                tag = tr("strategy.calculation", language) if i == 0 else "",
                lhs = lhs_tex if i == 0 else "",
                rel = proof.render_relation(link_relation),
                rhs = rhs_tex,
            )
        )
        lhs = link_rhs
    return "<div>" + "\n".join(calc_steps) + "</div>"
