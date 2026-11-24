from __future__ import annotations

import json
import hashlib
import re
from pathlib import Path

from PS4HTML.project import PS4HTMLError
from PS4HTML.recording import BRANCHES_FIELD, RULE_ID_FIELD


EXPRESSION_ID = re.compile(r"^e(0|[1-9][0-9]*)$")
BINDER_INFOS = {"default", "implicit", "strictImplicit", "instImplicit"}
CHILDREN = {"app": ("fn", "arg"), "lam": ("type", "body"),
            "forall": ("type", "body"), "let": ("type", "value", "body"),
            "proj": ("expr",), "mdata": ("expr",)}
REBUILD_HINT = "Rebuild with lake build <Library>:ps4html to regenerate recording data."
# Only these framework-owned rules give their ordinary field names schema meaning.
# User recorders may reuse the same spelling for arbitrary plain JSON.
BUILTIN_RECORDING_COLUMNS = {
    "simp": {"args", "config", "locations"},
    "field": {"args"},
    "rewrite": {"rules", "config", "locations"},
    "rw": {"rules", "config", "locations"},
    "rwPos": {"locations"}, "rwNeg": {"locations"},
    "decide": {"config"}, "nativeDecide": {"config"}, "omega": {"config"},
    "betaReduce": {"locations"}, "change": {"locations"}, "pointwise": {"locations"},
    "symm": {"locations"}, "unfold": {"locations"},
    "renderCalc": {"chain"}, "infer": {"chain"},
    "svg": {"metadata"}, "latex": {"metadata", "source"},
}
# Handwritten builtin recorders capture structured inputs before execution.


def _fail(message):
    raise PS4HTMLError(message)


def _nat(value):
    return type(value) is int and value >= 0


def _keys(value, expected, label):
    if not isinstance(value, dict) or set(value) != set(expected):
        _fail(f"Invalid {label} fields")


def validate_recorded_value(value, resolver, path, admitted=None):
    """Only tagged expression leaves can own a graph root; plain JSON is opaque."""
    _keys(value, {"kind", "value"}, "recorded value")
    kind, data = value["kind"], value["value"]
    if kind == "expression":
        resolver.require_root(path + ("value",), data)
        if admitted is not None:
            admitted.add(path + ("value",))
    elif kind == "array":
        if not isinstance(data, list):
            _fail("Recorded array value must be an array")
        for index, item in enumerate(data):
            validate_recorded_value(item, resolver, path + ("value", index), admitted)
    elif kind != "plain":
        _fail(f"Invalid recorded value kind: {kind!r}")


def recorded_data(value, kind):
    _keys(value, {"kind", "value"}, "recorded value")
    if value["kind"] != kind:
        _fail(f"Expected recorded {kind} value")
    return value["value"]


def _column(step, key, allowed, *, plain_type=str):
    items = recorded_data(step[key], "array")
    for item in items:
        kind, value = item["kind"], item["value"]
        if kind not in allowed or (kind == "plain" and
                (type(value) not in ((str,) if plain_type is str else (str, int, float)) or
                 type(value) is str and allowed["plain"] is not None and
                 value not in allowed["plain"])):
            _fail(f"Invalid recorded column {key}")
    return len(items)


