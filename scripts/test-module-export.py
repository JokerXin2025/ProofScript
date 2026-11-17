"""Exercise module publication and failure isolation without requiring a Wasm toolchain."""

import importlib.util
import json
import multiprocessing
import os
import shutil
import threading
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "proofscript" / "module_export.py"
SPEC = importlib.util.spec_from_file_location("proofscript_module_export", SCRIPT)
export = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export)


class ModuleExportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        self.root = self.workspace / ".ProofScript"
        self.source = self.workspace / "source"
        self.source.mkdir()
        self.descriptor = self.workspace / "descriptor.json"
        self.build = self.workspace / "build.json"
        self.build.write_text("{}")

    def publish(self, files, figures=(), *, module=("Project", "A")):
        files = list(files)
        if files and not any(path.startswith("info/") for path, _ in files):
            files.append(("info/Project/A.json", {
                "module": list(module), "records": []}))
        files = [(path, dict({"module": list(module),
                             "info": ".ProofScript/info/Project/A.json",
                             "components": [{"data": {"title": {"value": "test"}}}]}, **contents))
                 if path.startswith("pages/") else
                  (path, dict({"module": list(module)}, **contents))
                 if path.startswith("info/") else (path, contents)
                 for path, contents in files]
        value = {
            "module": list(module),
            "package": "Project", "library": "Project", "hasComponents": bool(files),
            "resourceModule": "Project/A",
            "manifest": "manifests/modules/Project/A.json",
            "files": [{"path": path, "json": contents} for path, contents in files],
            "figures": list(figures),
        }
        self.descriptor.write_text(json.dumps(value))
        export.publish(self.descriptor, self.root, self.source, SCRIPT.parents[2], self.build)

    def test_success_replaces_and_cleans_only_owned_files(self):
        self.publish([("pages/Project/A.json", {"title": "old"}),
                      ("info/Project/A.json", {"name": "old", "records": []})])
        unrelated = self.root / "pages/Project/B.json"
        unrelated.write_text("other")
        self.publish([("pages/Project/A.json", {"title": "new"})])
        self.assertEqual(json.loads((self.root / "pages/Project/A.json").read_text())["title"], "new")
        self.assertEqual(json.loads((self.root / "info/Project/A.json").read_text())["records"], [])
        self.assertEqual(unrelated.read_text(), "other")
        manifest = json.loads((self.root / "manifests/modules/Project/A.json").read_text())
        self.assertEqual([entry["path"] for entry in manifest["files"]],
                         ["info/Project/A.json", "pages/Project/A.json"])

    def test_replaces_previous_module_manifest_and_cleans_obsolete_files(self):
        self.publish([("pages/Project/A.json", {"title": "old"}),
                       ("resources/Project/A/generated/obsolete.txt", "old")])
        manifest_path = self.root / "manifests/modules/Project/A.json"
        old = json.loads(manifest_path.read_text())
        self.publish([("pages/Project/A.json", {"title": "new"})])
        self.assertNotEqual(json.loads(manifest_path.read_text()), old)
        self.assertFalse((self.root / "resources/Project/A/generated/obsolete.txt").exists())
        self.assertEqual(json.loads((self.root / "pages/Project/A.json").read_text())["title"], "new")

    def test_missing_image_keeps_previous_module(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        manifest = (self.root / "manifests/modules/Project/A.json").read_bytes()
        with self.assertRaises(FileNotFoundError):
            self.publish([("pages/Project/A.json", {"title": "new"})],
                         [{"source": "missing.png", "path": "resources/Project/A/images/image.png"}])
        self.assertEqual((self.root / "manifests/modules/Project/A.json").read_bytes(), manifest)
        self.assertEqual(json.loads((self.root / "pages/Project/A.json").read_text())["title"], "old")

    def test_accepts_declaration_record_without_version(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        completion = self.root / "manifests/modules/Project/A.json"
        record = {"identity": {"kind": "decl", "target": ["Project", "value"]},
                   "value": {}}
        self.publish([("pages/Project/A.json", {"title": "new"}),
                      ("info/Project/A.json", {"records": [record]})])
        self.assertEqual(json.loads((self.root / "info/Project/A.json").read_text())["records"], [record])

    def test_image_is_copied_and_sealed(self):
        image = self.source / "image.png"
        image.write_bytes(b"png-content")
        page = {"components": [{"data": {"figure": {
            "value": {"path": ".ProofScript/resources/Project/A/images/image.png"}}}}]}
        self.publish([("pages/Project/A.json", page)],
                     [{"source": "image.png", "path": "resources/Project/A/images/image.png"}])
        self.assertEqual((self.root / "resources/Project/A/images/image.png").read_bytes(), b"png-content")
        figure = json.loads((self.root / "pages/Project/A.json").read_text())["components"][0]
        resource = figure["data"]["figure"]["value"]["resource"]["$resource"]
        self.assertEqual(resource["byteSize"], len(b"png-content"))

    def test_failure_during_publication_rolls_back(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        manifest = (self.root / "manifests/modules/Project/A.json").read_bytes()
        write = export._write

        def fail_manifest(path, value):
            if path.name == "A.json" and path.parent.name == "Project" and "manifests" in path.parts:
                raise OSError("injected publication failure")
            return write(path, value)

        with patch.object(export, "_write", side_effect=fail_manifest):
            with self.assertRaisesRegex(OSError, "injected publication failure"):
                self.publish([("pages/Project/A.json", {"title": "new"})])
        self.assertEqual((self.root / "manifests/modules/Project/A.json").read_bytes(), manifest)
        self.assertEqual(json.loads((self.root / "pages/Project/A.json").read_text())["title"], "old")

    def test_rejects_path_escape_and_other_module_ownership(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        with self.assertRaisesRegex(ValueError, "unsafe"):
            self.publish([("../outside.json", {})])
        with self.assertRaisesRegex(ValueError, "ownership conflict"):
            self.publish([("pages/Project/A.json", {})], module=("Other", "A"))

    def test_rejects_case_insensitive_file_collisions(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        with self.assertRaisesRegex(ValueError, "case-insensitive"):
            self.publish([("pages/Project/A.json", {}),
                          ("resources/Project/A/generated/foo.svg", "svg"),
                          ("resources/Project/A/generated/Foo.svg", "svg")])

    def test_configuration_only_module_cleans_previous_page(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        self.publish([])
        self.assertFalse((self.root / "pages/Project/A.json").exists())
        self.assertFalse((self.root / "info/Project/A.json").exists())
        manifest = json.loads((self.root / "manifests/modules/Project/A.json").read_text())
        self.assertFalse(manifest["hasComponents"])
        self.assertEqual(manifest["files"], [])

    def test_missing_resource_and_invalid_info_keep_last_successful_export(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        old_manifest = (self.root / "manifests/modules/Project/A.json").read_bytes()
        broken_resource = {"$resource": {
            "path": ".ProofScript/resources/Project/A/missing.svg",
            "hash": "0" * 64, "encoding": "utf-8"}}
        with self.assertRaisesRegex((ValueError, FileNotFoundError), "missing.svg"):
            self.publish([("pages/Project/A.json", {"components": [
                {"data": {"latex": {"value": {"svg": broken_resource}}}}
            ]})])
        with self.assertRaisesRegex(ValueError, "duplicate frozen Info identity"):
            self.publish([("pages/Project/A.json", {"title": "new"}),
                          ("info/Project/A.json", {"records": [
                               {"identity": {"kind": "decl", "target": ["Project", "A"]}},
                               {"identity": {"kind": "decl", "target": ["Project", "A"]}},
                          ]})])
        self.assertEqual((self.root / "manifests/modules/Project/A.json").read_bytes(), old_manifest)

    def test_rejects_project_info_in_new_protocol(self):
        with self.assertRaisesRegex(ValueError, "unsupported frozen Info identity"):
            self.publish([("pages/Project/A.json", {}),
                          ("info/Project/A.json", {"records": [
                              {"identity": {"kind": "project", "target": "Project"}}
                          ]})])

    def test_failure_in_computation_build_preserves_old_module(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        before = (self.root / "manifests/modules/Project/A.json").read_bytes()
        with patch.object(export, "_build_computations", side_effect=RuntimeError("wasm build failed")):
            with self.assertRaisesRegex(RuntimeError, "wasm build failed"):
                self.publish([("pages/Project/A.json", {"title": "new"})])
        self.assertEqual((self.root / "manifests/modules/Project/A.json").read_bytes(), before)
        self.assertEqual(json.loads((self.root / "pages/Project/A.json").read_text())["title"], "old")

    def test_concurrent_module_publication_keeps_both_manifests(self):
        self.publish([("pages/Project/A.json", {"title": "A"})])
        errors = []

        def publish_other(name):
            try:
                with tempfile.TemporaryDirectory(dir=self.workspace) as directory:
                    descriptor = Path(directory) / "descriptor.json"
                    descriptor.write_text(json.dumps({
                        "module": ["Project", name],
                        "package": "Project", "library": "Project", "hasComponents": True,
                        "resourceModule": f"Project/{name}",
                        "manifest": f"manifests/modules/Project/{name}.json",
                        "files": [
                            {"path": f"pages/Project/{name}.json", "json": {
                                "module": ["Project", name],
                                "info": f".ProofScript/info/Project/{name}.json",
                                "components": [{"data": {"title": {"value": name}}}]}},
                            {"path": f"info/Project/{name}.json", "json": {
                                "module": ["Project", name],
                                "records": []}},
                        ], "figures": [],
                    }))
                    export.publish(descriptor, self.root, self.source, SCRIPT.parents[2], self.build)
            except Exception as error:
                errors.append(error)

        workers = [threading.Thread(target=publish_other, args=(name,)) for name in ("B", "C")]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join()
        self.assertFalse(errors, errors)
        for name in ("A", "B", "C"):
            self.assertTrue((self.root / f"manifests/modules/Project/{name}.json").is_file())

    def test_interrupted_publication_recovers_before_next_module(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        old_manifest = (self.root / "manifests/modules/Project/A.json").read_bytes()
        journal = self.root / "staging/transactions/interrupted"
        original = self.root / "pages/Project/A.json"
        saved = journal / "backup/pages/Project/A.json"
        saved.parent.mkdir(parents=True)
        saved.write_bytes(original.read_bytes())
        (journal / "backup/manifests/modules/Project").mkdir(parents=True)
        (journal / "backup/manifests/modules/Project/A.json").write_bytes(old_manifest)
        (journal / "journal.json").write_text(json.dumps({
            "state": "prepared",
            "touched": ["pages/Project/A.json", "manifests/modules/Project/A.json",
                        "resources/Project/A/generated/new.svg"],
            "existing": ["pages/Project/A.json", "manifests/modules/Project/A.json"],
        }))
        original.write_text("corrupted new page")
        extra = self.root / "resources/Project/A/generated/new.svg"
        extra.parent.mkdir(parents=True)
        extra.write_text("unfinished")
        with export._lock(self.root):
            export._recover(self.root)
        self.assertEqual(json.loads(original.read_text())["title"], "old")
        self.assertEqual((self.root / "manifests/modules/Project/A.json").read_bytes(), old_manifest)
        self.assertFalse(extra.exists())
        self.assertFalse(journal.exists())

    def test_process_termination_mid_publication_recovers_on_next_export(self):
        self.publish([("pages/Project/A.json", {"title": "old"}),
                      ("resources/Project/A/generated/old.svg", {"svg": "old"})])
        original = (self.root / "manifests/modules/Project/A.json").read_bytes()
        self.descriptor.write_text(json.dumps({
            "module": ["Project", "A"],
            "package": "Project", "library": "Project", "hasComponents": True,
            "resourceModule": "Project/A", "manifest": "manifests/modules/Project/A.json",
            "files": [
                {"path": "info/Project/A.json", "json": {
                    "module": ["Project", "A"], "records": []}},
                {"path": "pages/Project/A.json", "json": {
                    "module": ["Project", "A"],
                    "info": ".ProofScript/info/Project/A.json", "components": [{}], "title": "new"}},
            ], "figures": [],
        }))

        def terminate():
            copy = shutil.copyfile

            def crash(source, destination, *args, **kwargs):
                result = copy(source, destination, *args, **kwargs)
                if destination == self.root / "pages/Project/A.json":
                    os._exit(42)
                return result

            with patch.object(export.shutil, "copyfile", side_effect=crash):
                export.publish(self.descriptor, self.root, self.source, SCRIPT.parents[2], self.build)

        child = multiprocessing.get_context("fork").Process(target=terminate)
        child.start()
        child.join(10)
        self.assertEqual(child.exitcode, 42)
        with export._lock(self.root):
            export._recover(self.root)
        self.assertEqual((self.root / "manifests/modules/Project/A.json").read_bytes(), original)
        self.assertEqual(json.loads((self.root / "pages/Project/A.json").read_text())["title"], "old")
        self.assertTrue((self.root / "resources/Project/A/generated/old.svg").exists())
        self.publish([("pages/Project/A.json", {"title": "final"})])
        self.assertEqual(json.loads((self.root / "pages/Project/A.json").read_text())["title"], "final")

    def test_corrupt_backup_aborts_recovery_without_erasing_public_data(self):
        self.publish([("pages/Project/A.json", {"title": "old"})])
        original = (self.root / "pages/Project/A.json").read_bytes()
        journal = self.root / "staging/transactions/corrupt"
        journal.mkdir(parents=True)
        (journal / "journal.json").write_text(json.dumps({
            "state": "prepared",
            "touched": ["pages/Project/A.json"], "existing": ["pages/Project/A.json"],
        }))
        with export._lock(self.root):
            with self.assertRaisesRegex(ValueError, "missing publication backup"):
                export._recover(self.root)
        self.assertEqual((self.root / "pages/Project/A.json").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
