"""Direct edges from the validated projection of automatic references in each source project."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Iterable

from PS4HTML.info import LeanName, TheoremKey, TheoremRecord, digest, name_text
from PS4HTML.project import PS4HTMLError


def theorem_id(key: TheoremKey) -> str:
    """A logical identity shared by body translations and navigation, independent of HTML anchors."""
    return "theorem-" + digest({"projectId": key[0], "declaration": list(key[1])})


def name_order(name: LeanName):
    # A stable total order, not an attempt to reproduce Lean Name.cmp.
    return tuple((0, part) if isinstance(part, str) else (1, part) for part in name)


@dataclass(frozen=True)
class TheoremNode:
    key: TheoremKey
    record: TheoremRecord | None


@dataclass(frozen=True)
class TheoremDestination:
    output_path: Path
    anchor: str
    title: str
    order: int


class TheoremGraph:
    def __init__(self, records: Iterable[TheoremRecord], *, destinations=None, modules=()):
        nodes = {}
        sources = {}
        for record in records:
            if record.key in nodes:
                raise PS4HTMLError(f"Duplicate/conflicting theorem facts: {record.key}")
            nodes[record.key] = TheoremNode(record.key, record)
            sources[record.key] = record
        uses = {key: set() for key in nodes}
        used_by = {key: set() for key in nodes}
        for source, record in sources.items():
            for declaration in record.proof_dependencies:
                target = (record.project_id, declaration)
                if target == source or target in uses[source]:
                    raise PS4HTMLError(f"Self/duplicate theorem dependency: {source}")
                if target not in nodes:
                    nodes[target] = TheoremNode(target, None)
                    uses[target] = set()
                    used_by[target] = set()
                uses[source].add(target)
                used_by[target].add(source)
        destinations = dict(destinations or {})
        if any(key not in sources for key in destinations):
            raise PS4HTMLError("Page destination has no exported theorem proof facts")
        self.nodes = MappingProxyType(nodes)
        self.uses = MappingProxyType({key: frozenset(edges) for key, edges in uses.items()})
        self.used_by = MappingProxyType({key: frozenset(edges) for key, edges in used_by.items()})
        self.destinations = MappingProxyType(destinations)
        # Coverage describes this bundle, never all modules of a ProjectId.
        self.modules = tuple(modules)

    def title(self, key: TheoremKey) -> str:
        destination = self.destinations.get(key)
        return destination.title if destination else name_text(list(key[1]))

    def ordered(self, keys):
        def order(key):
            destination = self.destinations.get(key)
            return ((0, destination.output_path.as_posix(), destination.order) if destination else (1, "", 0),
                    key[0], name_order(key[1]))
        return tuple(sorted(keys, key=order))