def validate_recorded_columns(step, *, rule_id=None):
    """Check reserved state everywhere; check ordinary columns only for their owners."""
    for stage in ("before", "after"):
        context_names = f"$context_names_{stage}"
        context_types = f"$context_types_{stage}"
        if context_names in step or context_types in step:
            if context_names not in step or context_types not in step:
                _fail("Incomplete recorded context columns")
            if _column(step, context_names, {"plain": None}, plain_type=str) != _column(
                    step, context_types, {"expression": None}):
                _fail("Misaligned recorded context columns")
            names = [item["value"] for item in step[context_names]["value"]]
            if len(names) != len(set(names)):
                _fail("Duplicate recorded context name")
        goal_key = f"$goal_{stage}"
        if goal_key in step:
            goal = step[goal_key]
            if goal["kind"] != "expression" and goal != {"kind": "plain", "value": "completed"}:
                _fail("Invalid recorded goal state")
    columns_for_rule = BUILTIN_RECORDING_COLUMNS.get(rule_id, set())
    if not columns_for_rule:
        return
    for stage in ("before", "after"):
        groups = (
            ("args", {"kind": {"plain": {"star", "erase", "lemma"}},
                      "name": {"plain": None}, "phase": {"plain": {"pre", "post", "not applicable"}},
                      "direction": {"plain": {"forward", "backward", "not applicable"}},
                      "expression": {"plain": {"not applicable"}, "expression": None}}),
        )
        for prefix, columns in groups:
            if prefix not in columns_for_rule:
                continue
            keys = [f"{prefix}_{member}_{stage}" for member in columns]
            if stage == "before" or any(key in step for key in keys):
                if any(key not in step for key in keys) or len({
                        _column(step, key, allowed) for key, allowed in zip(keys, columns.values())}) != 1:
                    _fail(f"Incomplete or misaligned recorded {prefix} columns")
                if prefix == "args":
                    rows = zip(*(step[key]["value"] for key in keys))
                    for kind_item, name_item, phase_item, direction_item, expression in rows:
                        kind, name, phase, direction = (item["value"] for item in
                            (kind_item, name_item, phase_item, direction_item))
                        absent = "not applicable"
                        if kind == "star":
                            valid = (name, phase, direction, expression) == (
                                absent, absent, absent, {"kind": "plain", "value": absent})
                        elif kind == "erase":
                            valid = bool(name) and name != absent and phase == direction == absent
                        else:  # lemma
                            valid = (name == absent and phase in {"pre", "post"} and
                                     direction in {"forward", "backward"} and
                                     expression["kind"] == "expression")
                        if not valid:
                            _fail("Invalid recorded simp argument row")
    if "config" in columns_for_rule:
        if "config" not in step or type(recorded_data(step["config"], "plain")) is not str:
            _fail("Invalid recorded configuration")
    if "rules" in columns_for_rule:
        if "rules" not in step:
            _fail("Incomplete recorded rules")
        _column(step, "rules", {"expression": None})
    if "locations" in columns_for_rule:
        if "locations" not in step:
            _fail("Incomplete recorded location")
        _column(step, "locations", {"expression": None, "plain": {"all", "target"}})
        locations = step["locations"]["value"]
        markers = [item["value"] for item in locations if item["kind"] == "plain"]
        if markers.count("all") > 1 or markers.count("target") > 1 or (
                "all" in markers and len(locations) != 1):
            _fail("Invalid recorded location")
    for prefix, members in (("chain", ("rhs", "proof")),
                             ("metadata_extra", ("names", "values"))):
        if ("metadata" if prefix == "metadata_extra" else prefix) not in columns_for_rule:
            continue
        keys = [f"{prefix}_{member}" for member in members]
        if any(key not in step for key in keys):
            _fail(f"Incomplete recorded {prefix} columns")
        allowed = (({"plain": None}, {"plain": None}) if prefix == "metadata_extra" else
                   ({"expression": None}, {"expression": None, "plain": {"hole"}}))
        if _column(step, keys[0], allowed[0]) != _column(step, keys[1], allowed[1]):
            _fail(f"Misaligned recorded {prefix} columns")
    if rule_id == "renderCalc":
        if "chain_relation" not in step:
            _fail("Incomplete recorded calc relation column")
        if _column(step, "chain_relation", {"expression": None}) != _column(
                step, "chain_rhs", {"expression": None}):
            _fail("Misaligned recorded calc relation column")
    if "chain" in columns_for_rule:
        if "init" not in step or step["init"]["kind"] != "expression":
            _fail("Invalid recorded chain init")
        if not step["chain_rhs"]["value"]:
            _fail("Empty recorded chain")
    if "metadata" in columns_for_rule and any(
            key not in step for key in ("metadata_title", "metadata_label", "code")):
        _fail("Incomplete recorded metadata fields")
    if "source" in columns_for_rule and any(
            key not in step for key in ("source_language", "source_code")):
        _fail("Incomplete recorded source")
    for key in (("metadata_title", "metadata_label") if "metadata" in columns_for_rule else ()) + (
            ("source_language", "source_code") if "metadata" in columns_for_rule else ()):
        if key in step and (step[key]["kind"] != "plain" or not isinstance(step[key]["value"], str)):
            _fail(f"Invalid recorded {key}")
    if "metadata" in columns_for_rule and ("source_language" in step) != ("source_code" in step):
        _fail("Incomplete recorded source")
    if "metadata" in columns_for_rule and (step["code"]["kind"] != "plain" or
                                          type(step["code"]["value"]) is not str):
        _fail("Invalid recorded media code")


def json_path(value, path):
    """Follow typed JSON path parts without converting numeric strings to indices."""
    current = value
    for part in path:
        if isinstance(current, dict) and isinstance(part, str) and part in current:
            current = current[part]
        elif isinstance(current, list) and _nat(part) and part < len(current):
            current = current[part]
        else:
            _fail(f"Invalid expression root path: {list(path)!r}")
    return current


