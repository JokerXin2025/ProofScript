"""Render one recorded call using its proof module's resolved script_info rules."""

import html
import re

from PS4HTML.engine import render_step, render_strategy, render_details
from PS4HTML.Rules.calc import rule_calc
from PS4HTML.Rules.infer import rule_infer
from PS4HTML.Rules.diagram import rule_svg, rule_latex
from PS4HTML.Rules.remark import rule_remark
from PS4HTML.Rules.admit import rule_admit
from PS4HTML.Rules.embed import rule_embed
from PS4HTML.Rules.strategy import rule_strategy
from PS4HTML.Rules.unrecorded import rule_unrecorded
from PS4HTML.recording import (PROOF_SCHEMA_VERSION, validate_contract,
                               validate_fields, validate_slots, slot_value,
                               slot_schema, validate_value)
from PS4HTML.schema import Expression


SPECIAL_RENDERERS = {
    "calc": rule_calc, "infer": rule_infer, "media": rule_latex,
    "diagram": rule_svg, "remark": rule_remark, "admit": rule_admit,
    "embed": rule_embed,
    "strategy": rule_strategy,
    "unrecorded": rule_unrecorded,
}
COLOR = re.compile(r"#[0-9a-fA-F]{3,8}\Z")


def template_language(entry):
    if isinstance(entry, dict) and isinstance(entry.get("lang"), str):
        return entry["lang"]
    raise ValueError("Invalid template entry")


def validate_template(entries, strategy):
    if not isinstance(entries, list) or not entries:
        raise ValueError("Invalid template")
    languages = []
    for entry in entries:
        language = template_language(entry)
        if not language or language in languages:
            raise ValueError("Invalid or duplicate template language")
        languages.append(language)
        allowed = {"lang", "tag", "inline", "introducer", "cases"} if strategy else {"lang", "tag", "content"}
        required = {"lang", "tag", "cases"} if strategy else {"lang", "tag", "content"}
        if set(entry) - allowed or not required <= set(entry) or not isinstance(entry["tag"], str):
            raise ValueError("Invalid template fields")
        if not strategy:
            if not isinstance(entry["content"], str):
                raise ValueError("Invalid template content")
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
    "calc": ("init", "chain"), "infer": ("init", "chain"),
    "media": ("metadata", "svg", "source"), "diagram": ("code",),
    "remark": ("text",), "admit": ("reason",),
    "embed": ("theorem", "args", "argKinds", "proof", "h", "type"),
    "strategy": ("branches",),
    "unrecorded": ("name",),
}


def template_texts(entries):
    for entry in entries:
        yield entry["tag"]
        if "content" in entry:
            yield entry["content"]
        if "introducer" in entry:
            yield from entry["introducer"].values()
        for case in entry.get("cases", []):
            yield case["tag"]
            yield case["title"]
            if "introducer" in case:
                yield from case["introducer"].values()


