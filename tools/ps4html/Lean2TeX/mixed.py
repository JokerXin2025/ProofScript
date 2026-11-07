"""Safe HTML text atoms in linear (ungrouped) expression layouts.

The wire marker contains only hexadecimal Unicode scalar values and a fixed
style name. It survives the existing HTML escaping and is materialized only at
the page boundary, never inside a KaTeX group.
"""

import re


STYLES = {"plain": "span", "strong": "strong", "code": "code"}
ATOM = re.compile(r"\[\[PS4HTML-LITERAL-(plain|strong|code)-([0-9a-f]*)-(p[0-9]+)\]\]")
SELECTOR = re.compile(r"#([0-9]+)")


def atom(value: str, style: str, fragment: str) -> str:
    return f"[[PS4HTML-LITERAL-{style}-" + "".join(f"{ord(char):06x}" for char in value) + f"-{fragment}]]"


def linear_template(content: str, children: list) -> bool:
    """Only top-level selectors in an ungrouped TeX run can become HTML."""
    if any(char in content for char in "{}$") or "@" in content or "\\" in content:
        return False
    references = [int(match) for match in SELECTOR.findall(content)]
    return (bool(references) and all(index < len(children) for index in references)
            and any(children[index].kind == "literal" and
                    children[index].metadata.get("literalKind") == "literal.str" for index in references)
            and all(child.kind != "literal" or child.metadata.get("literalKind") != "literal.str"
                    or index in references for index, child in enumerate(children))
            and all(char in " #0123456789+-,.=<>:;!?()" for char in SELECTOR.sub("", content)))


def eligible_literals(root, registry, language: str, selections=None) -> set[int]:
    """Find literals for which the complete render root has a safe HTML layout."""
    if root.kind == "literal" and root.metadata.get("literalKind") == "literal.str":
        return {id(root)}
    if root.kind not in ("const", "concept"):
        return set()
    macro = registry.get(root.macro_name)
    if macro is None or macro.kind != "concept":
        return set()
    from .model import RenderTarget
    selected = (selections or {}).get(RenderTarget("constant", root.metadata.get("leanName", root.macro_name)))
    try:
        template = registry.template_for(macro, requested=selected, node=root, language=language)
    except ValueError:
        return set()
    if template.mode != "formula" or not linear_template(template.content, root.children):
        return set()
    if any(item.label != template.label and (item.language is None or item.language == language)
           for item in macro.templates):
        # A change of the containing constant template may move a literal into
        # a grouped math layout; the immutable browser tree cannot reclassify it.
        return set()
    for child in root.children:
        if child.kind == "literal" and child.metadata.get("literalKind") == "literal.str":
            continue
        if child.kind not in ("const", "literal", "fvar", "bvar", "binder", "sort", "metavariable"):
            return set()
        if child.kind == "const":
            configured = registry.get(child.macro_name)
            if configured is not None:
                try:
                    child_label = (selections or {}).get(RenderTarget("constant", child.metadata.get("leanName", child.macro_name)))
                    style = registry.template_for(configured, requested=child_label, node=child, language=language)
                except ValueError:
                    return set()
                if style.mode != "formula" or "$" in style.content:
                    return set()
    return {id(child) for child in root.children if child.kind == "literal"
            and child.metadata.get("literalKind") == "literal.str"}


def split_math(tex: str, wrap_math=None) -> str:
    """Turn top-level HTML atoms into math/text/math runs, retaining TeX runs."""
    result = []
    offset = 0
    for match in ATOM.finditer(tex):
        if match.start() > offset:
            part = tex[offset:match.start()]
            result.append("$" + (wrap_math(part) if wrap_math else part) + "$")
        result.append(match.group())
        offset = match.end()
    if offset < len(tex):
        part = tex[offset:]
        result.append("$" + (wrap_math(part) if wrap_math else part) + "$")
    return "".join(result)
