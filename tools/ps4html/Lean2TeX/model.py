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
class TemplateInstruction:
    """An insertion compiled by Lean, with its already resolved output mode."""

    kind: str
    content: str = ""
    index: int = 0
    depth: int = 0
    mode: str = "formula"
    max_precedence: bool = False
    instructions: tuple["TemplateInstruction", ...] = ()

    def as_dict(self) -> dict:
        if self.kind == "literal":
            return {"kind": self.kind, "content": self.content}
        if self.kind == "mode_switch":
            return {"kind": self.kind, "mode": self.mode,
                    "instructions": [item.as_dict() for item in self.instructions]}
        result = {"kind": self.kind, "index": self.index, "mode": self.mode,
                  "max_precedence": self.max_precedence}
        if self.kind in ("binder", "body"):
            result["depth"] = self.depth
        return result


@dataclass(frozen=True)
class DisplayTemplate:
    """A frozen template; local selectors map to stable native argument slots."""

    label: str
    mode: str
    content: str
    language: str | None
    precedence: int
    auto_arity: bool
    argument_indices: tuple[int, ...]
    instructions: tuple[TemplateInstruction, ...]
    binder_requirements: dict[int, int]

    @property
    def identity(self) -> tuple[str, str | None]:
        return self.label, self.language

    @property
    def effective_associativity(self) -> str:
        return {"$infixl": "left", "$infixr": "right"}.get(self.label, "none")

@dataclass(frozen=True)
class Macro:
    name: str
    kind: str
    arity: int
    templates: tuple[DisplayTemplate, ...]
    default_label: str | None

@dataclass(frozen=True)
class RenderTarget:
    """Extensible identity for a selectable render object."""

    kind: str
    key: str

    def as_key(self) -> str:
        return json.dumps([self.kind, self.key], ensure_ascii=False)


@dataclass(frozen=True)
class Unwrap:
    name: str
    argument: int
    arity: int
