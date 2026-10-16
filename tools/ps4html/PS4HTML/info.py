"""Read a completed Lean-owned bundle. Configuration events are diagnostic data only."""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from types import MappingProxyType

from jsonschema import Draft202012Validator, ValidationError

from PS4HTML.project import PS4HTMLError
from PS4HTML.recording import PROOF_SCHEMA_VERSION, proof_steps
from PS4HTML.render_rules import validate_record, validate_rules

INFO_VERSION = "4.0.0"
MANIFEST_VERSION = "4"
SNAPSHOT_VERSION = "3"
MODEL_VERSION = "1.0.0"


def canonical(value):
    if isinstance(value, dict):
        return "{" + ",".join(canonical(key) + ":" + canonical(value[key]) for key in sorted(value)) + "}"
    if isinstance(value, list):
        return "[" + ",".join(map(canonical, value)) + "]"
    if isinstance(value, Decimal):
        text = format(value, "f")
        return (text.rstrip("0").rstrip(".") if "." in text else text) if value else "0"
    if isinstance(value, float):
        return canonical(Decimal(str(value)))
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def name_key(parts):
    """Use the name's components directly as a hashable Python identity."""
    if not isinstance(parts, list) or not parts or any(
        not (isinstance(part, str) and part or type(part) is int and part >= 0) for part in parts
    ):
        raise ValueError("Invalid lossless Lean name")
    return tuple(parts)


def name_text(parts):
    return ".".join(str(part) if type(part) is int or re.fullmatch(r"[^\W\d][\w'!?]*", part) else f"«{part}»" for part in name_key(parts))


def proof_facts_digest(artifact):
    """Match Lean's binding of theorem facts to source content, identity and snapshot."""
    return digest({"schemaVersion": artifact["schemaVersion"], "artifactId": artifact["id"],
                   "snapshotId": artifact["snapshotId"], "contentDigest": artifact["contentDigest"],
                   "theorem": {key: artifact[key] for key in ("declaration", "projectId", "proofDependencies")}})


LeanName = tuple[str | int, ...]
TheoremKey = tuple[str, LeanName]


@dataclass(frozen=True)
class TheoremRecord:
    """Validated immutable proof facts; names and project IDs retain their lossless identities."""
    declaration: LeanName
    project_id: str
    proof_dependencies: tuple[LeanName, ...]
    artifact_id: str
    snapshot_id: str
    owner: LeanName
    path: str

    @property
    def key(self) -> TheoremKey:
        return self.project_id, self.declaration


