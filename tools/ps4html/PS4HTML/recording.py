"""Recorded step envelopes and access to their actual template values."""

PROOF_SCHEMA_VERSION = "0.4.0"
UNRECORDED_RULE_ID = "ProofScript.unrecorded"
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
    value = step
    for part in key.split("."):
        if value is None:
            return None
        if isinstance(value, dict) and part in value:
            value = value[part]
        elif isinstance(value, list) and part.isdigit() and int(part) < len(value):
            value = value[int(part)]
        else:
            raise ValueError(f"Missing recorded template field {key!r}")
    return value
