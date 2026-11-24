"""Render one recorded call using its proof module's resolved script_info rules."""

import html
import re

from PS4HTML.engine import render_step, render_strategy, render_details
from PS4HTML.dashboard import validate_dashboard, render_dashboard
from PS4HTML.Rules.calc import rule_calc
from PS4HTML.Rules.infer import rule_infer
from PS4HTML.Rules.media import render_svg
from PS4HTML.Rules.remark import rule_remark
from PS4HTML.Rules.admit import rule_admit
from PS4HTML.recording import BRANCHES_FIELD, RULE_ID_FIELD, branches, rule_id, slot_value, render_value, unpack
from Lean2TeX.model import DisplayNode


SPECIAL_RENDERERS = {
    "calc": rule_calc, "infer": rule_infer, "svg": render_svg,
    "remark": rule_remark, "admit": rule_admit,
}
COLOR = re.compile(r"#[0-9a-fA-F]{3,8}\Z")


def template_language(entry):
    if isinstance(entry, dict) and isinstance(entry.get("lang"), str):
        return entry["lang"]
    raise ValueError("Invalid template entry")


def validate_template(entries, kind):
    if not isinstance(entries, list) or not entries:
        raise ValueError("Invalid template")
    languages = []
    for entry in entries:
        language = template_language(entry)
        if not language or language in languages:
            raise ValueError("Invalid or duplicate template language")
        languages.append(language)
        strategy = kind == "strategy"
        dynamic = strategy and "case" in entry
        allowed = ({"lang", "tag", "introducer", "case"} if dynamic else
                   {"lang", "tag", "inline", "introducer", "cases"} if strategy else {"lang", "tag", "content"})
        required = ({"lang", "tag", "case"} if dynamic else
                    {"lang", "tag", "cases"} if strategy else {"lang", "tag", "content"})
        if set(entry) - allowed or not required <= set(entry) or not isinstance(entry["tag"], str):
            raise ValueError("Invalid template fields")
        if not strategy:
            if not isinstance(entry["content"], str):
                raise ValueError("Invalid template content")
            continue
        if dynamic:
            case = entry["case"]
            if not isinstance(case, dict) or not {"tag", "title"} <= set(case) or \
                    set(case) - {"tag", "title", "introducer"} or \
                    not isinstance(case["tag"], str) or not isinstance(case["title"], str):
                raise ValueError("Invalid dynamic strategy case")
            if "introducer" in entry:
                validate_introducer(entry["introducer"])
            if "introducer" in case:
                validate_introducer(case["introducer"])
            continue
        if "inline" in entry and type(entry["inline"]) is not bool:
            raise ValueError("Invalid inline flag")
        if "introducer" in entry:
            validate_introducer(entry["introducer"])
        cases = entry["cases"]
        if not isinstance(cases, list) or not cases or (entry.get("inline") and len(cases) != 1):
            raise ValueError("Invalid template cases")
        names = set()
        for case in cases:
            if not isinstance(case, dict) or not {"name", "tag", "title"} <= set(case) or \
                    set(case) - {"name", "tag", "title", "introducer"} or \
                    not isinstance(case["name"], str) or not case["name"] or \
                    not isinstance(case["tag"], str) or not isinstance(case["title"], str) or \
                    case["name"] in names:
                raise ValueError("Invalid template case")
            names.add(case["name"])
            if "introducer" in case:
                validate_introducer(case["introducer"])
        if entry.get("inline") and (cases[0]["tag"] or cases[0]["title"]):
            raise ValueError("Inline case must have empty tag and title")


def validate_introducer(value):
    if not isinstance(value, dict) or set(value) != {"tag", "content"} or \
            not all(isinstance(item, str) for item in value.values()):
        raise ValueError("Invalid template introducer")
