"""Visible placeholder for script invocations without an available recorder."""

import html

from PS4HTML.engine import render_details, render_step
from PS4HTML.recording import BRANCHES_FIELD


def rule_unrecorded(step, proof, *, language, path=(), index=None):
    blocks = [render_step(proof.text("script.unrecorded"), html.escape(step["name"]), sort="unknown")]
    for branch_index, branch in enumerate(step.get(BRANCHES_FIELD, [])):
        blocks.append(render_details(True, html.escape(branch["name"]), "",
            proof.render_branch(branch["proof"], branch_index, path + (f"{index}:{branch['name']}",))))
    return "\n".join(blocks)
