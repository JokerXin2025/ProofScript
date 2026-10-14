from string import Template
from pathlib import Path
from textwrap import indent
from PS4HTML.engine import render_annotation
from PS4HTML.Rules.media import _sanitize_svg, render_latex

CURRENT_DIR = Path(__file__).absolute().parent
TEMPLATE_DIAGRAM = Template((CURRENT_DIR.parent / "Templates/diagram.html").read_text())
DIAGRAM_ICON = '<i class="codicon codicon-symbol-color"></i>'


def _render_diagram(content):
    return render_annotation(sort="diagram", icon=DIAGRAM_ICON, content=content)


def rule_svg(svg, previous, subsequent, proof, *, language):
    code = svg["code"]
    if not isinstance(code, str):
        raise ValueError("svg.code must be a string")
    if not code:
        return "<!-- Silent Step: svg (empty) -->"
    figure = TEMPLATE_DIAGRAM.substitute(svg_code = indent(_sanitize_svg(code), "    "))
    return _render_diagram(figure)


def rule_latex(value, previous, subsequent, proof, *, language):
    rendered, diagnostics = render_latex(
        value, proof.project_root, proof.resource_loader, inline=True
    )
    proof.diagnostics.extend(diagnostics)
    return _render_diagram(rendered)
