"""Small public helpers for resolved structural expression occurrences."""

from __future__ import annotations


def unwrap_mdata(node: object, *, visit=None) -> tuple[object, dict]:
    """Read one occurrence's metadata wrappers, keeping each outer value first."""
    data = {}
    while isinstance(node, dict) and node.get("kind") == "mdata":
        if visit is not None:
            visit()
        for key, value in node["data"].items():
            data.setdefault(key, value)
        node = node["expr"]
    return node, data


def flatten_app(node: dict, *, visit=None) -> tuple[dict, list[dict]]:
    """Flatten applications through metadata, preserving each argument and head occurrence."""
    args: list[dict] = []
    current = node
    while True:
        structural, _ = unwrap_mdata(current, visit=visit)
        if not isinstance(structural, dict) or structural.get("kind") != "app":
            break
        if visit is not None:
            visit()
        args.append(structural["arg"])
        current = structural["fn"]
    args.reverse()
    return current, args
