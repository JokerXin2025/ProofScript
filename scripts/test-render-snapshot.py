"""A renderer cannot observe a partially replaced module publication."""

import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/ps4html"))
sys.path.insert(0, str(ROOT / "tools/proofscript"))

from PS4HTML.module_protocol import snapshot_target
from PS4HTML.project import PS4HTMLError
import module_export
import target_manifest


class RenderSnapshotTests(unittest.TestCase):
    def test_publish_and_snapshot_use_same_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            root = workspace / ".ProofScript"
            source = workspace / "source"
            relative = "pages/Test/Page.json"
            manifest = "manifests/modules/Test/Page.json"

            def publish(content):
                source.mkdir(exist_ok=True)
                page = source / relative
                page.parent.mkdir(parents=True, exist_ok=True)
                page.write_text(content)
                info = source / "info/Test/Page.json"
                info.parent.mkdir(parents=True, exist_ok=True)
                info.write_text("{}")
                module_export._publish(root, source, ["Test", "Page"], "Pkg", "Test",
                                       manifest, True)

            publish("old")
            target = target_manifest.publish(root, "Pkg", "Test", "module",
                                              "Test.Page", ["Test.Page=Test/Page"])
            started, release, finished = threading.Event(), threading.Event(), threading.Event()
            errors = []
            original_commit = module_export._commit

            def delayed_commit(*args):
                started.set()
                if not release.wait(10):
                    raise TimeoutError("publication was not released")
                return original_commit(*args)

            def publisher():
                try:
                    with patch.object(module_export, "_commit", delayed_commit):
                        publish("new")
                except Exception as error:
                    errors.append(error)

            def reader():
                try:
                    with patch("PS4HTML.module_protocol.find_project_root", return_value=workspace):
                        snapshot_target(target, workspace / "snapshot")
                except PS4HTMLError as error:
                    errors.append(error)
                finally:
                    finished.set()

            writing = threading.Thread(target=publisher)
            reading = threading.Thread(target=reader)
            writing.start()
            self.assertTrue(started.wait(10))
            try:
                reading.start()
                self.assertFalse(finished.wait(.1), "renderer read a module during publication")
            finally:
                release.set()
                writing.join(10)
                reading.join(10)
            self.assertFalse(writing.is_alive() or reading.is_alive())
            self.assertEqual(len(errors), 1, errors)
            self.assertIsInstance(errors[0], PS4HTMLError)
            self.assertIn("digest mismatch", str(errors[0]))
            # Refreshing the target after publication makes its complete new view readable.
            target_manifest.publish(root, "Pkg", "Test", "module", "Test.Page", ["Test.Page=Test/Page"])
            with patch("PS4HTML.module_protocol.find_project_root", return_value=workspace):
                snapshot_target(target, workspace / "fresh")
            self.assertEqual((workspace / "fresh" / relative).read_text(), "new")


if __name__ == "__main__":
    unittest.main()
