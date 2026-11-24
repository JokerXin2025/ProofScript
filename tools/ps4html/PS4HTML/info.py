"""Lossless Lean identities and immutable theorem facts for module exports."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from decimal import Decimal


def canonical(value):
    if isinstance(value, dict):
        return "{" + ",".join(canonical(key) + ":" + canonical(value[key]) for key in sorted(value)) + "}"
    if isinstance(value, list):
        return "[" + ",".join(map(canonical, value)) + "]"
    if isinstance(value, Decimal):
        text = format(value, "f")
        return (text.rstrip("0").rstrip(".") if "." in text else text) if value else "0"
    if isinstance(value, float):
        return canonical(Decimal(str(value)))
    if type(value) is int:
        from Lean2TeX.numerals import signed_decimal_digits
        return signed_decimal_digits(value)
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def project_id(package, library):
    return canonical({"package": package, "library": library})


def name_key(parts):
    """Use the name's components directly as a hashable Python identity."""
    if not isinstance(parts, list) or not parts or any(
        not (isinstance(part, str) and part or type(part) is int and part >= 0) for part in parts
    ):
        raise ValueError("Invalid lossless Lean name")
    return tuple(parts)


def name_text(parts):
    return ".".join(str(part) if type(part) is int or re.fullmatch(r"[^\W\d][\w'!?]*", part)
                    else f"«{part}»" for part in name_key(parts))


def printed_name_key(value):
    """Read Lean's printed Name without conflating quoted strings and numeric parts.

    A source declaration may quote an otherwise printable Unicode identifier,
    whereas ``name_text`` prints its lossless component without the quotes.
    """
    if not isinstance(value, str) or not value:
        raise ValueError("Invalid printed Lean name")
    parts = []
    start = 0
    while start < len(value):
        if value[start] == "«":
            end = value.find("»", start + 1)
            if end <= start + 1:
                raise ValueError("Invalid printed Lean name")
            part = value[start + 1:end]
            end += 1
        else:
            end = value.find(".", start)
            if end < 0:
                end = len(value)
            part = value[start:end]
            if not part or "«" in part or "»" in part:
                raise ValueError("Invalid printed Lean name")
            if part.isascii() and part.isdecimal():
                part = int(part)
        parts.append(part)
        if end == len(value):
            return name_key(parts)
        if value[end] != ".":
            raise ValueError("Invalid printed Lean name")
        start = end + 1
    raise ValueError("Invalid printed Lean name")


LeanName = tuple[str | int, ...]
TheoremKey = tuple[str, LeanName]


@dataclass(frozen=True)
class RefInfo:
    name: LeanName
    is_dependency: bool


@dataclass(frozen=True)
class TheoremRecord:
    declaration: LeanName
    declaration_kind: str
    project_id: str
    proof_refs: tuple[RefInfo, ...]
    proof_dependencies: tuple[LeanName, ...]
    owner: LeanName
    path: str

    @property
    def key(self) -> TheoremKey:
        return self.project_id, self.declaration