def validate_record(rule, step, *, resolver=None, path=None):
    """Check facts supplied by Lean; renderer implementations need not infer missing fields."""
    if not isinstance(step, dict):
        raise ValueError("Recorded step must be an object")
    validate_fields(step, rule.get("recordedFields"), resolver=resolver, path=path)
    fields = rule["fields"]
    if fields.get("display") is False:
        if rule["strategy"]:
            branches = step.get("branches")
            if not isinstance(branches, list) or not branches or any(
                    not isinstance(branch, dict) or not isinstance(branch.get("name"), str) or
                    not isinstance(branch.get("proof"), list) for branch in branches):
                raise ValueError("Invalid recorded strategy branches")
            names = [branch["name"] for branch in branches]
            if len(names) != len(set(names)):
                raise ValueError("Duplicate recorded strategy branch")
        return
    if fields.get("renderer", "none") != "none":
        renderer = fields["renderer"]
        for key in RENDERER_FIELDS[renderer]:
            if key not in step:
                raise ValueError(f"Missing recorded {renderer} field {key!r}")
        if renderer in ("calc", "infer"):
            chain = step["chain"]
            required = {"rhs", "proof", "relation"} if renderer == "calc" else {"rhs", "proof"}
            if not isinstance(chain, list) or not chain or any(not isinstance(link, dict) or not required <= link.keys() for link in chain):
                raise ValueError(f"Invalid recorded {renderer} chain")
        elif renderer == "embed":
            if not isinstance(step["theorem"], str) or not isinstance(step["args"], list) or \
                    not isinstance(step["argKinds"], list) or len(step["args"]) != len(step["argKinds"]) or \
                    any(kind not in ("data", "proof") for kind in step["argKinds"]):
                raise ValueError("Invalid recorded embed arguments")
            value = step["proof"]
            if not isinstance(value, (list, dict)) or (isinstance(value, dict) and "$resource" in value):
                raise ValueError("Embed proof must be recorded inline or as an expression")
        elif renderer == "media":
            if not isinstance(step["metadata"], dict) or not isinstance(step["source"], str) or \
                    not isinstance(step["svg"], (dict, str)):
                raise ValueError("Invalid recorded media fields")
        elif renderer != "strategy" and not isinstance(step[RENDERER_FIELDS[renderer][0]], str):
            raise ValueError(f"Invalid recorded {renderer} text field")
    else:
        for entry in fields["template"]:
            texts = (
                [entry["tag"], entry["content"]] if "content" in entry else
                [entry["tag"]] + ([entry["introducer"]["tag"], entry["introducer"]["content"]]
                                   if "introducer" in entry else []) +
                [text for case in entry.get("cases", []) for text in
                 [case["tag"], case["title"]] +
                 ([case["introducer"]["tag"], case["introducer"]["content"]]
                  if "introducer" in case else [])])
            for text in texts:
                for name in SLOT.findall(text):
                    slot_value(step, name)
    if rule["strategy"]:
        branches = step.get("branches")
        if not isinstance(branches, list) or not branches or any(not isinstance(branch, dict) or
                not isinstance(branch.get("name"), str) or not isinstance(branch.get("proof"), list) for branch in branches):
            raise ValueError("Invalid recorded strategy branches")
        names = [branch["name"] for branch in branches]
        if len(names) != len(set(names)):
            raise ValueError("Duplicate recorded strategy branch")
        if fields.get("renderer", "none") == "none":
            for entry in fields["template"]:
                expected = {case["name"] for case in entry["cases"]}
                if set(names) != expected:
                    raise ValueError(f"Strategy branches do not match template {entry['lang']!r}")


def validate_rules(document, module, imports=None):
    if not isinstance(document, dict) or document.get("schemaVersion") != PROOF_SCHEMA_VERSION or document.get("module") != module:
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
        if not isinstance(entry, dict) or not isinstance(entry.get("ruleId"), str) or not isinstance(entry.get("strategy"), bool) or not isinstance(entry.get("fields"), dict):
            raise ValueError(f"Invalid rule entry for {module}")
        rule_id, fields = entry["ruleId"], entry["fields"]
        if "recordedFields" not in entry:
            raise ValueError(f"Missing recordedFields contract for {rule_id}")
        validate_contract(entry.get("recordedFields"))
        if rule_id in result:
            raise ValueError(f"Duplicate rule {rule_id} in {module}")
        if set(fields) - {"renderer", "template", "display", "color"}:
            raise ValueError(f"Unsupported rendering fields for {rule_id}")
        if "display" in fields and type(fields["display"]) is not bool:
            raise ValueError(f"Invalid display for {rule_id}")
        if "color" in fields and (not isinstance(fields["color"], list) or
                len(fields["color"]) != 3 or any(v is not None and
                (not isinstance(v, str) or not COLOR.fullmatch(v) or len(v) not in (4, 5, 7, 9))
                for v in fields["color"])):
            raise ValueError(f"Invalid color for {rule_id}")
        if "renderer" in fields:
            if fields["renderer"] != "none" and fields["renderer"] not in SPECIAL_RENDERERS:
                raise ValueError(f"Unknown renderer {fields['renderer']!r} for {rule_id}")
        if fields.get("renderer", "none") == "none" and "template" not in fields:
            raise ValueError(f"Incomplete template for {rule_id}")
        if "template" in fields:
            validate_template(fields["template"], entry["strategy"])
            validate_slots(template_texts(fields["template"]), entry.get("recordedFields"))
        result[rule_id] = entry
    return result


