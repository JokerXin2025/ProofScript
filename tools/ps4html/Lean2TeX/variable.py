"""Allocate automatic mathematical names from frozen declaration prefixes."""

from __future__ import annotations

from contextlib import contextmanager
import re


class VariableAllocator:
    """Per-theorem prefix counters and generated names keyed by fvar identity."""

    def __init__(self, prefixes: dict[str, str] | None = None):
        self.prefixes = dict(prefixes or {})
        self.counters: dict[str, int] = {}
        self.generated_fvars: dict[str, str] = {}

    def reset(self) -> None:
        self.counters.clear()
        self.generated_fvars.clear()

    @contextmanager
    def transaction(self):
        """Restore allocation state when conversion or rendering raises."""
        counters = self.counters.copy()
        names = self.generated_fvars.copy()
        try:
            yield
        except Exception:
            self.counters = counters
            self.generated_fvars = names
            raise

    def allocate(self, descriptor: object, *, fvar_id: str | None = None) -> str:
        if fvar_id is not None and fvar_id in self.generated_fvars:
            return self.generated_fvars[fvar_id]
        prefix = self._prefix(descriptor)
        index = self.counters.get(prefix, 0) + 1
        self.counters[prefix] = index
        base = math_name(prefix)
        # An existing subscript or a compound prefix needs its own TeX group.
        if not re.fullmatch(r".|\\[A-Za-z]+", base):
            base = "{" + base + "}"
        name = f"{base}_{{{index}}}"
        if fvar_id is not None:
            self.generated_fvars[fvar_id] = name
        return name

    def _prefix(self, descriptor: object) -> str:
        if isinstance(descriptor, str):
            if descriptor.startswith("decl:"):
                declaration = descriptor[5:]
                return self.prefixes.get(declaration) or _declaration_initial(declaration)
            return {"proof": "h", "sort:Prop": "P", "sort:Type": "T",
                    "function": "f"}.get(descriptor, "v")
        return "v"


def _declaration_initial(name: str) -> str:
    """Read the last printed Lean Name component, including quoted dots."""
    part = ""
    quoted = False
    for char in name:
        if char == "«" and not quoted:
            if part:
                raise ValueError("Invalid printed declaration name escape")
            quoted = True
        elif char == "»" and quoted:
            quoted = False
        elif char == "." and not quoted:
            if not part:
                raise ValueError("Empty printed declaration name component")
            part = ""
        else:
            part += char
    if quoted or not part:
        raise ValueError("Invalid printed declaration name")
    return part[0]


def is_anonymous_name(name: object) -> bool:
    return (
        not isinstance(name, str) or not name
        or name in ("_", "[anonymous]", "_uniq")
        or name.startswith(("_uniq.", "_hyg.", "_@.", "__"))
        or "._hyg." in name or "._@." in name
    )


def math_name(name: str) -> str:
    """Group numeric subscripts in mathematical names, including Lean's digits."""
    suffix = len(name)
    while suffix > 0 and name[suffix - 1] in "₀₁₂₃₄₅₆₇₈₉":
        suffix -= 1
    base = re.sub(r"(?<!\\)_(\d+)$", r"_{\1}", name[:suffix])
    if suffix < len(name):
        digits = name[suffix:].translate(str.maketrans("₀₁₂₃₄₅₆₇₈₉", "0123456789"))
        if "_" in base:
            base = "{" + base + "}"
        return base + "_{" + digits + "}"
    return base
