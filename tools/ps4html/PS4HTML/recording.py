"""Recording contracts and ordinary step fields."""

import math
from decimal import Decimal

PROOF_SCHEMA_VERSION = "0.0.0"
RESERVED = {"_ruleId", "branches"}


def proof_steps(records):
    """Read one JSON object per script step."""
    if not isinstance(records, list) or not records:
        raise ValueError("proof must contain at least one step")
    if any(not isinstance(record, dict) for record in records):
        raise ValueError("proof records must be objects")
    for index, step in enumerate(records):
        if not isinstance(step.get("_ruleId"), str) or not step["_ruleId"]:
            raise ValueError(f"proof record {index} must contain a rule ID")
    return records


def validate_schema(schema):
    if not isinstance(schema, dict):
        raise ValueError("Invalid parameter schema")
    kind = schema.get("kind")
    if kind in {"expression", "string", "name", "syntax", "number", "boolean", "json"}:
        keys = {"kind"}
    elif kind in {"array", "optional"}:
        keys = {"kind", "element"}
        validate_schema(schema.get("element"))
    elif kind == "literal":
        keys = {"kind", "value"}
        if not isinstance(schema.get("value"), str):
            raise ValueError("Invalid literal schema")
    elif kind == "object":
        keys = {"kind", "fields"}
        validate_contract(schema.get("fields"), nested=True)
    elif kind == "union":
        keys = {"kind", "options"}
        options = schema.get("options")
        if not isinstance(options, list) or not options:
            raise ValueError("Invalid union schema")
        for option in options:
            validate_schema(option)
    else:
        raise ValueError(f"Unknown parameter schema kind {kind!r}")
    if set(schema) != keys:
        raise ValueError(f"Invalid {kind} schema fields")


def validate_contract(fields, nested=False):
    if fields is None and not nested:
        return  # An external handwritten recorder may have an opaque contract.
    if not isinstance(fields, list):
        raise ValueError("Invalid recordedFields contract")
    names = set()
    for field in fields:
        keys = {"name", "schema"} if nested else {"name", "schema", "nullable"}
        if not isinstance(field, dict) or set(field) != keys:
            raise ValueError("Invalid recorded field")
        name = field["name"]
        if not isinstance(name, str) or not name or name in names or (not nested and name in RESERVED):
            raise ValueError(f"Invalid or duplicate recorded field {name!r}")
        names.add(name)
        if not nested and type(field["nullable"]) is not bool:
            raise ValueError(f"Invalid nullable flag for {name}")
        validate_schema(field["schema"])


def validate_value(value, schema, path):
    kind = schema["kind"]
    valid = False
    if kind == "json":
        valid = True
    elif kind == "expression":
        valid = isinstance(value, dict) and (
            set(value) == {"$ref"} and isinstance(value["$ref"], str) or
            isinstance(value.get("kind"), str) and type(value.get("isProp")) is bool)
    elif kind in {"string", "name", "syntax"}:
        valid = isinstance(value, str)
    elif kind == "number":
        valid = type(value) in (int, float, Decimal) and (type(value) is int or math.isfinite(value))
    elif kind == "boolean":
        valid = type(value) is bool
    elif kind == "literal":
        valid = value == schema["value"]
    elif kind == "optional":
        if value is None:
            return
        return validate_value(value, schema["element"], path)
    elif kind == "array" and isinstance(value, list):
        for index, item in enumerate(value):
            validate_value(item, schema["element"], f"{path}.{index}")
        return
    elif kind == "object" and isinstance(value, dict):
        if set(value) == {field["name"] for field in schema["fields"]}:
            for field in schema["fields"]:
                validate_value(value[field["name"]], field["schema"], f"{path}.{field['name']}")
            return
    elif kind == "union":
        for option in schema["options"]:
            try:
                validate_value(value, option, path)
                return
            except ValueError:
                pass
    if not valid:
        raise ValueError(f"Recorded field {path!r} does not match {kind} schema")


def validate_fields(step, fields):
    if fields is None:
        return
    for field in fields:
        name = field["name"]
        if name not in step:
            raise ValueError(f"Missing recorded field {name!r}")
        if step[name] is None and field["nullable"]:
            continue
        validate_value(step[name], field["schema"], name)


def schema_has_path(schema, parts):
    return schema_at_path(schema, parts) is not None


def schema_at_path(schema, parts):
    if not parts or schema["kind"] == "json":
        return schema
    kind = schema["kind"]
    if kind == "optional":
        return schema_at_path(schema["element"], parts)
    if kind == "union":
        options = [result for option in schema["options"]
                   if (result := schema_at_path(option, parts)) is not None]
        return {"kind": "union", "options": options} if options else None
    if kind == "array" and parts[0].isascii() and parts[0].isdigit():
        return schema_at_path(schema["element"], parts[1:])
    if kind == "object":
        field = next((field for field in schema["fields"] if field["name"] == parts[0]), None)
        if field:
            return schema_at_path(field["schema"], parts[1:])
    return None


def slot_schema(fields, key):
    if fields is None:
        return None
    exact = next((field for field in fields if field["name"] == key), None)
    if exact:
        return exact["schema"]
    root, *parts = key.split(".")
    field = next((field for field in fields if field["name"] == root), None)
    return schema_at_path(field["schema"], parts) if field else None


def validate_slots(texts, fields):
    import re
    if fields is None:
        return
    schemas = {field["name"]: field["schema"] for field in fields}
    for text in texts:
        if any("}" not in fragment for fragment in text.split("${")[1:]):
            raise ValueError("Unclosed template slot")
        for slot in re.findall(r"\$\{([^}]+)\}", text):
            if slot in schemas:
                continue
            root, *parts = slot.split(".")
            if root not in schemas or not schema_has_path(schemas[root], parts):
                raise ValueError(f"Unknown recorded template field {slot!r}")


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