def _path(path):
    if not isinstance(path, (list, tuple)) or any(
            not (isinstance(part, str) or _nat(part)) for part in path):
        _fail("Expression paths must contain object keys or nonnegative array indices")
    return tuple(path)


def _level(level):
    if not isinstance(level, dict):
        _fail("Invalid expression universe level")
    kind = level.get("kind")
    if kind == "level.zero":
        _keys(level, {"kind"}, "universe level")
    elif kind == "level.succ":
        _keys(level, {"kind", "level"}, "universe level")
        _level(level["level"])
    elif isinstance(kind, str) and kind in {"level.max", "level.imax"}:
        _keys(level, {"kind", "u", "v"}, "universe level")
        _level(level["u"])
        _level(level["v"])
    elif isinstance(kind, str) and kind in {"level.param", "level.mvar"}:
        key = "name" if kind == "level.param" else "id"
        _keys(level, {"kind", key}, "universe level")
        if not isinstance(level[key], str):
            _fail("Invalid expression universe name")
    else:
        _fail(f"Unknown expression universe kind: {kind!r}")


class Expression(dict):
    """A native expression node; only structural graph edges are resolved lazily."""

    def __init__(self, resolver, reference):
        super().__init__(resolver.expressions[reference])
        self.resolver = resolver
        self.reference = reference

    def __getitem__(self, key):
        value = super().__getitem__(key)
        kind = super().get("kind")
        if key in CHILDREN.get(kind, ()):
            return self.resolver.node(value)
        return value

    def get(self, key, default=None):
        return self[key] if key in self else default

    def items(self):
        return ((key, self[key]) for key in self)

    def values(self):
        return (self[key] for key in self)


