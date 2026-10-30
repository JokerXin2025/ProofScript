"""Rebuild the statement design preview around an existing rendered proof page.

Usage: python3 examples/site/preview-theorem-statements.py /path/to/MeanValue.html
The input and its assets are read-only. The preview links to the original assets.
"""

import html
from pathlib import Path
import re
import sys
from urllib.parse import urljoin


def math(tex):
    return "$" + html.escape(tex) + "$"


def statement(name, language):
    en = language == "en"
    f, g = math("f"), math("g")
    point = math("x_0")
    interval = math("[a,b]")
    interior = math("(a,b)")
    pair = name.startswith("cauchy")
    fermat = name.startswith("fermat")
    parameters = [math(r"f\colon D_f\subseteq\mathbb R\longrightarrow\mathbb R")]
    if pair:
        parameters.append(math(r"g\colon D_g\subseteq\mathbb R\longrightarrow\mathbb R"))
    parameters.extend([math(r"x_0\in\mathbb R")] if fermat else [math(r"a\in\mathbb R"), math(r"b\in\mathbb R")])
    if fermat:
        conditions = [f"{f} is differentiable at {point}" if en else f"{f} 在 {point} 处可导"]
        relation = r"\le" if name.endswith("max") else r"\ge"
        conditions.append(math(r"\exists\,\delta>0,\quad\forall x\in(x_0-\delta,x_0+\delta),\quad f(x)" + relation + " f(x_0)"))
        conclusion = math(r"f'(x_0)=0")
    else:
        conditions = [math("a<b"), math(r"[a,b]\subseteq D_f\cap D_g" if pair else r"[a,b]\subseteq D_f")]
        if name == "rolle_meanvalue":
            conditions.append(math("f(a)=f(b)"))
        if name.endswith("'"):
            conditions.append(math(r"\forall x\in D_{g'},\quad g'(x)\ne0"))
        for function in ([f, g] if pair else [f]):
            conditions.append(f"{function} is continuous on {interval}" if en else f"{function} 在 {interval} 上连续")
        for function in ([f, g] if pair else [f]):
            conditions.append(f"{function} is differentiable on {interior}" if en else f"{function} 在 {interior} 内可导")
        equation = {
            "rolle_meanvalue": r"f'(\xi)=0",
            "lagrange_meanvalue": r"f'(\xi)=\frac{f(b)-f(a)}{b-a}",
            "cauchy_meanvalue": r"f'(\xi)\,[g(b)-g(a)]=g'(\xi)\,[f(b)-f(a)]",
            "cauchy_meanvalue'": r"\frac{f(b)-f(a)}{g(b)-g(a)}=\frac{f'(\xi)}{g'(\xi)}",
        }[name]
        conclusion = "<p>" + math(r"\exists\,\xi\in(a,b),") + "</p><p>" + math(equation) + "</p>"
    return (
        '<div class="theorem-statement" data-language="' + language + '" aria-label="' + ("Theorem statement" if en else "定理表述") + '">'
        '<div class="statement-parameters"><i class="statement-parameter-mark" aria-hidden="true"></i>' + "".join(f"<span>{value}</span>" for value in parameters) + '</div>'
        '<div class="statement-implication"><ul class="statement-conditions" aria-label="' + ("Assumptions" if en else "条件") + '">' 
        + "".join(f"<li>{value}</li>" for value in conditions)
        + '</ul><span class="statement-arrow" aria-hidden="true"></span>'
        '<div class="statement-conclusion">' + conclusion + '</div></div>'
        '<h3 class="statement-proof-divider">' + ("Proof" if en else "证明") + '</h3></div>'
    )


def main():
    source = Path(sys.argv[1]).resolve()
    document = source.read_text(encoding="utf-8")
    # Keep the real page's scripts, fonts, navigation and proof interactions working.
    def resource(match):
        attr, value = match.groups()
        if value.startswith(("#", "https:", "http:", "data:")):
            return match.group(0)
        if value.startswith(source.name + "#"):
            value = value[len(source.name):]
        else:
            value = urljoin(source.as_uri(), value)
        return f'{attr}="{value}"'
    document = re.sub(r'(href|src)="([^"]+)"', resource, document)
    pattern = r'(<section class="theorem-proof" id="theorem-([^\"]+)"[^>]*data-language-panel="(zh|en)"[^>]*>.*?<div class="proof-flip-front">)'
    def insert(match):
        header, name, language = match.groups()
        if language == "en":
            name = name.removesuffix("-en")
        return header + "\n" + statement(html.unescape(name), language)
    document, count = re.subn(pattern, insert, document, flags=re.S)
    if count != 12:
        raise ValueError(f"Expected six bilingual theorems, found {count}")
    css = Path(__file__).resolve().parents[2] / "tools/ps4html/PS4HTML/assets/css/theorem-statement.css"
    document = document.replace("</head>", "<style>\n" + css.read_text() + "\n</style>\n</head>")
    document = document.replace("<title>Calculus_21.Derivative.MeanValue</title>", "<title>中值定理 · 定理表述预览</title>")
    output = Path(__file__).with_name("theorem-statement.html")
    output.write_text(document, encoding="utf-8")
    print(f"Generated {output}: {count} statements, original proof bodies preserved")


if __name__ == "__main__":
    main()
