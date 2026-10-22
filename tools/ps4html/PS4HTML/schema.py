from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from PS4HTML.project import PS4HTMLError
from PS4HTML.recording import PROOF_SCHEMA_VERSION


EXPRESSION_ID = re.compile(r"^e(0|[1-9][0-9]*)$")
PROOF_MEDIA_TYPE = "application/vnd.proofscript.proof+json"
# Resource and computation envelopes keep their independent execution version.
SCHEMA_VERSION = "0.0.0"
BINDER_INFOS = {"default", "implicit", "strictImplicit", "instImplicit"}
CHILDREN = {"app": ("fn", "arg"), "lam": ("type", "body"),
            "forall": ("type", "body"), "let": ("type", "value", "body"),
            "proj": ("expr",)}
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
    """A typed expression occurrence. Display hints belong to this view and path.

    The dictionary contains only the structural node fields. Children are exposed
    lazily to avoid expanding a shared DAG into an exponential JSON tree.
    """

    def __init__(self, resolver, reference, display=None, view=None, path=()):
        super().__init__(resolver.expressions[reference])
        self.resolver = resolver
        self.reference = reference
        self.display = display
        self.view = view
        self.occurrence_path = tuple(path)

    def __getitem__(self, key):
        value = super().__getitem__(key)
        if key in CHILDREN.get(super().get("kind"), ()):
            return Expression(self.resolver, value["$ref"], self.display, self.view,
                              self.occurrence_path + (key,))
        return value

    def get(self, key, default=None):
        return self[key] if key in self else default

    def items(self):
        return ((key, self[key]) for key in self)

    def values(self):
        return (self[key] for key in self)

    def child(self, edge):
        if edge not in CHILDREN.get(self.get("kind"), ()):
            _fail(f"Invalid {self.get('kind')} expression edge: {edge}")
        return self[edge]

    @property
    def hint(self):
        if self.display is None:
            return {}
        return self.display.hints[self.view].get(self.occurrence_path, {})

    def resolve_view(self, index):
        if index is None or self.display is None:
            return None
        return self.display.expression(index)

    @property
    def declaration(self):
        value = self.hint.get("declaration")
        if value is None:
            return None
        return {"name": value["name"], "type": self.resolve_view(value["typeView"]),
                "value": self.resolve_view(value["valueView"])}

    @property
    def is_prop(self):
        return self.hint.get("isProp")

    @property
    def source_range(self):
        return self.hint.get("sourceRange")


class Display:
    def __init__(self, resolver, value, roots, hints):
        self.resolver = resolver
        self.value = value
        self.roots = roots
        self.hints = hints

    def expression(self, index):
        return Expression(self.resolver, self.roots[index], self, index)


class ExpressionResolver:
    """Validate structural nodes and resolve only explicitly registered roots."""

    def __init__(self, expressions, expression_roots=None, owner=None):
        if not isinstance(expressions, dict):
            _fail("Proof expressions must be an object")
        self.expressions = expressions
        self.owner = owner
        self.roots = set()
        self.displays = {}
        self._paths = {}
        self._validate()
        if expression_roots is not None:
            if not isinstance(expression_roots, list) or owner is None:
                _fail("Expression roots require an owner and an array manifest")
            for raw_path in expression_roots:
                if not isinstance(raw_path, list):
                    _fail("Expression root paths must be arrays")
                path = _path(raw_path)
                if not path or path in self.roots:
                    _fail("Expression root paths must be nonempty and unique")
                self.reference(json_path(owner, path))
                self.roots.add(path)
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
                      "lit": {"lit"}, "proj": {"typeName", "index", "expr"}}
            if not isinstance(kind, str) or kind not in fields:
                _fail(f"Unknown expression node kind: {kind!r}")
            _keys(node, fields[kind] | {"kind"}, f"{kind} expression")
            for edge in CHILDREN.get(kind, ()):
                child = self.reference(node[edge])
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
            return value
        path = self.path_of(value, path)
        if path in self.roots:
            display_view = self.displays.get(path)
            if display_view is not None:
                return display_view[0].expression(display_view[1])
            return self.node(value)
        if isinstance(value, list):
            return [self.resolve(child, path + (index,) if path is not None else None)
                    for index, child in enumerate(value)]
        if isinstance(value, dict):
            return {key: self.resolve(child, path + (key,) if path is not None else None)
                    for key, child in value.items()}
        return value

    def apply_fields(self, step, fields, path=None):
        from PS4HTML.recording import validate_fields
        validate_fields(step, fields, resolver=self, path=path)
        return self.resolve(step, path)

    def register_display(self, step, display_field, field, path=None):
        path = self.path_of(step, path)
        if path is None:
            _fail("Display validation requires its owner path")
        display = validate_display(self, step[display_field], step, field,
                                   path, path + (display_field,))
        for index, view in enumerate(display.value["views"]):
            if view["root"]["kind"] == "field":
                target = path + (field,) + tuple(view["root"]["path"])
            else:
                target = path + (display_field, "views", index, "root", "expression")
            self.displays[target] = (display, index)
        return display