class ExpressionResolver:
    """Validate native expression graphs and resolve only registered roots."""

    def __init__(self, expressions, expression_roots=None, owner=None):
        if not isinstance(expressions, dict):
            _fail("Proof expressions must be an object")
        self.expressions = expressions
        self.owner = owner
        self.roots = set()
        self._paths = {}
        self._validate()
        if expression_roots is not None:
            if not isinstance(expression_roots, list) or owner is None:
                _fail("Expression roots require an owner and an array manifest")
            previous = None
            root_references = []
            for raw_path in expression_roots:
                if not isinstance(raw_path, list):
                    _fail("Expression root paths must be arrays")
                path = _path(raw_path)
                if not path or path in self.roots:
                    _fail("Expression root paths must be nonempty and unique")
                if path[0] in {"expressions", "expressionRoots", "recordingProtocol"}:
                    _fail("Expression roots cannot enter the owner expression table or manifest")
                order = tuple((0, part) if isinstance(part, str) else (1, part) for part in path)
                if previous is not None and order <= previous:
                    _fail("Expression root paths must follow object key and array index order")
                previous = order
                root_references.append(self.reference(json_path(owner, path)))
                self.roots.add(path)
            self._validate_postorder(root_references)
        if owner is not None:
            self._index(owner, ())

    def _index(self, value, path):
        if isinstance(value, (dict, list)):
            self._paths[id(value)] = path
            items = value.items() if isinstance(value, dict) else enumerate(value)
            for key, child in items:
                self._index(child, path + (key,))

    def _validate(self):
        expected = {f"e{i}" for i in range(len(self.expressions))}
        if set(self.expressions) != expected:
            _fail("Expression IDs must be canonical and contiguous from e0")
        for index in range(len(self.expressions)):
            reference = f"e{index}"
            node = self.expressions[reference]
            if not isinstance(node, dict):
                _fail(f"Expression {reference} must be a structural node")
            kind = node.get("kind")
            fields = {"bvar": {"index"}, "fvar": {"id"}, "mvar": {"id"},
                      "sort": {"level"}, "const": {"name", "levels"},
                      "app": {"fn", "arg"},
                      "lam": {"name", "type", "body", "binderInfo"},
                      "forall": {"name", "type", "body", "binderInfo"},
                      "let": {"name", "type", "value", "body", "nondep"},
                      "lit": {"lit"}, "proj": {"typeName", "index", "expr"},
                      "mdata": {"data", "expr"}}
            if not isinstance(kind, str) or kind not in fields:
                _fail(f"Unknown expression node kind: {kind!r}")
            _keys(node, fields[kind] | {"kind"}, f"{kind} expression")
            if kind == "mdata":
                data = node["data"]
                if not isinstance(data, dict) or not data or any(
                        not isinstance(key, str) or type(value) not in {str, bool, int}
                        for key, value in data.items()):
                    _fail(f"Expression {reference}.data must be a nonempty object of native metadata scalars")
            for edge, value in self._edges(node):
                child = self.reference(value)
                if int(child[1:]) >= index:
                    _fail(f"Expression {reference}.{edge} must refer to an earlier node")
            for key in ("id", "name", "typeName"):
                if key in node and not isinstance(node[key], str):
                    _fail(f"Expression {reference}.{key} must be a string")
            if "index" in node and not _nat(node["index"]):
                _fail(f"Expression {reference}.index must be a natural number")
            if "binderInfo" in node and (not isinstance(node["binderInfo"], str) or node["binderInfo"] not in BINDER_INFOS):
                _fail(f"Invalid expression binder information: {node['binderInfo']!r}")
            if kind == "let" and type(node["nondep"]) is not bool:
                _fail("Expression let.nondep must be a boolean")
            if kind == "sort":
                _level(node["level"])
            if kind == "const":
                if not isinstance(node["levels"], list):
                    _fail("Expression const.levels must be an array")
                for level in node["levels"]:
                    _level(level)
            if kind == "lit":
                literal = node["lit"]
                _keys(literal, {"kind", "value"}, "expression literal")
                if not ((literal["kind"] == "literal.nat" and _nat(literal["value"])) or
                        (literal["kind"] == "literal.str" and isinstance(literal["value"], str))):
                    _fail("Invalid expression literal")

    @staticmethod
    def _edges(node):
        for edge in CHILDREN.get(node["kind"], ()):
            yield edge, node[edge]

    def _validate_postorder(self, roots):
        """Check owner traversal order and reject table entries without a typed root."""
        visited = set()
        next_index = 0
        for root in roots:
            pending = [(root, False)]
            while pending:
                reference, complete = pending.pop()
                if reference in visited:
                    continue
                if complete:
                    if reference != f"e{next_index}":
                        _fail("Expression IDs must follow structural postorder from owner roots")
                    visited.add(reference)
                    next_index += 1
                    continue
                pending.append((reference, True))
                edges = list(self._edges(self.expressions[reference]))
                pending.extend((value["$ref"], False) for _, value in reversed(edges))
        if len(visited) != len(self.expressions):
            _fail("Expression table contains nodes unreachable from expressionRoots")

    def reference(self, value):
        if isinstance(value, Expression):
            if value.resolver is not self:
                _fail("Expression belongs to a different graph owner")
            return value.reference
        if not isinstance(value, dict) or set(value) != {"$ref"}:
            _fail("Registered expression roots must be exact expression references")
        reference = value["$ref"]
        if not isinstance(reference, str) or not EXPRESSION_ID.fullmatch(reference) or reference not in self.expressions:
            _fail(f"Unknown expression reference: {reference!r}")
        return reference

    def node(self, reference):
        if isinstance(reference, str):
            reference = {"$ref": reference}
        return Expression(self, self.reference(reference))

    def path_of(self, value, path=None):
        if path is not None:
            return _path(path)
        if isinstance(value, (dict, list)) and id(value) in self._paths:
            return self._paths[id(value)]
        return None

    def require_root(self, path, value=None):
        path = _path(path)
        if path not in self.roots:
            _fail(f"Declared expression is missing from expressionRoots: {list(path)!r}")
        if value is not None:
            self.reference(value)

    def resolve_at(self, path):
        path = _path(path)
        if self.owner is None:
            _fail("Expression resolver has no owner document")
        return self.resolve(json_path(self.owner, path), path)

    def resolve(self, value, path=None):
        if isinstance(value, Expression):
            self.reference(value)
            return value
        path = self.path_of(value, path)
        if path in self.roots:
            return self.node(value)
        if path is not None and len(path) >= 2 and path[0] == "proof" and self.owner is not None:
            # A plain tagged payload is opaque even when it resembles a reference.
            current = self.owner
            for part in path:
                if isinstance(current, dict) and current.get("kind") == "plain" and part == "value":
                    return value
                current = current[part]
        if isinstance(value, list):
            return [self.resolve(child, path + (index,) if path is not None else None)
                    for index, child in enumerate(value)]
        if isinstance(value, dict):
            return {key: self.resolve(child, path + (key,) if path is not None else None)
                    for key, child in value.items()}
        return value

