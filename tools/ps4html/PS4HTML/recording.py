"""Recorded step envelopes and access to their actual template values."""

import html
import json

RULE_ID_FIELD = "$ruleId"
BRANCHES_FIELD = "$branches"


def rule_id(step):
    """Return the framework-owned rule ID from one recorded step."""
    return step.get(RULE_ID_FIELD) if isinstance(step, dict) else None


def branches(step):
    """Return framework-owned strategy branches, if present."""
    return step.get(BRANCHES_FIELD) if isinstance(step, dict) else None


def proof_steps(records):
    """Read one JSON object per script step."""
    if not isinstance(records, list) or not records:
        raise ValueError("proof must contain at least one step")
    if any(not isinstance(record, dict) for record in records):
        raise ValueError("proof records must be objects")
    for index, step in enumerate(records):
        if "_ruleId" in step:
            raise ValueError(
                f"proof record {index} uses the legacy recording protocol (_ruleId); "
                "rebuild the recording with lake build <Library>:ps4html"
            )
        if not isinstance(step.get(RULE_ID_FIELD), str) or not step[RULE_ID_FIELD]:
            raise ValueError(f"proof record {index} must contain a rule ID")
    return records


def slot_value(step, key):
    if key in step:
        return step[key]
    raise ValueError(f"Missing recorded template field {key!r}")


def render_value(value, proof, path=None):
    """Render a tagged recorder field, never interpreting opaque plain JSON as expressions."""
    if not isinstance(value, dict) or set(value) != {"kind", "value"}:
        raise ValueError("Invalid recorded value")
    kind, data = value["kind"], value["value"]
    if kind == "expression":
        return proof.tex(proof.resolve(data, path=path + ("value",) if path else None))
    if kind == "array":
        if not isinstance(data, list):
            raise ValueError("Invalid recorded array")
        return ", ".join(render_value(item, proof, path + ("value", index) if path else None)
                         for index, item in enumerate(data)) if data else "[]"
    if kind == "plain":
        if isinstance(data, str):
            return html.escape(data)
        if type(data) in (int, float):
            return html.escape(str(data))
        return html.escape(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    raise ValueError(f"Invalid recorded value kind {kind!r}")


def unpack(value, proof, path):
    """Return a typed leaf or a list of typed leaves for dedicated renderers."""
    kind, data = value["kind"], value["value"]
    if kind == "array":
        return [unpack(item, proof, path + ("value", index)) for index, item in enumerate(data)]
    if kind == "expression":
        return proof.resolve(data, path=path + ("value",))
    if kind == "plain":
        return data
    raise ValueError("Invalid recorded value kind")