SLOT = re.compile(r"\$\{([^}]+)\}")
RENDERER_FIELDS = {
    "calc": ("init", "chain_relation", "chain_rhs", "chain_proof"),
    "infer": ("init", "chain_rhs", "chain_proof"),
    "svg": ("metadata_title", "metadata_label", "metadata_extra_names", "metadata_extra_values", "code"),
    "remark": ("text",), "admit": ("reason",),
}


def validate_record(rule, step, *, resolver=None, path=None):
    """Check the actual data needed by this renderer or template."""
    if not isinstance(step, dict):
        raise ValueError("Recorded step must be an object")

    fields = rule["fields"]
    if rule["kind"] == "tactic" and fields.get("renderer", "default") == "default":
        validate_dashboard(step, fields.get("board", []), resolver, path)
    if fields.get("renderer", "default") != "default":
        renderer = fields["renderer"]
        for key in RENDERER_FIELDS[renderer]:
            if key not in step:
                raise ValueError(f"Missing recorded {renderer} field {key!r}")
        if renderer in ("calc", "infer"):
            columns = ["chain_rhs", "chain_proof"] + (["chain_relation"] if renderer == "calc" else [])
            if any(step[key]["kind"] != "array" for key in columns):
                raise ValueError(f"Invalid recorded {renderer} chain")
            arrays = [step[key]["value"] for key in columns]
            if not isinstance(arrays[0], list) or not arrays[0] or any(
                    not isinstance(items, list) or len(items) != len(arrays[0]) for items in arrays):
                raise ValueError(f"Invalid recorded {renderer} chain")
            for key in ("chain_rhs", "chain_relation") if renderer == "calc" else ("chain_rhs",):
                if any(item["kind"] != "expression" for item in step[key]["value"]):
                    raise ValueError(f"Invalid {renderer} {key} expression")
            if any(item["kind"] != "expression" and item != {"kind": "plain", "value": "hole"}
                   for item in step["chain_proof"]["value"]):
                raise ValueError(f"Invalid {renderer} proof state")
            if step["init"]["kind"] != "expression":
                raise ValueError(f"Invalid {renderer} init expression")
        elif renderer == "svg":
            if step["metadata_title"]["kind"] != "plain" or not isinstance(step["metadata_title"]["value"], str) or \
                    step["metadata_label"]["kind"] != "plain" or not isinstance(step["metadata_label"]["value"], str) or \
                    step["code"]["kind"] != "plain" or not isinstance(step["code"]["value"], str) or \
                    any(step[key]["kind"] != "array" for key in ("metadata_extra_names", "metadata_extra_values")) or \
                    len(step["metadata_extra_names"]["value"]) != len(step["metadata_extra_values"]["value"]) or \
                    any(item.get("kind") != "plain" or not isinstance(item["value"], str)
                        for key in ("metadata_extra_names", "metadata_extra_values") for item in step[key]["value"]) or \
                    (("source_language" in step) != ("source_code" in step)) or \
                    any(step[key]["kind"] != "plain" or not isinstance(step[key]["value"], str)
                        for key in ("source_language", "source_code") if key in step):
                raise ValueError("Invalid recorded svg fields")
        elif step[RENDERER_FIELDS[renderer][0]]["kind"] != "plain" or not isinstance(step[RENDERER_FIELDS[renderer][0]]["value"], str):
            raise ValueError(f"Invalid recorded {renderer} text field")
    elif fields.get("display") is not False:
        for entry in fields["template"]:
            if "case" in entry:
                top_texts = [entry["tag"]]
                branch_texts = [entry["case"]["tag"], entry["case"]["title"]]
                if "introducer" in entry:
                    top_texts.extend([entry["introducer"]["tag"], entry["introducer"]["content"]])
                if "introducer" in entry["case"]:
                    branch_texts.extend([entry["case"]["introducer"]["tag"],
                                         entry["case"]["introducer"]["content"]])
            else:
                top_texts = (
                    [entry["tag"], entry["content"]] if "content" in entry else
                    [entry["tag"]] + ([entry["introducer"]["tag"], entry["introducer"]["content"]]
                                      if "introducer" in entry else []) +
                    [text for case in entry.get("cases", []) for text in
                     [case["tag"], case["title"]] +
                     ([case["introducer"]["tag"], case["introducer"]["content"]]
                      if "introducer" in case else [])])
                branch_texts = []
            for text in top_texts:
                for name in SLOT.findall(text):
                    slot_value(step, name)
            for text in branch_texts:
                for name in SLOT.findall(text):
                    if name not in ("index", "index'"):
                        slot_value(step, name)
    if rule["kind"] == "strategy":
        branches = step.get(BRANCHES_FIELD)
        if not isinstance(branches, list) or not branches or any(not isinstance(branch, dict) or
                not isinstance(branch.get("name"), str) or not isinstance(branch.get("proof"), list) for branch in branches):
            raise ValueError("Invalid recorded strategy branches")
        names = [branch["name"] for branch in branches]
        if len(names) != len(set(names)):
            raise ValueError("Duplicate recorded strategy branch")
        if fields.get("renderer", "default") == "default" and fields.get("display") is not False:
            for entry in fields["template"]:
                if "case" in entry:
                    continue
                expected = {case["name"] for case in entry["cases"]}
                if set(names) != expected:
                    raise ValueError(f"Strategy branches do not match template {entry['lang']!r}")