class InfoBundle:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.documents = {}
        try:
            self.index = self.read("info/index.json")
            if self.index.get("schemaVersion") != INFO_VERSION or self.index.get("complete") is not True:
                raise ValueError("Unsupported or incomplete Info bundle; rebuild the cache with Lean")
            if self.index.get("recordingVersion") != PROOF_SCHEMA_VERSION or self.index.get("contractVersion") != "1":
                raise ValueError("Unsupported recording/contract version; rebuild the cache with Lean")
            schema = self.read("info/schema/bundle.schema.json")
            # Fail explicitly for old theorem caches, even when their bundled schema is permissive.
            for artifact in self.index.get("artifacts", []):
                if artifact.get("schemaVersion") != MANIFEST_VERSION:
                    raise ValueError("Unsupported artifact manifest version; rebuild the cache with Lean")
                if artifact.get("kind") == "proof" and artifact.get("declaration") is not None:
                    if any(key not in artifact for key in ("proofDependencies", "proofFactsDigest")):
                        raise ValueError("Named proof artifact lacks proofDependencies/proofFactsDigest; rebuild the cache with Lean")
            Draft202012Validator(schema).validate(self.index)
            listed = set()
            for entry in self.index["files"]:
                if entry["path"] in listed:
                    raise ValueError("Duplicate file in completion index")
                listed.add(entry["path"])
                actual = hashlib.sha256(self.file_path(entry["path"]).read_bytes()).hexdigest() if "sha256" in entry else digest(self.read(entry["path"]))
                if actual != entry.get("sha256", entry.get("digest")):
                    raise ValueError(f"Bundle content digest mismatch: {entry['path']}")
            required = {"info/schema/bundle.schema.json", "info/schema/snapshot.schema.json", "info/schema/models.json"}
            required.update(entry["events"] for entry in self.index["modules"])
            required.update(entry["path"] for entry in self.index["snapshots"])
            required.update(self.relative(entry["path"]) for entry in self.index["artifacts"])
            if not required <= listed:
                raise ValueError("Completion index omits referenced files")
            self.schemas = self.read("info/schema/models.json")
            self.modules = {entry["module"]: entry for entry in self.index["modules"]}
            if len(self.modules) != len(self.index["modules"]):
                raise ValueError("Duplicate module in Info bundle")
            self.snapshots = {}
            self._snapshot_records = {}
            for entry in self.index["snapshots"]:
                document = self.read(entry["path"])
                Draft202012Validator(self.read("info/schema/snapshot.schema.json")).validate(document)
                payload = document["payload"]
                if document.get("schemaVersion") != INFO_VERSION or digest(payload) != entry["id"] or document["id"] != entry["id"]:
                    raise ValueError("Snapshot identity/version mismatch")
                if payload.get("schemaVersion") != SNAPSHOT_VERSION or payload.get("recordingVersion") != PROOF_SCHEMA_VERSION or payload.get("contractVersion") != "1":
                    raise ValueError("Unsupported persisted snapshot version")
                records_by_identity = {}
                for record in payload["records"]:
                    kind, target = record["identity"]["kind"], record["identity"]["target"]
                    identity = (kind, target if kind == "project" else name_key(target))
                    if identity in records_by_identity or kind not in self.schemas or record["schemaVersion"] != MODEL_VERSION:
                        raise ValueError("Invalid/duplicate snapshot record schema")
                    if record["schemaId"] != self.schemas[kind]["title"]:
                        raise ValueError("Snapshot record schema identity mismatch")
                    records_by_identity[identity] = record
                    Draft202012Validator(self.schemas[kind]).validate(record["value"])
                contracts = {}
                for contract in payload["contracts"]:
                    value = contract["value"]
                    if value["contractVersion"] != "1" or value["recordingVersion"] != PROOF_SCHEMA_VERSION or digest(value) != contract["id"]:
                        raise ValueError("Unsupported or corrupt invocation contract")
                    if contract["id"] in contracts:
                        raise ValueError("Duplicate invocation contract")
                    contracts[contract["id"]] = value
                if entry["id"] in self.snapshots:
                    raise ValueError("Duplicate snapshot")
                self.snapshots[entry["id"]] = (payload, contracts)
                self._snapshot_records[entry["id"]] = records_by_identity
            for module, entry in self.modules.items():
                if name_text(entry["name"]) != module:
                    raise ValueError("Module name/identity mismatch")
                document = self.read(entry["events"])
                if document.get("schemaVersion") != INFO_VERSION or document.get("owner") != entry["name"] or document.get("module") != module:
                    raise ValueError("Module events version/owner mismatch")
                if entry["defaultSnapshot"] is not None and entry["defaultSnapshot"] not in self.snapshots:
                    raise ValueError("Unknown default snapshot")
            self.artifacts = {}
            self.by_path = {}
            theorems = {}
            theorems_by_artifact = {}
            declarations = set()
            for artifact in self.index["artifacts"]:
                if artifact["schemaVersion"] != MANIFEST_VERSION or artifact["snapshotId"] not in self.snapshots:
                    raise ValueError("Invalid artifact snapshot/version")
                if name_text(artifact["owner"]) != artifact["module"] or artifact["module"] not in self.modules:
                    raise ValueError("Artifact module/owner mismatch")
                if self.snapshots[artifact["snapshotId"]][0]["query"]["module"] != artifact["owner"]:
                    raise ValueError("Artifact snapshot belongs to another owner")
                if not artifact["path"].startswith(".ProofScript/"):
                    raise ValueError("Invalid logical artifact path")
                if ("publishedDigest" in artifact) != (artifact.get("transform") == "finalize-computations"):
                    raise ValueError("Incomplete artifact transformation metadata")
                expected = digest({"owner": artifact["owner"], "kind": artifact["kind"], "name": artifact["name"]})
                if artifact["id"] != expected or artifact["id"] in self.artifacts or artifact["path"] in self.by_path:
                    raise ValueError("Invalid/duplicate artifact identity")
                relative = self.relative(artifact["path"])
                if digest(self.read(relative)) != artifact.get("publishedDigest", artifact["contentDigest"]):
                    raise ValueError(f"Artifact content mismatch: {relative}")
                self.artifacts[artifact["id"]] = artifact
                self.by_path[relative] = artifact
                theorem = self._theorem_record(artifact)
                if theorem is not None:
                    if theorem.key in theorems or theorem.declaration in declarations:
                        raise ValueError("Duplicate/conflicting theorem export identity")
                    declarations.add(theorem.declaration)
                    theorems[theorem.key] = theorem
                    theorems_by_artifact[theorem.artifact_id] = theorem
            self.theorems = MappingProxyType(theorems)
            self.theorems_by_artifact = MappingProxyType(theorems_by_artifact)
            for artifact in self.artifacts.values():
                if artifact["kind"] == "proof":
                    self.proof_rules(artifact, validate=True)
        except (KeyError, TypeError, ValueError, OSError, ValidationError) as error:
            raise PS4HTMLError(f"Invalid Info bundle: {error}") from error

    def _theorem_record(self, artifact):
        declaration = artifact["declaration"]
        if artifact["kind"] != "proof" or declaration is None:
            if declaration is not None or any(key in artifact for key in ("proofDependencies", "proofFactsDigest")):
                raise ValueError("Only named proof artifacts may carry theorem proof facts")
            return None
        source = name_key(declaration)
        if source != name_key(artifact["name"]):
            raise ValueError("Theorem declaration/artifact name mismatch")
        project = artifact["projectId"]
        if not isinstance(project, str) or not project:
            raise ValueError("Theorem proof facts require a nonempty projectId")
        dependencies = artifact["proofDependencies"]
        if not isinstance(dependencies, list):
            raise ValueError("proofDependencies must be an array of lossless Lean names")
        dependencies = tuple(name_key(name) for name in dependencies)
        if source in dependencies or len(set(dependencies)) != len(dependencies):
            raise ValueError("Self/duplicate theorem proof dependency")
        if artifact["proofFactsDigest"] != proof_facts_digest(artifact):
            raise ValueError("Theorem proof facts digest mismatch")
        records = self._snapshot_records[artifact["snapshotId"]]
        metadata = records.get(("theorem", source))
        if metadata is None or metadata["configured"] is not True or metadata["value"]["project"] != project:
            raise ValueError("Theorem proof facts disagree with frozen project metadata")
        project_record = records.get(("project", project))
        if project_record is None or project_record["configured"] is not True:
            raise ValueError("Theorem proof facts reference an unconfigured project")
        return TheoremRecord(source, project, dependencies, artifact["id"], artifact["snapshotId"],
                             name_key(artifact["owner"]), artifact["path"])

    def file_path(self, relative):
        path = self.root / relative
        if Path(relative).is_absolute() or ".." in Path(relative).parts or not path.resolve().is_relative_to(self.root):
            raise ValueError("Invalid bundle path")
        return path

    def read(self, relative):
        if relative not in self.documents:
            path = self.file_path(relative)
            self.documents[relative] = json.loads(path.read_text(encoding="utf-8"), parse_float=Decimal)
        return self.documents[relative]

    @staticmethod
    def relative(path):
        return Path(path.removeprefix(".ProofScript/")).as_posix()

    def artifact(self, path):
        path = Path(path)
        if path.is_absolute():
            relative = path.resolve().relative_to(self.root).as_posix()
        else:
            relative = self.relative(path.as_posix())
        try:
            return self.by_path[relative]
        except KeyError as error:
            raise PS4HTMLError(f"Artifact absent from completed bundle: {relative}") from error

    def theorem(self, path):
        """Read the single facts record shared by page references and standalone proof artifacts."""
        artifact = self.artifact(path)
        try:
            return self.theorems_by_artifact[artifact["id"]]
        except KeyError as error:
            raise PS4HTMLError(f"Artifact is not a named theorem proof: {artifact['path']}") from error

    def snapshot(self, module=None, snapshot_id=None):
        if snapshot_id is None:
            entry = self.modules.get(module)
            snapshot_id = entry and entry["defaultSnapshot"]
        if snapshot_id not in self.snapshots:
            raise PS4HTMLError(f"No unambiguous consumed snapshot for {module}; select an artifact or snapshotId")
        return self.snapshots[snapshot_id][0]

    def configuration(self, module=None, snapshot_id=None):
        from Lean2TeX.configuration import interpret
        values = {}
        for record in self.snapshot(module, snapshot_id)["records"]:
            kind, target = record["identity"]["kind"], record["identity"]["target"]
            if kind not in {"definition", "variable", "phrase"}:
                continue
            fields = {key: value for key, value in record["value"].items() if key != "extra"}
            if kind == "definition":
                target = name_text(target)
                if fields.get("alias") is not None:
                    fields["alias"] = name_text(fields["alias"])
            else:
                # Literal variable/phrase keys occupy a single Name component.
                target = ".".join(map(str, target))
            values[(kind, target)] = fields
        return interpret(values)

    def projects(self, snapshot_id):
        return {record["identity"]["target"]: record["value"] for record in self.snapshot(snapshot_id=snapshot_id)["records"]
                if record["identity"]["kind"] == "project"}

    def proof_rules(self, artifact, validate=False):
        payload, contracts = self.snapshots[artifact["snapshotId"]]
        infos = {name_key(record["identity"]["target"]): record["value"] for record in payload["records"]
                 if record["identity"]["kind"] == "script"}
        rules = {}
        for binding in artifact["bindings"]:
            path = tuple(binding["path"])
            contract = contracts[binding["contractId"]]
            rule_id = name_text(contract["ruleId"])
            info = infos[name_key(contract["ruleId"])]
            templates = []
            for template in info["template"]:
                entry = dict(template["value"])
                if entry.get("introducer") is None:
                    entry.pop("introducer", None)
                if "cases" in entry:
                    entry["cases"] = [{key: value for key, value in case.items() if value is not None} for case in entry["cases"]]
                templates.append(entry)
            color = info["color"]
            fields = {"renderer": info["renderer"], "display": info["display"],
                      "color": [color[key] for key in ("tag", "border", "background")]}
            if templates:
                fields["template"] = templates
            rule = {"ruleId": rule_id, "strategy": contract["strategy"], "recordedFields": contract["fields"],
                    "fields": fields, "extra": info["extra"]}
            # Reuse the established contract, template and renderer checks at the adapter boundary.
            validate_rules({"schemaVersion": PROOF_SCHEMA_VERSION, "module": artifact["module"], "imports": [], "rules": [rule]}, artifact["module"])
            if path in rules:
                raise ValueError("Duplicate step binding")
            rules[path] = rule
        if validate:
            document = self.read(self.relative(artifact["path"]))
            if document.get("schemaVersion") != PROOF_SCHEMA_VERSION or document.get("module") != artifact["module"]:
                raise ValueError("Proof version/module differs from artifact")
            from PS4HTML.schema import ExpressionResolver
            ExpressionResolver(document.get("expressions", {})).resolve(document.get("proof", []))
            seen = set()

            def visit(steps, parent):
                for index, step in enumerate(proof_steps(steps)):
                    path = parent + (index,)
                    rule = rules.get(path)
                    if rule is None or rule["ruleId"] != step["_ruleId"]:
                        raise ValueError(f"Missing/mismatched contract at {path}")
                    validate_record(rule, step)
                    seen.add(path)
                    for branch_index, branch in enumerate(step.get("branches", [])):
                        visit(branch["proof"], path + ("branches", branch_index, "proof"))
                    embedded = step.get("proof")
                    if isinstance(embedded, list) and any(isinstance(child, dict) and "_ruleId" in child for child in embedded):
                        visit(embedded, path + ("proof",))

            if "proof" in document:
                visit(document["proof"], ("proof",))
            if seen != set(rules):
                raise ValueError("Orphan invocation contract bindings")
        return rules
