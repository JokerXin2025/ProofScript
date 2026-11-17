"""Target inventories are published only after every selected module is complete."""

import importlib.util
import hashlib
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools/proofscript/target_manifest.py"
SPEC = importlib.util.spec_from_file_location("target_manifest", SCRIPT)
target = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(target)


class TargetManifestTests(unittest.TestCase):
    def test_encoded_module_path_and_refresh_of_other_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "manifests/modules/Project/%E6%B5%8B%E8%AF%95.json"
            source.parent.mkdir(parents=True)
            value = {"complete": True,
                     "package": "Demo", "library": "Project", "module": ["Project", "测试"],
                     "files": []}
            source.write_text(json.dumps(value))
            module = target.publish(root, "Demo", "Project", "module", "Project.测试",
                                    ["Project.测试=Project/%E6%B5%8B%E8%AF%95"])
            source.write_text(json.dumps({**value, "exportFingerprint": "changed"}))
            info = root / "snapshot.json"
            info.write_text('{"records": []}')
            library = target.publish(root, "Demo", "Project", "library", "Project",
                                     ["Project.测试=Project/%E6%B5%8B%E8%AF%95"], info)
            entry = json.loads(module.read_text())["modules"][0]
            self.assertEqual(entry["sha256"], hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(entry, json.loads(library.read_text())["modules"][0])
            self.assertEqual(json.loads((root / "info/Project.json").read_text())["records"], [])
            self.assertEqual(json.loads(library.read_text())["info"], {
                "path": "info/Project.json",
                "sha256": hashlib.sha256((root / "info/Project.json").read_bytes()).hexdigest(),
            })

    def test_failed_module_preserves_previous_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "manifests/modules/Project/A.json"
            source.parent.mkdir(parents=True)
            source.write_text(json.dumps({
                "complete": True,
                "package": "Demo", "library": "Project", "module": ["Project", "A"],
                "files": [],
            }))
            info = root / "snapshot.json"
            info.write_text('{"records": []}')
            published = target.publish(root, "Demo", "Project", "library", "Project",
                                        ["Project.A=Project/A"], info)
            before = published.read_bytes()
            with self.assertRaises(FileNotFoundError):
                target.publish(root, "Demo", "Project", "library", "Project",
                               ["Project.A=Project/A", "Project.B=Project/B"], info)
            self.assertEqual(published.read_bytes(), before)

    def test_invalid_snapshot_does_not_replace_completed_library(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = root / "manifests/modules/Project/A.json"
            module.parent.mkdir(parents=True)
            module.write_text(json.dumps({"complete": True, "package": "Demo", "library": "Project",
                                          "module": ["Project", "A"], "files": []}))
            info = root / "snapshot.json"
            info.write_text('{"records": []}')
            published = target.publish(root, "Demo", "Project", "library", "Project",
                                       ["Project.A=Project/A"], info)
            before = published.read_bytes()
            snapshot = (root / "info/Project.json").read_bytes()
            info.write_text('{"records": "invalid"}')
            with self.assertRaises(ValueError):
                target.publish(root, "Demo", "Project", "library", "Project",
                               ["Project.A=Project/A"], info)
            self.assertEqual(published.read_bytes(), before)
            self.assertEqual((root / "info/Project.json").read_bytes(), snapshot)

    def test_ownership_collision_rejects_library_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = root / "manifests/modules/Project/A.json"
            module.parent.mkdir(parents=True)
            module.write_text(json.dumps({"complete": True, "package": "Demo", "library": "Project",
                                          "module": ["Project", "A"], "files": []}))
            info = root / "snapshot.json"
            info.write_text('{"records": []}')
            destination = root / "info/Project.json"
            destination.parent.mkdir()
            destination.write_text('{"library": {"package": "Other", "library": "Project"}}')
            with self.assertRaisesRegex(ValueError, "owned by another project"):
                target.publish(root, "Demo", "Project", "library", "Project",
                               ["Project.A=Project/A"], info)


if __name__ == "__main__":
    unittest.main()
