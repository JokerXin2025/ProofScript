"""Static state comparison and recorded fields for ordinary script steps."""

import html

from PS4HTML.schema import Expression, recorded_data
from PS4HTML.recording import render_value
from PS4HTML.i18n import tr


CONTEXT_NAMES = ("$context_names_before", "$context_names_after")
CONTEXT_TYPES = ("$context_types_before", "$context_types_after")
GOAL_FIELDS = ("$goal_before", "$goal_after")


def validate_dashboard(step, board, resolver=None, path=None):
    """Check optional state data and any recorded expressions displayed by board."""
    if resolver is not None:
        path = resolver.path_of(step, path)
        if path is None:
            raise ValueError("Dashboard validation requires a step path")
    for names_key, types_key in zip(CONTEXT_NAMES, CONTEXT_TYPES):
        if names_key not in step and types_key not in step:
            continue
        if names_key not in step or types_key not in step:
            raise ValueError("Dashboard context columns must be recorded together")
        names = recorded_data(step[names_key], "array")
        types = recorded_data(step[types_key], "array")
        if len(names) != len(types) or any(item.get("kind") != "plain" or
                not isinstance(item["value"], str) for item in names) or \
                len({item["value"] for item in names}) != len(names) or \
                any(item.get("kind") != "expression" for item in types):
            raise ValueError("Invalid dashboard context columns")
    for field in GOAL_FIELDS:
        if field in step and step[field]["kind"] != "expression" and step[field] != {"kind": "plain", "value": "completed"}:
            raise ValueError("Dashboard goal must be an expression or completed")


def _reference(value, resolver):
    if value is None:
        return None
    return resolver.reference(value) if resolver is not None else value.reference if isinstance(value, Expression) else value["$ref"]


def _same_expression(left, right, resolver):
    if left is None or right is None:
        return left is None and right is None
    first, second = _reference(left, resolver), _reference(right, resolver)
    if resolver is None or first == second:
        return first == second
    # Compare graph content rather than allocation IDs; distinct root IDs can
    # represent identical expressions in the same recorded proof.
    def equal(a, b):
        if isinstance(a, dict) and set(a) == {"$ref"} and isinstance(b, dict) and set(b) == {"$ref"}:
            return equal(resolver.expressions[a["$ref"]], resolver.expressions[b["$ref"]])
        if isinstance(a, dict) and isinstance(b, dict):
            return set(a) == set(b) and all(equal(a[key], b[key]) for key in a)
        if isinstance(a, list) and isinstance(b, list):
            return len(a) == len(b) and all(equal(x, y) for x, y in zip(a, b))
        return type(a) is type(b) and a == b
    return equal(resolver.expressions[first], resolver.expressions[second])


def _context(step, before):
    side = 0 if before else 1
    if CONTEXT_NAMES[side] not in step:
        return None
    names = [item["value"] for item in step[CONTEXT_NAMES[side]]["value"]]
    return {name: index for index, name in enumerate(names)}


def _context_row(step, proof, before, name):
    context_key = CONTEXT_TYPES[0 if before else 1]
    other_context = _context(step, not before)
    context = _context(step, before)
    if context is None or name not in context:
        return '<div class="proof-dashboard-context-row proof-dashboard-blank" role="cell" aria-hidden="true"></div>'
    index = context[name]
    value = step[context_key]["value"][index]["value"]
    changed = other_context is not None and (
        name not in other_context or
        not _same_expression(value, step[CONTEXT_TYPES[1 if before else 0]]["value"][other_context[name]]["value"], proof.expression_resolver))
    rendered = render_value(step[context_key]["value"][index], proof,
                            proof._structural_step + (context_key, "value", index))
    marker = (f'<span class="proof-dashboard-marker {"removed" if before else "added"}" '
              f'aria-label="{tr("dashboard.removed" if before else "dashboard.added", proof.language)}">'
              f'{"－" if before else "＋"}</span>'
              if changed else '<span class="proof-dashboard-marker" aria-hidden="true"></span>')
    return (f'<div class="proof-dashboard-context-row" role="cell">{marker}'
            f'<span class="proof-dashboard-name">{html.escape(name)}</span> : {rendered}</div>')


def _goal(step, proof, before):
    goal_key = GOAL_FIELDS[0 if before else 1]
    goal = step.get(goal_key)
    if goal is None:
        text = '<span class="proof-dashboard-goal-mark">—</span>未记录'
    elif goal == {"kind": "plain", "value": "completed"}:
        text = '<span class="proof-dashboard-goal-mark proof-dashboard-complete"><i class="codicon codicon-check" aria-hidden="true"></i></span>目标已完成'
    else:
        text = ('<span class="proof-dashboard-goal-mark">⊢</span>' +
                render_value(goal, proof, proof._structural_step + (goal_key,)))
    return f'<div class="proof-dashboard-goal" role="cell">{text}</div>'


def render_dashboard(step, board, proof):
    """Render a full static panel; the interaction layer can later fold it away."""
    before_context = _context(step, True) or {}
    after_context = _context(step, False) or {}
    names = list(before_context) + [name for name in after_context if name not in before_context]
    rows = ['<div class="proof-dashboard-heading" role="row">' + "".join(
        f'<h3 role="columnheader">{tr(key, proof.language)}</h3>'
        for key in ("dashboard.before", "dashboard.after")) + '</div>']
    for name in names:
        rows.append('<div class="proof-dashboard-pair" role="row">' +
                    "".join(_context_row(step, proof, before, name) for before in (True, False)) + '</div>')
    rows.append('<div class="proof-dashboard-pair proof-dashboard-goals" role="row">' +
                "".join(_goal(step, proof, before) for before in (True, False)) + '</div>')
    result = '<div class="proof-dashboard"><div class="proof-dashboard-states" role="table">' + "".join(rows) + '</div>'
    if board:
        rows = []
        for item in board:
            key = item["value"]
            value = (render_value(step[key], proof, proof._structural_step + (key,))
                     if key in step else "未记录")
            rows.append(f'<div class="proof-dashboard-field"><span>{html.escape(item["name"])}</span>'
                        f'<span>{value}</span></div>')
        result += '<div class="proof-dashboard-board">' + "".join(rows) + '</div>'
    return result + '</div>'
