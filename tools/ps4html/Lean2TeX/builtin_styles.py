"""Built-in identities and style labels shared by page catalog and renderer.

Only ACTIVE_KEYS have implementations in both Python and browser layout.
"""

from dataclasses import dataclass

from .model import RenderTarget


SORT_LEVEL_KINDS = (
    "level.zero", "level.succ", "level.max", "level.imax",
    "level.param", "level.mvar",
)


@dataclass(frozen=True)
class BuiltinStyleFamily:
    key: str
    default: str
    labels: tuple[str, ...]

    @property
    def target(self) -> RenderTarget:
        return RenderTarget("builtin", self.key)


STYLE_FAMILIES = (
    BuiltinStyleFamily("lambda", "mapsto", ("mapsto", "fun", "typed")),
    BuiltinStyleFamily("application", "call", ("call", "juxtaposed")),
    BuiltinStyleFamily("forall.dependent", "phrase", ("phrase", "symbol")),
    BuiltinStyleFamily("forall.arrow", "implies", ("implies", "arrow")),
    BuiltinStyleFamily("let", "where", ("where", "inline", "stacked")),
    BuiltinStyleFamily("sort.level.zero", "prop", ("prop", "sort")),
    *(BuiltinStyleFamily(f"sort.{kind}", "compact", ("compact", "structural"))
      for kind in SORT_LEVEL_KINDS if kind != "level.zero"),
    BuiltinStyleFamily("metavariable", "question", ("question", "unknown")),
    BuiltinStyleFamily("literal.nat", "decimal", (
        "decimal", "chinese-simplified", "chinese-traditional", "greek-ionian", "roman")),
    BuiltinStyleFamily("literal.str", "plain", ("plain", "strong", "code")),
)


@dataclass(frozen=True)
class NumeralSystem:
    label: str
    maximum_decimal: str | None
    zero: str


NUMERAL_SYSTEMS = (
    NumeralSystem("decimal", None, "0"),
    NumeralSystem("chinese-simplified", "9" * 48, "零"),
    NumeralSystem("chinese-traditional", "9" * 48, "零"),
    NumeralSystem("greek-ionian", "9999", "μηδέν"),
    NumeralSystem("roman", "3999", r"\mathrm{N}"),
)


STYLE_BY_KEY = {family.key: family for family in STYLE_FAMILIES}
ACTIVE_KEYS = frozenset({"lambda", "application", "forall.dependent", "forall.arrow", "let",
                         "metavariable", "literal.nat", "literal.str", *(f"sort.{kind}" for kind in SORT_LEVEL_KINDS)})


def target_for_node(node) -> RenderTarget | None:
    """Identify a built-in display object without changing its layout."""
    if node.kind == "forall":
        key = "forall.arrow" if node.metadata.get("isArrow") else "forall.dependent"
    elif node.kind == "sort":
        level = node.metadata.get("level")
        kind = level.get("kind") if isinstance(level, dict) else None
        key = f"sort.{kind}"
    elif node.kind == "literal":
        key = node.metadata.get("literalKind")
    else:
        key = {"lambda": "lambda", "let": "let", "application": "application",
               "metavariable": "metavariable"}.get(node.kind)
    family = STYLE_BY_KEY.get(key)
    return family.target if family is not None else None
