"""Small public helpers for the ProofScript ExprJSON representation."""

from __future__ import annotations


def flatten_app(node: dict) -> tuple[dict, list[dict]]:
    """Return the head and left-to-right arguments of a binary app chain."""
    args: list[dict] = []
    current = node
    while isinstance(current, dict) and current.get("kind") == "app":
        args.append(current.get("arg", {}))
        current = current.get("fn", {})
    args.reverse()
    return current, args
