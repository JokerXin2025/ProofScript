import html

from PS4HTML.engine import render_cal_step
from PS4HTML.i18n import tr


def rule_calc(calc, proof, *, language):
    init = calc["init"]
    chain = calc["chain"]
    if init is None:
        raise ValueError("calc.init must be a recorded expression")
    if not isinstance(chain, list) or not chain:
        raise ValueError("calc.chain must be a nonempty array")
    calc_steps = []
    lhs = init
    for i, link in enumerate(chain):
        if not isinstance(link, dict) or not {"rhs", "relation", "proof"} <= link.keys():
            raise ValueError("calc chain entry requires rhs, relation and proof")
        if link["rhs"] is None or link["relation"] is None or link["proof"] is None:
            raise ValueError("calc chain entries cannot contain null values")
        rhs = link["rhs"]
        lhs_tex = html.escape(proof.tex(lhs)) if lhs is not None else ""
        rhs_tex = html.escape(proof.tex(rhs)) if rhs is not None else ""
        calc_steps.append(
            render_cal_step(
                tag = tr("strategy.calculation", language) if i == 0 else "",
                lhs = lhs_tex if i == 0 else "",
                rel = proof.render_relation(link["relation"]),
                rhs = rhs_tex,
            )
        )
        lhs = rhs
    return "<div>" + "\n".join(calc_steps) + "</div>"