def validate_document(document, *, module_protocol=False):
    """Validate the recording envelope and expression root ownership."""
    if not isinstance(document, dict):
        _fail("Proof document must be an object")
    if document.get("recordingProtocol") != 2 or type(document.get("recordingProtocol")) is not int:
        _fail(f"Unsupported recording protocol; {REBUILD_HINT}")
    base = {"recordingProtocol", "module", "code", "statement", "expressions", "expressionRoots"}
    extras = {"proof", "bindings"} if module_protocol else {"proof"}
    if not base <= set(document) or set(document) - (base | extras | {"semanticCode"}):
        _fail(f"Proof document requires the reserved statement and expression graph fields. {REBUILD_HINT}")
    if not isinstance(document["module"], str) or not document["module"] or not isinstance(document["code"], str):
        _fail("Proof document requires a module and source code")
    if module_protocol and "semanticCode" not in document:
        _fail("Proof document has no Verso semantic resource; rebuild the page-mode module")
    if "semanticCode" in document:
        reference = document["semanticCode"]
        _keys(reference, {"$resource"}, "Verso semantic reference")
        resource = reference["$resource"]
        _keys(resource, {"path", "hash", "mediaType", "encoding"}, "Verso semantic resource")
        if (not isinstance(resource["path"], str) or
                not resource["path"].startswith(".ProofScript/resources/") or
                not isinstance(resource["hash"], str) or
                not re.fullmatch(r"[0-9a-f]{64}", resource["hash"]) or
                resource["mediaType"] != "application/vnd.proofscript.verso-highlighted+json" or
                resource["encoding"] != "utf-8"):
            _fail("Invalid Verso semantic resource reference")
    from PS4HTML.recording import proof_steps
    try:
        if "proof" in document:
            proof_steps(document["proof"])
    except ValueError as error:
        _fail(str(error))
    resolver = ExpressionResolver(document["expressions"], document["expressionRoots"], document)
    statement_roots = set()
    if "statement" in document:
        statement = document["statement"]
        _keys(statement, {"parameters", "conditions", "conclusion"}, "theorem statement")
        if not isinstance(statement["parameters"], list) or not isinstance(statement["conditions"], list):
            _fail("Statement parameters and conditions must be arrays")
        statement_roots.add(("statement", "conclusion"))
        for index, parameter in enumerate(statement["parameters"]):
            _keys(parameter, {"variable", "type", "instance"}, "statement parameter")
            if type(parameter["instance"]) is not bool:
                _fail("Statement instance flag must be boolean")
            for key in ("variable", "type"):
                statement_roots.add(("statement", "parameters", index, key))
        statement_roots.update(("statement", "conditions", index) for index in range(len(statement["conditions"])))
        for path in statement_roots:
            resolver.require_root(path, json_path(document, path))
        for index in range(len(statement["parameters"])):
            node = resolver.node(statement["parameters"][index]["variable"])
            while node["kind"] == "mdata":
                node = node["expr"]
            if node["kind"] != "fvar":
                _fail("Statement parameter variable must be a free variable")
    def validate_records(steps):
        for record in steps:
            if BRANCHES_FIELD not in record:
                continue
            branches = record[BRANCHES_FIELD]
            if not isinstance(branches, list):
                _fail("Proof branches must be an array")
            for branch in branches:
                _keys(branch, {"name", "proof"}, "proof branch")
                if not isinstance(branch["name"], str) or not branch["name"] or not isinstance(branch["proof"], list):
                    _fail("Invalid proof branch")
                if branch["proof"]:
                    try:
                        proof_steps(branch["proof"])
                    except ValueError as error:
                        _fail(str(error))
                    validate_records(branch["proof"])
    validate_records(document.get("proof", []))
    admitted_roots = set()
    def validate_step_values(steps, parent):
        for index, step in enumerate(steps):
            step_path = parent + (index,)
            for key, value in step.items():
                if key not in {RULE_ID_FIELD, BRANCHES_FIELD}:
                    validate_recorded_value(value, resolver, step_path + (key,), admitted_roots)
            validate_recorded_columns(step, rule_id=step[RULE_ID_FIELD])
            if BRANCHES_FIELD in step:
                for branch_index, branch in enumerate(step[BRANCHES_FIELD]):
                    validate_step_values(branch["proof"], step_path + (BRANCHES_FIELD, branch_index, "proof"))
    if "proof" in document:
        validate_step_values(document["proof"], ("proof",))
    if resolver.roots != statement_roots | admitted_roots:
        _fail("Expression roots must match the theorem statement and tagged recorder expressions")
    for path in resolver.roots:
        if path in statement_roots:
            continue
        if len(path) < 3 or path[0] != "proof" or not _nat(path[1]):
            _fail("Proof expression root paths must belong to proof record data")
        # Structural branch metadata and rule IDs are not expression data.
        remaining = path[2:]
        record = document["proof"][path[1]]
        while remaining:
            key = remaining[0]
            if key == RULE_ID_FIELD:
                _fail("Expression roots cannot target proof protocol fields")
            if key == BRANCHES_FIELD:
                if len(remaining) < 5 or not _nat(remaining[1]) or remaining[2] != "proof" or not _nat(remaining[3]):
                    _fail("Expression roots cannot target branch metadata")
                record = record[BRANCHES_FIELD][remaining[1]]["proof"][remaining[3]]
                remaining = remaining[4:]
            else:
                break
        # Every root was admitted by validate_step_values; reject stray roots.
        if path not in admitted_roots:
            _fail("Proof expression root is not a recorded expression leaf")
    return resolver