def validate_rules(document, module, imports=None):
    if not isinstance(document, dict) or document.get("module") != module:
        raise ValueError(f"Invalid effective rendering rules for {module}")
    if not isinstance(document.get("imports"), list) or any(not isinstance(name, str) for name in document["imports"]):
        raise ValueError(f"Invalid effective rule imports for {module}")
    if imports is not None and document["imports"] != imports:
        raise ValueError(f"Effective rule imports do not match the module manifest for {module}")
    rules = document.get("rules")
    if not isinstance(rules, list):
        raise ValueError(f"Missing effective rendering rules for {module}")
    result = {}
    for entry in rules:
        if not isinstance(entry, dict) or not isinstance(entry.get("ruleId"), str) or entry.get("kind") not in ("tactic", "strategy", "metadata") or not isinstance(entry.get("fields"), dict):
            raise ValueError(f"Invalid rule entry for {module}")
        rule_id, fields = entry["ruleId"], entry["fields"]
        if "recordedFields" in entry:
            raise ValueError(f"Rule output declarations are unsupported for {rule_id}; rebuild with Lean")
        if rule_id in result:
            raise ValueError(f"Duplicate rule {rule_id} in {module}")
        if set(fields) - {"renderer", "template", "display", "color", "board"}:
            raise ValueError(f"Unsupported rendering fields for {rule_id}")
        board = fields.get("board", [])
        if not isinstance(board, list) or any(
                not isinstance(item, dict) or set(item) != {"name", "value"} or
                not isinstance(item["name"], str) or not isinstance(item["value"], str)
                for item in board):
            raise ValueError(f"Invalid board for {rule_id}")
        if "display" in fields and type(fields["display"]) is not bool:
            raise ValueError(f"Invalid display for {rule_id}")
        if "color" in fields and (not isinstance(fields["color"], list) or
                len(fields["color"]) != 3 or any(v is not None and
                (not isinstance(v, str) or not COLOR.fullmatch(v) or len(v) not in (4, 5, 7, 9))
                for v in fields["color"])):
            raise ValueError(f"Invalid color for {rule_id}")
        if "renderer" in fields:
            if fields["renderer"] != "default" and fields["renderer"] not in SPECIAL_RENDERERS:
                raise ValueError(f"Unknown renderer {fields['renderer']!r} for {rule_id}")
        if fields.get("renderer", "default") == "default" and "template" not in fields:
            raise ValueError(f"Incomplete template for {rule_id}")
        if "template" in fields:
            validate_template(fields["template"], entry["kind"])
        result[rule_id] = entry
    return result


def _language(entries, language):
    return next((entry for entry in entries if template_language(entry) == language), entries[0])


