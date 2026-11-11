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
            value = {"schemaVersion": target.VERSION, "complete": True,
                     "package": "Demo", "library": "Project", "module": ["Project", "测试"],
                     "files": []}
            source.write_text(json.dumps(value))
            module = target.publish(root, "Demo", "Project", "module", "Project.测试",
                                    ["Project.测试=Project/%E6%B5%8B%E8%AF%95"])
            source.write_text(json.dumps({**value, "exportFingerprint": "changed"}))
            library = target.publish(root, "Demo", "Project", "library", "Project",
                                     ["Project.测试=Project/%E6%B5%8B%E8%AF%95"])
            entry = json.loads(module.read_text())["modules"][0]
            self.assertEqual(entry["sha256"], hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(entry, json.loads(library.read_text())["modules"][0])

    def test_failed_module_preserves_previous_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "manifests/modules/Project/A.json"
            source.parent.mkdir(parents=True)
            source.write_text(json.dumps({
                "schemaVersion": target.VERSION, "complete": True,
                "package": "Demo", "library": "Project", "module": ["Project", "A"],
                "files": [],
            }))
            published = target.publish(root, "Demo", "Project", "library", "Project",
                                        ["Project.A=Project/A"])
            before = published.read_bytes()
            with self.assertRaises(FileNotFoundError):
                target.publish(root, "Demo", "Project", "library", "Project",
                                ["Project.A=Project/A", "Project.B=Project/B"])
            self.assertEqual(published.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
