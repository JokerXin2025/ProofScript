"""Selection of frozen declaration display names, independent of Lean identity."""


def validate_names(fields, target):
    if "name" in fields or "name_is_default" in fields:
        raise ValueError(f"L2T008: obsolete declaration name fields for {target}; rebuild exports")
    names = fields.get("names")
    tags = fields.get("tags")
    for label, entries in (("names", names), ("tags", tags)):
        if not isinstance(entries, list):
            raise ValueError(f"L2T008: invalid frozen {label} for {target}")
        languages = set()
        for index, entry in enumerate(entries):
            if (not isinstance(entry, dict) or set(entry) != {"lang", "value"} or
                    (entry["lang"] is not None and
                     (not isinstance(entry["lang"], str) or not entry["lang"])) or
                    not isinstance(entry["value"], str) or not entry["value"].strip()):
                raise ValueError(f"L2T008: invalid frozen {label}[{index}] for {target}")
            if label == "names":
                if entry["lang"] in languages:
                    raise ValueError(f"L2T008: duplicate name language for {target}")
                languages.add(entry["lang"])


def select_name(names, language, lean_name, *, theorem=False, lean_last_component=None):
    """Current language, neutral, English, then native Lean name."""
    by_language = {entry["lang"]: entry["value"] for entry in names}
    for candidate in dict.fromkeys((language, None, "en")):
        if candidate in by_language:
            return by_language[candidate]
    if theorem:
        return lean_last_component if lean_last_component is not None else lean_name.rsplit(".", 1)[-1]
    return lean_name