def _language(entries, language):
    return next((entry for entry in entries if template_language(entry) == language), entries[0])


def _slot(value, proof, schema=None):
    # Resolution is manifest-based, including typed leaves deliberately composed
    # inside schema.json. An ordinary {kind: ...} or {$ref: ...} stays data.
    value = proof.resolve(value)
    if isinstance(value, Expression):
        return proof.tex(value)
    if schema and schema["kind"] == "optional":
        return _slot(value, proof, schema["element"])
    if schema and schema["kind"] == "union":
        for option in schema["options"]:
            try:
                validate_value(value, option, "template slot")
                return _slot(value, proof, option)
            except ValueError:
                continue
    if isinstance(value, list):
        element = schema["element"] if schema and schema["kind"] == "array" else None
        return ", ".join(_slot(item, proof, element) for item in value)
    if isinstance(value, str):
        return html.escape(value)
    if isinstance(value, (int, float, bool)):
        return html.escape(str(value))
    if value is None:
        return "—"
    if isinstance(value, dict) and schema and schema["kind"] == "expression":
        raise ValueError("Rendering expression requires a registered expression occurrence")
    if isinstance(value, dict):
        children = {field["name"]: field["schema"] for field in (schema or {}).get("fields", [])}
        return ", ".join(f"{html.escape(key)}: {_slot(item, proof, children.get(key))}"
                         for key, item in value.items())
    raise ValueError("Unsupported recorded template value")


def _template(text, step, proof):
    result = []
    last = 0
    for match in SLOT.finditer(text):
        result.append(html.escape(text[last:match.start()]))
        key = match.group(1)
        value = slot_value(step, key)
        rule = proof.current_rule or proof.rules.get(step.get("_ruleId"), {})
        contract = rule.get("recordedFields")
        result.append(_slot(value, proof, slot_schema(contract, key)))
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


def _introducer(entry, step, proof):
    if not entry or not entry["tag"] and not entry["content"]:
        return ""
    tag = _template(entry["tag"], step, proof)
    content = _template(entry["content"], step, proof)
    return render_step(tag, content, sort="introducer")


def render_rule(rule, step, proof, path, index):
    fields = rule["fields"]
    validate_record(rule, step, resolver=proof.expression_resolver, path=proof._structural_step)
    if fields.get("display") is False:
        return ""
    special = fields.get("renderer")
    if special is not None and special != "none":
        if special in ("embed", "strategy", "unrecorded"):
            handler = SPECIAL_RENDERERS[special]
            value = proof.resolve(step, path=proof._structural_step) if special == "embed" else step
            if special == "embed" and isinstance(step.get("proof"), list):
                value["proof"] = step["proof"]
            rendered = handler(value, proof, language=proof.language,
                                  path=path, index=index,
                                  **({"style": _rule_style(fields)} if special == "strategy" else {}))
        else:
            rendered = SPECIAL_RENDERERS[special](proof.resolve(step, path=proof._structural_step), proof, language=proof.language)
        if special != "strategy" and "color" in fields and any(fields["color"]):
            return f'<div class="proof-rule-wrapper"{_rule_style(fields)}>{rendered}</div>'
        return rendered
    entry = _language(fields["template"], proof.language)
    title = _template(entry["tag"], step, proof)
    style = _rule_style(fields)
    if not rule["strategy"]:
        content = _template(entry["content"], step, proof)
        return render_step(title, content, style=style)
    branches = {branch["name"]: (index, branch["proof"]) for index, branch in enumerate(step["branches"])}
    children = [_introducer(entry.get("introducer"), step, proof)]
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