def validate_display(resolver, value, step, field, step_path=(), display_path=None):
    """Explicitly validate a declared Display. Never discover markers in JSON."""
    _keys(value, {"kind", "field", "views"}, "Display")
    if value["kind"] != "expression-display-v1" or value["field"] != field or field not in step or step[field] is None:
        _fail("Display must identify an existing nonnull sibling subject field")
    if not isinstance(value["views"], list):
        _fail("Display views must be an array")
    step_path = tuple(step_path)
    if display_path is None:
        display_path = step_path + (field + "_display",)
    roots, hints, main_paths, links = [], [], set(), []
    for index, view in enumerate(value["views"]):
        _keys(view, {"root", "hints"}, "Display view")
        root = view["root"]
        if not isinstance(root, dict):
            _fail("Invalid Display root")
        if root.get("kind") == "field":
            _keys(root, {"kind", "path"}, "Display field root")
            if not isinstance(root["path"], list):
                _fail("Display field occurrence paths must be arrays")
            relative = _path(root["path"])
            if relative in main_paths:
                _fail("Duplicate Display main occurrence path")
            main_paths.add(relative)
            target = step_path + (field,) + relative
            resolver.require_root(target)
            reference = resolver.reference(json_path(step[field], relative))
        elif root.get("kind") == "auxiliary":
            _keys(root, {"kind", "expression"}, "Display auxiliary root")
            resolver.require_root(tuple(display_path) + ("views", index, "root", "expression"))
            reference = resolver.reference(root["expression"])
        else:
            _fail("Unknown Display root kind")
        roots.append(reference)
        if not isinstance(view["hints"], list):
            _fail("Display hints must be an array")
        view_hints, view_links = {}, set()
        for hint in view["hints"]:
            _keys(hint, {"path", "isProp", "declaration", "appBinders", "sourceRange"}, "Display hint")
            raw_path = hint["path"]
            if not isinstance(raw_path, list) or any(not isinstance(edge, str) for edge in raw_path):
                _fail("Display hint paths must be arrays of structural edges")
            hint_path = tuple(raw_path)
            if hint_path in view_hints:
                _fail("Duplicate Display hint occurrence path")
            current = resolver.node(reference)
            for edge in hint_path:
                current = current.child(edge)
            if hint["isProp"] is not None and type(hint["isProp"]) is not bool:
                _fail("Display isProp must be boolean or null")
            declaration = hint["declaration"]
            if declaration is not None:
                _keys(declaration, {"name", "typeView", "valueView"}, "Display declaration")
                if current["kind"] not in {"fvar", "mvar"} or not isinstance(declaration["name"], str):
                    _fail("Declaration hints require an fvar or mvar expression")
                if current["kind"] != "fvar" and declaration["valueView"] is not None:
                    _fail("Only fvar declarations may reference local values")
                for key in ("typeView", "valueView"):
                    target = declaration[key]
                    if target is not None:
                        if not _nat(target) or target >= len(value["views"]):
                            _fail("Display declaration view index is out of bounds")
                        candidate = value["views"][target]
                        if not isinstance(candidate, dict) or not isinstance(candidate.get("root"), dict) or candidate["root"].get("kind") != "auxiliary":
                            _fail("Display declaration references must target auxiliary views")
                        view_links.add(target)
            binders = hint["appBinders"]
            if binders is not None:
                if current["kind"] != "app" or not isinstance(binders, list) or any(
                        binder is not None and (not isinstance(binder, str) or binder not in BINDER_INFOS) for binder in binders):
                    _fail("Display appBinders requires an application and valid binder information")
                count, application = 0, current
                while application["kind"] == "app":
                    count += 1
                    application = application["fn"]
                if len(binders) != count:
                    _fail("Display appBinders length must match flattened application arguments")
            source = hint["sourceRange"]
            if source is not None:
                _keys(source, {"file", "start", "stop"}, "Display source range")
                if not isinstance(source["file"], str) or not _nat(source["start"]) or not _nat(source["stop"]) or source["start"] > source["stop"]:
                    _fail("Invalid Display source byte range")
            view_hints[hint_path] = hint
        hints.append(view_hints)
        links.append(view_links)
    active, checked = set(), set()
    def visit(index):
        if index in active:
            _fail("Cyclic Display auxiliary view references")
        if index in checked:
            return
        active.add(index)
        for target in links[index]:
            visit(target)
        active.remove(index)
        checked.add(index)
    for index in range(len(roots)):
        visit(index)
    return Display(resolver, value, roots, hints)


