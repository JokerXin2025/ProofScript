"""Display native Lean universe levels without unfolding or JS number coercion."""

def _name(value: object) -> str:
    text = str(value)
    replacements = {"\\": r"\backslash ", "{": r"\{", "}": r"\}", "_": r"\_",
                    "%": r"\%", "#": r"\#", "&": r"\&", "$": r"\$",
                    "^": r"\^{}", "~": r"\sim ", "<": r"\lt ", ">": r"\gt "}
    return r"\mathrm{" + ("".join(replacements.get(char, char) for char in text) or "?") + "}"


def _level(level: dict, depth: int = 0) -> str:
    if depth > 256:
        raise ValueError("Universe level exceeds display depth limit")
    kind = level["kind"]
    if kind == "level.zero":
        return "0"
    if kind == "level.succ":
        inner = level["level"]
        if inner["kind"] == "level.zero":
            return "1"
        count = 1
        while inner["kind"] == "level.succ":
            count += 1
            if depth + count > 256:
                raise ValueError("Universe level exceeds display depth limit")
            inner = inner["level"]
        return str(count) if inner["kind"] == "level.zero" else f"{_level(inner, depth + count)}+{count}"
    if kind in ("level.max", "level.imax"):
        return r"\operatorname{" + kind[6:] + r"}\left(" + _level(level["u"], depth + 1) + "," + _level(level["v"], depth + 1) + r"\right)"
    return _name(level.get("name") if kind == "level.param" else level.get("id"))


def sort_styles(level: dict) -> dict[str, str]:
    """Return the two layouts for the level's outer constructor."""
    if level["kind"] == "level.zero":
        return {"prop": r"\mathbb{P}", "sort": r"\operatorname{Sort}\ 0"}
    if level["kind"] == "level.succ":
        inner = level["level"]
        return {"compact": r"\operatorname{Type}_{" + _level(inner) + "}",
                "structural": r"\operatorname{Sort}_{" + _level(level) + "}"}
    text = _level(level)
    if level["kind"] == "level.param":
        compact = r"\operatorname{Sort}_{" + text + "}"
    elif level["kind"] == "level.mvar":
        compact = r"\operatorname{Sort}_{?}"
    else:
        compact = r"\operatorname{Type}_{?}"
    return {"compact": compact, "structural": r"\operatorname{Sort}_{" + text + "}"}
