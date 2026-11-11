"""End-to-end checks for rendering verified Lake target manifests."""

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / ".ProofScript"
SITE = ROOT / ".PS4HTML/build/Test"
MODULES = EXPORT / "manifests/targets/ProofScript/Test/module"
LIBRARY = EXPORT / "manifests/targets/ProofScript/Test/library/Test.json"


def render(manifest):
    env = dict(os.environ, PYTHONPATH=str(ROOT / "tools/ps4html"))
    return subprocess.run([sys.executable, "-m", "PS4HTML", "_render-target", str(manifest)],
                          cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)


class ModuleRenderTests(unittest.TestCase):
    def test_single_module_scope_and_frozen_proof(self):
        result = render(MODULES / "Test.PageTheoremQualified.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        page = (SITE / "Test/PageTheoremQualified.html").read_text()
        self.assertIn("theorem-Qualified.root", page)
        self.assertIn("theorem-Outer.Qualified.nested", page)
        self.assertFalse((SITE / "Test/ModuleFigure.html").exists())

    def test_failure_keeps_previous_site(self):
        result = render(MODULES / "Test.ModuleFigure.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        home = SITE / "index.html"
        page = SITE / "Test/ModuleFigure.html"
        before = (home.read_bytes(), page.read_bytes())
        bad = EXPORT / "manifests/modules/Test/ModuleFigure.json"
        original = bad.read_bytes()
        try:
            bad.write_bytes(original + b" ")
            result = render(MODULES / "Test.ModuleFigure.json")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("digest mismatch", result.stderr)
            self.assertEqual((home.read_bytes(), page.read_bytes()), before)
        finally:
            bad.write_bytes(original)

    def test_computation_runtime_files_are_published(self):
        result = render(MODULES / "Test.ModuleComputation.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        document = json.loads((EXPORT / "pages/Test/ModuleComputation.json").read_text())
        execution = document["components"][0]["data"]["computation"]["value"]["execution"]
        self.assertEqual(execution["status"], "ready")
        for kind in ("manifest", "module", "wasm"):
            reference = execution[kind]["$resource"]
            relative = reference["path"]
            self.assertEqual((SITE / relative).read_bytes(), (ROOT / relative).read_bytes())
        self.assertIn("data-computation", (SITE / "Test/ModuleComputation.html").read_text())
        script = (SITE.parent / "assets/js/computation.js").read_text()
        self.assertIn('RECORDING_VERSION = "0.4.0"', script)

    def test_library_scope(self):
        result = render(LIBRARY)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((SITE / "Test/PageTitle.html").is_file())
        self.assertTrue((SITE / "Test/ModuleFigure.html").is_file())
        self.assertFalse((SITE / "Test/InfoFreezeProjectBase.html").exists())

    def test_package_index_and_shared_assets(self):
        result = render(LIBRARY)
        self.assertEqual(result.returncode, 0, result.stderr)
        build = SITE.parent
        index = (build / "index.html").read_text()
        page = (SITE / "Test/PageTitle.html").read_text()
        self.assertIn("<title>ProofScript</title>", index)
        self.assertIn('class="module-sidebar"', index)
        self.assertIn('href="Test/index.html"', index)
        self.assertIn('href="./assets/css/layout.css"', index)
        self.assertIn('href="../assets/css/layout.css"', (SITE / "index.html").read_text())
        self.assertIn('href="../../assets/css/layout.css"', page)
        self.assertIn('"Test"', (build / "assets/js/libraries.js").read_text())
        self.assertFalse((SITE / "assets").exists())


if __name__ == "__main__":
    unittest.main()