def validate_document(document):
    """Validate the 0.1 recording envelope and root ownership, returning its resolver."""
    if not isinstance(document, dict):
        _fail("Proof document must be an object")
    if document.get("schemaVersion") != PROOF_SCHEMA_VERSION:
        _fail(f"Unsupported recording schema version: {document.get('schemaVersion')!r}. {REBUILD_HINT}")
    base = {"schemaVersion", "module", "code"}
    graph = {"proof", "expressions", "expressionRoots"}
    if not base <= set(document) or set(document) - (base | graph):
        _fail("Invalid proof document fields")
    if not isinstance(document["module"], str) or not document["module"] or not isinstance(document["code"], str):
        _fail("Proof document requires a module and source code")
    present = set(document) & graph
    if not present:
        return None
    if present != graph:
        _fail("Proof, expressions and expressionRoots must appear together")
    from PS4HTML.recording import proof_steps
    try:
        proof_steps(document["proof"])
    except ValueError as error:
        _fail(str(error))
    resolver = ExpressionResolver(document["expressions"], document["expressionRoots"], document)
    def validate_records(steps):
        for record in steps:
            if "branches" not in record:
                continue
            branches = record["branches"]
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
    validate_records(document["proof"])
    for path in resolver.roots:
        if len(path) < 3 or path[0] != "proof" or not _nat(path[1]):
            _fail("Proof expression root paths must belong to proof record data")
        # Structural branch metadata and rule IDs are not expression data.
        remaining = path[2:]
        record = document["proof"][path[1]]
        while remaining:
            key = remaining[0]
            if key == "_ruleId":
                _fail("Expression roots cannot target proof protocol fields")
            if key == "branches":
                if len(remaining) < 5 or not _nat(remaining[1]) or remaining[2] != "proof" or not _nat(remaining[3]):
                    _fail("Expression roots cannot target branch metadata")
                record = record["branches"][remaining[1]]["proof"][remaining[3]]
                remaining = remaining[4:]
            else:
                break
    return resolver


def validate_computation_function(function):
    """Validate one computation's independent expression graph and Display owner."""
    if not isinstance(function, dict) or function.get("recordingVersion") != PROOF_SCHEMA_VERSION:
        version = function.get("recordingVersion") if isinstance(function, dict) else None
        _fail(f"Unsupported computation recording version: {version!r}. {REBUILD_HINT}")
    required = {"declaration", "type", "expression", "implementation", "expressions", "expressionRoots"}
    if not required <= set(function) or not isinstance(function["declaration"], str) or not isinstance(function["type"], str):
        _fail("Computation function is missing expression provenance")
    resolver = ExpressionResolver(function["expressions"], function["expressionRoots"], function)
    from PS4HTML.recording import display_schema, validate_fields
    fields = [{"name": field, "schema": {"kind": "expression"}, "nullable": False}
              for field in ("expression", "implementation")]
    for field in ("expression", "implementation"):
        companion = field + "_display"
        if companion in function:
            fields.append({"name": companion, "schema": {"kind": "optional", "element": display_schema(field)},
                           "nullable": True})
    validate_fields(function, fields, resolver=resolver, path=())
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
