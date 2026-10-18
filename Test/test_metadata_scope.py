"""Cross-document checks for content-specific metadata snapshots.

Run with PYTHONPATH=tools/ps4html python3 -m unittest Test/test_metadata_scope.py.
"""

import json
from pathlib import Path
import tempfile
import unittest

from PS4HTML.info import (
    INFO_VERSION, MANIFEST_VERSION, SNAPSHOT_VERSION, InfoBundle, digest, proof_facts_digest,
)
from PS4HTML.page import Page
from PS4HTML.project import PS4HTMLError
from PS4HTML.recording import PROOF_SCHEMA_VERSION
from PS4HTML.theorem_graph import TheoremGraph


class MetadataBundleFixture:
    """Small complete bundle; schemas leave cross-document invariants to InfoBundle."""

    owner = ["Demo", "Page"]
    module = "Demo.Page"

    def __init__(self, root):
        self.root = Path(root)
        self.documents = {
            "info/schema/bundle.schema.json": {"type": "object"},
            "info/schema/snapshot.schema.json": {"type": "object"},
            "info/schema/models.json": {
                "project": {"title": "ProjectInfo", "type": "object"},
                "theorem": {"title": "TheoremInfo", "type": "object"},
                "variable": {"title": "VariableInfo", "type": "object"},
            },
            "info/modules/demo.json": {
                "schemaVersion": INFO_VERSION, "owner": self.owner, "module": self.module,
                "events": [], "registrations": [],
            },
        }
        self.index = {
            "schemaVersion": INFO_VERSION, "recordingVersion": PROOF_SCHEMA_VERSION,
            "contractVersion": "1", "complete": True,
            "modules": [{"name": self.owner, "module": self.module,
                         "events": "info/modules/demo.json", "defaultSnapshot": None}],
            "artifacts": [], "snapshots": [], "files": [],
        }
        self.envelope_snapshot = self.snapshot(1)
        self.proofs = [self.proof("first", "First title", 1),
                       self.proof("second", "Second title", 2)]
        self.component_snapshot = self.snapshot(3)
        self.page_path = "pages/Demo/Page.json"
        self.page = {
            "module": self.module, "source": "Demo/Page.lean",
            "components": [
                {"source": {"file": "Demo/Page.lean", "start": 10, "stop": 20},
                 "snapshotId": proof["snapshotId"],
                 "data": {"theorem": {"value": {
                     "name": title, "proof": proof["path"], "sorryAx": False}}}}
                for proof, title in zip(self.proofs, ("First title", "Second title"))
            ] + [{"source": {"file": "Demo/Page.lean", "start": 30, "stop": 40},
                  "snapshotId": self.component_snapshot,
                  "data": {"text": {"value": {"source": "later text", "blocks": []}}}}],
        }
        self.documents[self.page_path] = self.page
        self.page_artifact = self.artifact("page", self.owner, self.page_path,
                                           self.envelope_snapshot)

    def snapshot(self, boundary, theorem=None, *, owner=None):
        records = [{"identity": {"kind": "project", "target": "P"},
                    "schemaId": "ProjectInfo", "schemaVersion": "1.0.0", "configured": True,
                    "value": {"title": "Project P"}}]
        if theorem is not None:
            name, title = theorem
            records.append({"identity": {"kind": "theorem", "target": name},
                            "schemaId": "TheoremInfo", "schemaVersion": "1.0.0",
                            "configured": True, "value": {"name": title, "project": "P"}})
            variable = "x" if name[-1] == "first" else "y"
            records.append({"identity": {"kind": "variable", "target": ["Nat"]},
                            "schemaId": "VariableInfo", "schemaVersion": "1.0.0",
                            "configured": True,
                            "value": {"default": variable, "names": [variable], "extra": {}}})
        payload = {"schemaVersion": SNAPSHOT_VERSION, "recordingVersion": PROOF_SCHEMA_VERSION,
                   "contractVersion": "1", "query": {"module": owner or self.owner,
                   "boundary": {"before": {"sequence": boundary}}}, "records": records, "contracts": []}
        identity = digest(payload)
        path = f"info/snapshots/{identity}.json"
        self.index["snapshots"].append({"id": identity, "path": path})
        self.documents[path] = {"schemaVersion": INFO_VERSION, "id": identity,
                                "payload": payload, "provenance": []}
        return identity

    def artifact(self, kind, name, path, snapshot, declaration=None):
        artifact = {"schemaVersion": MANIFEST_VERSION,
                    "id": digest({"owner": self.owner, "kind": kind, "name": name}),
                    "owner": self.owner, "module": self.module, "kind": kind, "name": name,
                    "path": ".ProofScript/" + path, "snapshotId": snapshot,
                    "declaration": declaration, "projectId": "P",
                    "contentDigest": digest(self.documents[path]), "dependencies": [], "bindings": []}
        if declaration is not None:
            artifact["proofDependencies"] = []
            artifact["proofFactsDigest"] = proof_facts_digest(artifact)
        self.index["artifacts"].append(artifact)
        return artifact

    def proof(self, name, title, boundary):
        declaration = self.owner + [name]
        snapshot = self.snapshot(boundary, (declaration, title))
        path = f"proofs/Demo/Page/{name}.json"
        self.documents[path] = {"schemaVersion": PROOF_SCHEMA_VERSION, "module": self.module,
                                "code": f"@theorem {name} : True := by trivial"}
        return self.artifact("proof", declaration, path, snapshot, declaration)

    def write(self):
        # Keep all ordinary content digests correct: rejection must concern semantics.
        for artifact in self.index["artifacts"]:
            artifact["contentDigest"] = digest(self.documents[InfoBundle.relative(artifact["path"])])
            if artifact["declaration"] is not None:
                artifact["proofFactsDigest"] = proof_facts_digest(artifact)
        self.index["files"] = [{"path": path, "digest": digest(document)}
                               for path, document in self.documents.items()]
        for path, document in {**self.documents, "info/index.json": self.index}.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")


class MetadataScopeTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.fixture = MetadataBundleFixture(self.directory.name)

    def bundle(self):
        self.fixture.write()
        return InfoBundle(self.directory.name)

    def test_one_page_accepts_distinct_proof_and_component_snapshots(self):
        bundle = self.bundle()
        page = Page(Path(self.directory.name) / self.fixture.page_path,
                    self.fixture.module, Path("Demo/Page.lean"), self.fixture.page["components"])
        graph = TheoremGraph.from_bundle(bundle, [page])
        self.assertEqual([destination.title for destination in graph.destinations.values()],
                         ["First title", "Second title"])
        self.assertEqual(len({record.snapshot_id for record in bundle.theorems.values()}), 2)
        self.assertNotIn(self.fixture.envelope_snapshot,
                         {record.snapshot_id for record in bundle.theorems.values()})
        self.assertIn(self.fixture.component_snapshot, bundle.snapshots)
        self.assertEqual([bundle.configuration(snapshot_id=proof["snapshotId"]).variables[0].var_names
                          for proof in self.fixture.proofs], [["x"], ["y"]])

    def test_proof_component_cannot_use_page_envelope_snapshot(self):
        self.fixture.page["components"][0]["snapshotId"] = self.fixture.envelope_snapshot
        with self.assertRaisesRegex(PS4HTMLError, "proof owner/snapshot"):
            self.bundle()

    def test_proof_component_cannot_use_another_proofs_snapshot(self):
        self.fixture.page["components"][0]["snapshotId"] = self.fixture.proofs[1]["snapshotId"]
        with self.assertRaisesRegex(PS4HTMLError, "proof owner/snapshot"):
            self.bundle()

    def test_every_component_requires_a_snapshot(self):
        del self.fixture.page["components"][-1]["snapshotId"]
        with self.assertRaisesRegex(PS4HTMLError, "lacks its configuration snapshot"):
            self.bundle()

    def test_component_cannot_use_unknown_snapshot(self):
        self.fixture.page["components"][-1]["snapshotId"] = "0" * 64
        with self.assertRaisesRegex(PS4HTMLError, "unknown or belongs to another owner"):
            self.bundle()

    def test_component_cannot_use_another_modules_snapshot(self):
        self.fixture.page["components"][-1]["snapshotId"] = self.fixture.snapshot(1, owner=["Other"])
        with self.assertRaisesRegex(PS4HTMLError, "unknown or belongs to another owner"):
            self.bundle()

    def test_title_must_match_the_proofs_frozen_metadata(self):
        self.fixture.page["components"][0]["data"]["theorem"]["value"]["name"] = "Later title"
        with self.assertRaisesRegex(PS4HTMLError, "title disagrees with its frozen metadata"):
            self.bundle()

    def test_page_envelope_cannot_use_a_later_configuration_boundary(self):
        self.fixture.page_artifact["snapshotId"] = self.fixture.component_snapshot
        with self.assertRaisesRegex(PS4HTMLError, "first component's configuration boundary"):
            self.bundle()

    def test_page_project_must_exist_in_its_envelope_snapshot(self):
        self.fixture.page_artifact["projectId"] = "Later project"
        with self.assertRaisesRegex(PS4HTMLError, "Page project disagrees"):
            self.bundle()

    def test_old_bundle_is_rejected(self):
        self.fixture.index["schemaVersion"] = "4.0.0"
        with self.assertRaisesRegex(PS4HTMLError, "Unsupported or incomplete Info bundle"):
            self.bundle()

    def test_old_manifest_is_rejected(self):
        self.fixture.proofs[0]["schemaVersion"] = "4"
        with self.assertRaisesRegex(PS4HTMLError, "Unsupported artifact manifest"):
            self.bundle()

    def test_old_snapshot_is_rejected_even_with_updated_digests(self):
        entry = self.fixture.index["snapshots"][0]
        document = self.fixture.documents.pop(entry["path"])
        document["payload"]["schemaVersion"] = "3"
        identity = digest(document["payload"])
        document["id"] = identity
        entry.update(id=identity, path=f"info/snapshots/{identity}.json")
        self.fixture.documents[entry["path"]] = document
        self.fixture.page_artifact["snapshotId"] = identity
        with self.assertRaisesRegex(PS4HTMLError, "Unsupported persisted snapshot version"):
            self.bundle()

    def test_snapshot_requires_a_concrete_nonnegative_integer_boundary(self):
        for boundary in (None, "endOfModule", {"endOfModule": {}}, {"before": 1},
                         {"before": {"sequence": True}}, {"before": {"sequence": -1}},
                         {"before": {"sequence": 1.5}}, {"before": {}},
                         {"before": {"sequence": 1}, "endOfModule": {}}):
            with self.subTest(boundary=boundary):
                fixture = MetadataBundleFixture(self.directory.name)
                entry = fixture.index["snapshots"][0]
                document = fixture.documents.pop(entry["path"])
                document["payload"]["query"]["boundary"] = boundary
                identity = digest(document["payload"])
                document["id"] = identity
                entry.update(id=identity, path=f"info/snapshots/{identity}.json")
                fixture.documents[entry["path"]] = document
                fixture.page_artifact["snapshotId"] = identity
                fixture.write()
                with self.assertRaisesRegex(PS4HTMLError, "concrete nonnegative content boundary"):
                    InfoBundle(self.directory.name)


if __name__ == "__main__":
    unittest.main()