def _template(text, step, proof, branch_index=None):
    result = []
    last = 0
    for match in SLOT.finditer(text):
        result.append(html.escape(text[last:match.start()]))
        key = match.group(1)
        if branch_index is not None and key in ("index", "index'"):
            number = branch_index + (key == "index'")
            node = DisplayNode(str(number), "literal", metadata={
                "literalKind": "literal.nat", "value": str(number), "originalExprKind": "lit"}, generated=True)
            result.append(proof.renderer.render_display(node, language=proof.language))
            proof.diagnostics.extend(proof.renderer.diagnostics_dict())
        else:
            result.append(render_value(slot_value(step, key), proof, proof._structural_step + (key,)))
        last = match.end()
    result.append(html.escape(text[last:]))
    return "".join(result)


def _rule_style(fields):
    colors = fields.get("color", [None, None, None])
    tag, border, background = colors
    # Reset all values at the rule boundary so nested rules never inherit their parent's palette.
    values = {
        "--rule-tag-color": tag or "var(--text-color)",
        "--rule-tag-border": border or "var(--cases-color-light)",
        "--rule-left-border": border or "var(--border-color)",
        "--rule-background": background or "transparent",
    }
    return ' style="' + html.escape("; ".join(f"{key}: {value}" for key, value in values.items()), quote=True) + '"'


def _introducer(entry, step, proof, branch_index=None):
    if not entry or not entry["tag"] and not entry["content"]:
        return ""
    tag = _template(entry["tag"], step, proof, branch_index)
    content = _template(entry["content"], step, proof, branch_index)
    return render_step(tag, content, sort="introducer")


def render_rule(rule, step, proof, path, index):
    fields = rule["fields"]
    validate_record(rule, step, resolver=proof.expression_resolver, path=proof._structural_step)
    if fields.get("display") is False:
        return ""
    special = fields.get("renderer")
    if special is not None and special != "default":
        values = {key: unpack(value, proof, proof._structural_step + (key,))
                  for key, value in step.items() if key not in (RULE_ID_FIELD, BRANCHES_FIELD)}
        rendered = SPECIAL_RENDERERS[special](values, proof, language=proof.language)
        if "color" in fields and any(fields["color"]):
            return f'<div class="proof-rule-wrapper"{_rule_style(fields)}>{rendered}</div>'
        return rendered
    entry = _language(fields["template"], proof.language)
    title = _template(entry["tag"], step, proof)
    style = _rule_style(fields)
    if rule["kind"] != "strategy":
        content = _template(entry["content"], step, proof)
        dashboard = render_dashboard(step, fields.get("board", []), proof) if rule["kind"] == "tactic" else ""
        return render_step(title, content, style=style, dashboard=dashboard)
    children = [_introducer(entry.get("introducer"), step, proof)]
    if "case" in entry:
        case = entry["case"]
        for branch_index, branch in enumerate(step[BRANCHES_FIELD]):
            content = _introducer(case.get("introducer"), step, proof, branch_index)
            content += proof.render_branch(branch["proof"], branch_index,
                                           path + (f"{index}:{branch['name']}",))
            children.append(render_details(True, _template(case["tag"], step, proof, branch_index),
                                           _template(case["title"], step, proof, branch_index), content))
        return render_strategy("", title, "\n".join(child for child in children if child), style=style)
    branches = {branch["name"]: (index, branch["proof"]) for index, branch in enumerate(step[BRANCHES_FIELD])}
    for case in entry["cases"]:
        name = case["name"]
        case_content = _introducer(case.get("introducer"), step, proof)
        branch_index, branch_proof = branches[name]
        case_content += proof.render_branch(branch_proof, branch_index, path + (f"{index}:{name}",))
        if not entry.get("inline", False):
            case_content = render_details(True,
                _template(case["tag"], step, proof),
                _template(case["title"], step, proof), case_content)
        children.append(case_content)
    return render_strategy("", title, "\n".join(child for child in children if child), style=style)
