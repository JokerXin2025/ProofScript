"""Explicit multilingual layouts for strategies with runtime-dependent branches."""

import html

from PS4HTML.engine import render_details, render_step, render_strategy
from PS4HTML.recording import BRANCHES_FIELD, RULE_ID_FIELD
from PS4HTML.utils import to_roman


LAYOUTS = {
    "decompose": {
        "zh": ("目标拆解", "逐项证明生成的子目标", "子目标"),
        "en": ("To decompose the goal,", "prove the resulting subgoals one by one", "Subgoal"),
    },
    "cases": {
        "zh": ("分类依据", "对所有可能的情形分别讨论", "情形"),
        "en": ("As the case distinction,", "consider each possible case", "In Case"),
    },
    "constructor": {
        "zh": ("构造目标", "应用构造器并逐项证明各字段", "构造器字段"),
        "en": ("Construct the goal", "apply the constructor and prove each field", "Constructor field"),
    },
}

STRATEGIES = {
    "ProofScript.Builtin.Script.split_and!": ("decompose", "递归拆分合取", "To split the conjunction recursively,"),
    "ProofScript.Builtin.Script.cases_by!": ("cases", "逐项分类讨论", "Analyzing each case,"),
    "ProofScript.Builtin.Script.cases_on": ("cases", "分类讨论", "By cases,"),
    "ProofScript.Builtin.Script.constructor": ("constructor", "应用构造器", "Apply the constructor"),
    "ProofScript.Builtin.Script.constructor!": ("constructor", "应用指定构造器", "Apply the named constructor"),
}


def rule_strategy(step, proof, *, language, path=(), index=None, style=""):
    config = STRATEGIES.get(step[RULE_ID_FIELD])
    branch_list = step[BRANCHES_FIELD]
    if not branch_list:
        raise ValueError("Dynamic strategy has no branches")
    lang = "zh" if language == "zh" else "en"
    children = []
    if config is not None:
        kind, _, _ = config
        intro_tag, intro_text, case_label = LAYOUTS[kind][lang]
        children.append(render_step(html.escape(intro_tag), html.escape(intro_text), sort="introducer"))
    else:
        case_label = ""
    for position, branch in enumerate(branch_list, start=1):
        label = (f"{case_label} {to_roman(position)}" + ("," if lang == "en" else "")) if config else branch["name"]
        children.append(render_details(True, html.escape(label), "",
            proof.render_branch(branch["proof"], position - 1, path + (f"{index}:{branch['name']}",))))
    title = config[1 if lang == "zh" else 2] if config else step[RULE_ID_FIELD].rsplit(".", 1)[-1]
    return render_strategy("", html.escape(title), "\n".join(children), style=style)
