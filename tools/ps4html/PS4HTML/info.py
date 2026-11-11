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
    artifact_id: str
    snapshot_id: str
    owner: LeanName
    path: str

    @property
    def key(self) -> TheoremKey:
        return self.project_id, self.declaration
