"""Project-scoped direct theorem edges, derived exclusively from validated proof facts."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Iterable

from PS4HTML.info import InfoBundle, LeanName, TheoremKey, TheoremRecord, digest, name_key, name_text
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

    @classmethod
    def from_bundle(cls, bundle: InfoBundle, pages=()):
        destinations = {}
        for page in pages:
            page_artifact = bundle.artifact(page.path)
            if page_artifact["kind"] != "page" or page_artifact["module"] != page.module:
                raise PS4HTMLError(f"Page does not match its bundle artifact: {page.path}")
            for order, component in enumerate(page.components):
                data = component.get("data", {}) if isinstance(component, dict) else {}
                if not isinstance(data, dict) or not ({"theorem", "lemma"} & data.keys()):
                    continue
                tag = "theorem" if "theorem" in data else "lemma"
                envelope = data[tag]
                value = envelope.get("value") if isinstance(envelope, dict) else None
                if not isinstance(value, dict) or not isinstance(value.get("proof"), str) or not value["proof"]:
                    raise PS4HTMLError(f"Theorem page component lacks an explicit proof artifact: {page.path}")
                record = bundle.theorem(value["proof"])
                if name_text(list(record.owner)) != page.module or record.snapshot_id != page_artifact["snapshotId"]:
                    raise PS4HTMLError(f"Theorem page reference disagrees with its proof owner/snapshot: {value['proof']}")
                if record.key in destinations:
                    raise PS4HTMLError(f"Ambiguous theorem page destination: {record.key}")
                title = value.get("name")
                if not isinstance(title, str) or not title:
                    raise PS4HTMLError(f"Theorem page component lacks a title: {value['proof']}")
                destinations[record.key] = TheoremDestination(
                    page.output_path, f"theorem-{name_text(list(record.declaration))}", title, order)
        modules = tuple(name_key(entry["name"]) for entry in bundle.index["modules"])
        return cls(bundle.theorems.values(), destinations=destinations, modules=modules)

    def title(self, key: TheoremKey) -> str:
        destination = self.destinations.get(key)
        return destination.title if destination else name_text(list(key[1]))

    def ordered(self, keys):
        def order(key):
            destination = self.destinations.get(key)
            return ((0, destination.output_path.as_posix(), destination.order) if destination else (1, "", 0),
                    key[0], name_order(key[1]))
        return tuple(sorted(keys, key=order))
