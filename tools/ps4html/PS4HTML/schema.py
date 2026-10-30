from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from PS4HTML.project import PS4HTMLError
from PS4HTML.recording import BRANCHES_FIELD, PROOF_SCHEMA_VERSION, RULE_ID_FIELD


EXPRESSION_ID = re.compile(r"^e(0|[1-9][0-9]*)$")
PROOF_MEDIA_TYPE = "application/vnd.proofscript.proof+json"
# Resource and computation envelopes keep their independent execution version.
SCHEMA_VERSION = "0.0.0"
BINDER_INFOS = {"default", "implicit", "strictImplicit", "instImplicit"}
CHILDREN = {"app": ("fn", "arg"), "lam": ("type", "body"),
            "forall": ("type", "body"), "let": ("type", "value", "body"),
            "proj": ("expr",), "mdata": ("expr",)}
REBUILD_HINT = "Rebuild with lake build <Library>:ps4html to regenerate recording data."


def _fail(message):
    raise PS4HTMLError(message)


def _nat(value):
    return type(value) is int and value >= 0


def _keys(value, expected, label):
    if not isinstance(value, dict) or set(value) != set(expected):
        _fail(f"Invalid {label} fields")


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
                if path[0] in {"expressions", "expressionRoots"}:
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
        if isinstance(value, list):
            return [self.resolve(child, path + (index,) if path is not None else None)
                    for index, child in enumerate(value)]
        if isinstance(value, dict):
            return {key: self.resolve(child, path + (key,) if path is not None else None)
                    for key, child in value.items()}
        return value

def validate_document(document):
    """Validate the recording envelope and expression root ownership."""
    if not isinstance(document, dict):
        _fail("Proof document must be an object")
    if document.get("schemaVersion") != PROOF_SCHEMA_VERSION:
        _fail(f"Unsupported recording schema version: {document.get('schemaVersion')!r}. {REBUILD_HINT}")
    base = {"schemaVersion", "module", "code", "statement", "expressions", "expressionRoots"}
    if not base <= set(document) or set(document) - (base | {"proof"}):
        _fail(f"Proof document requires the reserved statement and expression graph fields. {REBUILD_HINT}")
    if not isinstance(document["module"], str) or not document["module"] or not isinstance(document["code"], str):
        _fail("Proof document requires a module and source code")
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
    return resolver


def validate_computation_function(function):
    """Validate one computation's independent expression owner."""
    if not isinstance(function, dict) or function.get("recordingVersion") != PROOF_SCHEMA_VERSION:
        version = function.get("recordingVersion") if isinstance(function, dict) else None
        _fail(f"Unsupported computation recording version: {version!r}. {REBUILD_HINT}")
    required = {"recordingVersion", "declaration", "type", "expression", "implementation", "expressions", "expressionRoots"}
    _keys(function, required, "computation function")
    if not isinstance(function["declaration"], str) or not isinstance(function["type"], str):
        _fail("Computation function is missing expression provenance")
    resolver = ExpressionResolver(function["expressions"], function["expressionRoots"], function)
    # Computation has its own fixed format, independent of script recordings.
    for field in ("expression", "implementation"):
        resolver.require_root((field,), function[field])
    for path in resolver.roots:
        if path[0] in {"expressions", "expressionRoots", "recordingVersion", "declaration", "type"}:
            _fail("Computation expression roots cannot target protocol metadata")
    return resolver


@dataclass(frozen=True)
class LoadedProof:
    path: Path
    version: str
    code: str
    proof: list | None
    expressions: dict
    resolver: ExpressionResolver | None


class ResourceLoader:
    def __init__(self, project_root: Path, export_root: Path | None = None):
        self.project_root = project_root.resolve()
        self.export_root = (export_root or self.project_root / ".ProofScript").resolve()
        self.text_cache = {}
        self.proof_cache = {}

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
        return self.text_cache[key]

    def load_proof(self, value) -> LoadedProof:
        path, expected_hash = self.resource_path(value, PROOF_MEDIA_TYPE)
        key = (path, expected_hash)
        if key in self.proof_cache:
            return self.proof_cache[key]
        content = self.read_text(value, PROOF_MEDIA_TYPE)
        try:
            document = json.loads(content)
        except json.JSONDecodeError as error:
            raise PS4HTMLError(f"Invalid embedded proof JSON {path}: {error}") from error
        resolver = validate_document(document)
        version = document["schemaVersion"]
        proof = document.get("proof")
        expressions = document.get("expressions", {})
        code = document["code"]
        loaded = LoadedProof(path, version, code, proof, expressions, resolver)
        self.proof_cache[key] = loaded
        return loaded
