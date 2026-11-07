"""Internal semantic display model and rendering diagnostics."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
from typing import Any


class RenderLimitError(ValueError):
    """The requested expression would exceed bounded rendering work or output."""


@dataclass
class DisplayNode:
    """A renderer-oriented tree independent from the recorded expression graph."""

    macro_name: str
    kind: str = ""
    children: list["DisplayNode"] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)
    generated: bool = False
    occurrence_id: str | None = None
    parent_id: str | None = None


def visible_node(node: DisplayNode) -> DisplayNode:
    """Follow transparent semantic wrappers to the node used by layout rules."""
    while node.kind in ("wrapper", "expression"):
        node = node.children[0]
    return node


@dataclass(frozen=True)
class RenderDiagnostic:
    severity: str
    code: str
    message: str
    constant: str | None = None
    path: tuple[int, ...] = ()

    def as_dict(self) -> dict[str, Any]:
        return {
            "severity": self.severity,
            "code": self.code,
            "message": self.message,
            "constant": self.constant,
            "path": list(self.path),
        }


@dataclass(frozen=True)
class DisplayTemplate:
    """One language-aware display template."""

    label: str
    mode: str
    content: str
    fixity: str = "custom"
    precedence: int = 100
    associativity: str = "none"
    binders: dict[int, int] = field(default_factory=dict)
    isolated_arguments: frozenset[int] = frozenset()
    language: str | None = None

@dataclass(frozen=True)
class Macro:
    name: str
    kind: str
    arguments: tuple[int, ...]
    templates: tuple[DisplayTemplate, ...]
    auto_arity: bool = True
    symbol: str | None = None
    default_label: str = "formula"
    fixity: str = "atom"
    precedence: int = 100
    associativity: str = "none"

@dataclass(frozen=True)
class RenderTarget:
    """Extensible identity for a selectable render object."""

    kind: str
    key: str

    def as_key(self) -> str:
        return json.dumps([self.kind, self.key], ensure_ascii=False)


# Keep the Python construction API stable while migrating persisted definitions.
MacroStyle = DisplayTemplate


@dataclass(frozen=True)
class Unwrap:
    name: str
    argument: int
