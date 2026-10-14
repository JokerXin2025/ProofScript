from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from PS4HTML.project import PS4HTMLError
from PS4HTML.recording import PROOF_SCHEMA_VERSION, SUPPORTED_RECORDING_VERSIONS


EXPRESSION_ID = re.compile(r"^e[0-9]+$")
PROOF_MEDIA_TYPE = "application/vnd.proofscript.proof+json"
SCHEMA_VERSION = "0.0.0"


class ExpressionResolver:
    """Validate and lazily resolve one proof document's expression DAG."""

    def __init__(self, expressions: dict):
        if not isinstance(expressions, dict):
            raise PS4HTMLError("Proof expressions must be an object")
        self.expressions = expressions
        self.cache = {}
        self._validate()

    def _validate(self):
        for reference, node in self.expressions.items():
            if not isinstance(reference, str) or not EXPRESSION_ID.fullmatch(reference):
                raise PS4HTMLError(f"Invalid proof expression ID: {reference}")
            if not isinstance(node, dict) or set(node) == {"$ref"}:
                raise PS4HTMLError(f"Proof expression {reference} is not a complete node")
            if not isinstance(node.get("kind"), str) or not isinstance(node.get("isProp"), bool):
                raise PS4HTMLError(f"Proof expression {reference} is missing kind or isProp")
        checked = set()
        for reference in self.expressions:
            self._check_references(
                self.expressions[reference], frozenset({reference}), checked
            )

    def _check_references(self, value, active, checked):
        if isinstance(value, list):
            for child in value:
                self._check_references(child, active, checked)
            return
        if not isinstance(value, dict):
            return
        if set(value) == {"$ref"}:
            reference = value["$ref"]
            if not isinstance(reference, str) or reference not in self.expressions:
                raise PS4HTMLError(f"Unknown proof expression reference: {reference}")
            if reference in active:
                raise PS4HTMLError(f"Cyclic proof expression reference: {reference}")
            if reference not in checked:
                self._check_references(
                    self.expressions[reference], active | {reference}, checked
                )
                checked.add(reference)
            return
        for child in value.values():
            self._check_references(child, active, checked)

    def resolve(self, value, active=frozenset()):
        if isinstance(value, list):
            return [self.resolve(child, active) for child in value]
        if not isinstance(value, dict):
            return value
        if set(value) == {"$ref"}:
            reference = value["$ref"]
            if not isinstance(reference, str) or reference not in self.expressions:
                raise PS4HTMLError(f"Unknown proof expression reference: {reference}")
            if reference in active:
                raise PS4HTMLError(f"Cyclic proof expression reference: {reference}")
            if reference not in self.cache:
                self.cache[reference] = self.resolve(
                    self.expressions[reference], active | {reference}
                )
            return self.cache[reference]
        return {key: self.resolve(child, active) for key, child in value.items()}


def resolve_expressions(value, expressions: dict):
    """Compatibility helper for callers that need one resolved expression value."""
    return ExpressionResolver(expressions).resolve(value)


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
        if not isinstance(document, dict):
            raise PS4HTMLError(f"Embedded proof JSON must be an object: {path}")
        version = document.get("schemaVersion")
        if version not in SUPPORTED_RECORDING_VERSIONS:
            raise PS4HTMLError(f"Unsupported embedded proof schema version: {version}")
        proof = document.get("proof")
        expressions = document.get("expressions", {})
        code = document.get("code")
        if not isinstance(code, str) or (proof is not None and not isinstance(proof, list)):
            raise PS4HTMLError(f"Embedded proof is missing code or has invalid proof records: {path}")
        resolver = ExpressionResolver(expressions) if proof is not None else None
        loaded = LoadedProof(path, version, code, proof, expressions, resolver)
        self.proof_cache[key] = loaded
        return loaded


def read_text_resource(value, project_root: Path, media_type: str | None = None) -> str:
    return ResourceLoader(project_root).read_text(value, media_type)
