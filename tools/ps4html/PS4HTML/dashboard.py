"""Static state comparison and recorded fields for ordinary script steps."""

import html

from PS4HTML.schema import EXPRESSION_ID, Expression
from PS4HTML.i18n import tr


CONTEXT_FIELDS = ("$context_before", "$context_after")
GOAL_FIELDS = ("$goal_before", "$goal_after")


def _expression(value, resolver, path):
    if not isinstance(value, Expression) and not (
            isinstance(value, dict) and set(value) == {"$ref"} and
            isinstance(value["$ref"], str) and EXPRESSION_ID.fullmatch(value["$ref"])):
        raise ValueError("Dashboard state requires an expression reference")
    if resolver is not None:
        resolver.require_root(path, value)


def validate_dashboard(step, board, resolver=None, path=None):
    """Check optional state data and any recorded expressions displayed by board."""
    if resolver is not None:
        path = resolver.path_of(step, path)
        if path is None:
            raise ValueError("Dashboard validation requires a step path")
    for field in CONTEXT_FIELDS:
        if field not in step:
            continue
        context = step[field]
        if not isinstance(context, dict) or any(not isinstance(name, str) for name in context):
            raise ValueError(f"Invalid dashboard context {field}")
        for name, value in context.items():
            _expression(value, resolver, path + (field, name) if path is not None else None)
    for field in GOAL_FIELDS:
        if field in step and step[field] is not None:
            _expression(step[field], resolver, path + (field,) if path is not None else None)

    def validate_value(value, location):
        if isinstance(value, Expression) or isinstance(value, dict) and set(value) == {"$ref"}:
            _expression(value, resolver, location)
        elif isinstance(value, dict):
            for key, item in value.items():
                validate_value(item, location + (key,) if location is not None else None)
        elif isinstance(value, list):
            for index, item in enumerate(value):
                validate_value(item, location + (index,) if location is not None else None)

    for item in board:
        key = item["value"]
        if key in step:
            validate_value(step[key], path + (key,) if path is not None else None)


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


def _value(value, proof):
    if isinstance(value, Expression):
        return proof.tex(value)
    if isinstance(value, dict):
        return ", ".join(f"{html.escape(str(key))}: {_value(item, proof)}" for key, item in value.items())
    if isinstance(value, list):
        return ", ".join(_value(item, proof) for item in value)
    if value is None:
        return "—"
    return html.escape(str(value))


def _context_row(step, proof, before, name):
    context_key = CONTEXT_FIELDS[0 if before else 1]
    other_context = step.get(CONTEXT_FIELDS[1 if before else 0])
    context = step.get(context_key)
    if context is None or name not in context:
        return '<div class="proof-dashboard-context-row proof-dashboard-blank" role="cell" aria-hidden="true"></div>'
    value = context[name]
    changed = isinstance(other_context, dict) and (
        name not in other_context or
        not _same_expression(value, other_context[name], proof.expression_resolver))
    resolved = proof.resolve(value, path=proof._structural_step + (context_key, name))
    marker = (f'<span class="proof-dashboard-marker {"removed" if before else "added"}" '
              f'aria-label="{tr("dashboard.removed" if before else "dashboard.added", proof.language)}">'
              f'{"－" if before else "＋"}</span>'
              if changed else '<span class="proof-dashboard-marker" aria-hidden="true"></span>')
    return (f'<div class="proof-dashboard-context-row" role="cell">{marker}'
            f'<span class="proof-dashboard-name">{html.escape(name)}</span> : {_value(resolved, proof)}</div>')


def _goal(step, proof, before):
    goal_key = GOAL_FIELDS[0 if before else 1]
    goal = step.get(goal_key)
    if goal is None:
        text = '<span class="proof-dashboard-goal-mark proof-dashboard-complete"><i class="codicon codicon-check" aria-hidden="true"></i></span>目标已完成'
    else:
        text = ('<span class="proof-dashboard-goal-mark">⊢</span>' +
                _value(proof.resolve(goal, path=proof._structural_step + (goal_key,)), proof))
    return f'<div class="proof-dashboard-goal" role="cell">{text}</div>'


def render_dashboard(step, board, proof):
    """Render a full static panel; the interaction layer can later fold it away."""
    before_context = step.get(CONTEXT_FIELDS[0], {})
    after_context = step.get(CONTEXT_FIELDS[1], {})
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
            value = (_value(proof.resolve(step[key], path=proof._structural_step + (key,)), proof)
                     if key in step else "未记录")
            rows.append(f'<div class="proof-dashboard-field"><span>{html.escape(item["name"])}</span>'
                        f'<span>{value}</span></div>')
        result += '<div class="proof-dashboard-board">' + "".join(rows) + '</div>'
    return result + '</div>'