def validate_computation_function(function):
    """Validate one computation's independent expression owner."""
    if not isinstance(function, dict) or type(function.get("recordingProtocol")) is not int or function["recordingProtocol"] != 2:
        _fail(f"Unsupported recording protocol; {REBUILD_HINT}")
    required = {"recordingProtocol", "declaration", "type", "expression", "implementation", "expressions", "expressionRoots"}
    _keys(function, required, "computation function")
    if not isinstance(function["declaration"], str) or not isinstance(function["type"], str):
        _fail("Computation function is missing expression provenance")
    resolver = ExpressionResolver(function["expressions"], function["expressionRoots"], function)
    # Computation has its own fixed format, independent of script recordings.
    for field in ("expression", "implementation"):
        resolver.require_root((field,), function[field])
    for path in resolver.roots:
        if path[0] in {"expressions", "expressionRoots", "declaration", "type"}:
            _fail("Computation expression roots cannot target protocol metadata")
    return resolver


class ResourceLoader:
    def __init__(self, project_root: Path, export_root: Path | None = None):
        self.project_root = project_root.resolve()
        self.export_root = (export_root or self.project_root / ".ProofScript").resolve()
        self.text_cache = {}

    def resource_path(self, value, media_type: str | None = None) -> tuple[Path, str]:
        if not isinstance(value, dict) or set(value) != {"$resource"}:
            raise PS4HTMLError("Invalid ProofScript resource reference")
        resource = value["$resource"]
        if not isinstance(resource, dict):
            raise PS4HTMLError("Invalid ProofScript resource metadata")
        path_value = resource.get("path")
        if not isinstance(path_value, str) or not path_value:
            raise PS4HTMLError("ProofScript resource path must be a non-empty string")
        if resource.get("encoding") != "utf-8":
            raise PS4HTMLError(f"Unsupported ProofScript resource encoding: {resource.get('encoding')}")
        if media_type is not None and resource.get("mediaType") != media_type:
            raise PS4HTMLError(f"Unexpected ProofScript resource media type: {resource.get('mediaType')}")
        expected_hash = resource.get("hash")
        if not isinstance(expected_hash, str) or not expected_hash:
            raise PS4HTMLError("ProofScript resource hash must be a non-empty string")

        relative = Path(path_value)
        if relative.is_absolute():
            raise PS4HTMLError("ProofScript resource path must be relative")
        if relative.parts[0] != ".ProofScript":
            raise PS4HTMLError("ProofScript resource is outside the export root")
        path = (self.export_root.joinpath(*relative.parts[1:])).resolve()
        resource_root = self.export_root
        try:
            path.relative_to(resource_root)
        except ValueError:
            raise PS4HTMLError("ProofScript resource escapes the allowed resource root") from None
        return path, expected_hash

    def read_text(self, value, media_type: str | None = None) -> str:
        path, expected_hash = self.resource_path(value, media_type)
        key = (path, expected_hash)
        if key not in self.text_cache:
            try:
                self.text_cache[key] = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError) as error:
                raise PS4HTMLError(f"Unable to read ProofScript resource {path}: {error}") from error
            content = self.text_cache[key]
            actual = hashlib.sha256(json.dumps(content, ensure_ascii=False,
                separators=(",", ":")).encode("utf-8")).hexdigest()
            if actual != expected_hash:
                raise PS4HTMLError(f"ProofScript resource hash mismatch: {path}")
        return self.text_cache[key]
