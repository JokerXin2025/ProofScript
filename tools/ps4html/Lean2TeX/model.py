"""Internal semantic display model and rendering diagnostics."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class DisplayNode:
    """A renderer-oriented tree independent from ProofScript's ExprJSON shape."""

    macro_name: str
    kind: str = ""
    children: list["DisplayNode"] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class RenderDiagnostic:
    severity: str
    code: str
    message: str
    constant: str | None = None
    path: tuple[int, ...] = ()
    source_range: dict[str, Any] | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "severity": self.severity,
            "code": self.code,
            "message": self.message,
            "constant": self.constant,
            "path": list(self.path),
            "sourceRange": self.source_range,
        }


@dataclass(frozen=True)
class MacroStyle:
    name: str
    mode: str
    template: str
    fixity: str = "custom"
    precedence: int = 100
    associativity: str = "none"
    separator: str = ", "
    binders: dict[int, int] = field(default_factory=dict)
    isolated_arguments: frozenset[int] = frozenset()


@dataclass(frozen=True)
class Macro:
    name: str
    kind: str
    arguments: tuple[int, ...] | str
    styles: tuple[MacroStyle, ...]
    dynamic_arity: bool = False


@dataclass(frozen=True)
class Unwrap:
    name: str
    argument: int
