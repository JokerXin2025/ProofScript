"""Render a real page-mode export without touching the repository's .ProofScript tree.

Prerequisite: lake build +Test.PageTheoremExpressionBoundaries:proofscriptExport
(the Lake publication may reject old repository manifests after producing its descriptor).
"""

import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/proofscript"))
sys.path.insert(0, str(ROOT / "tools/ps4html"))

import module_export
import target_manifest
from PS4HTML.module_protocol import render_target
from PS4HTML.project import PS4HTMLError


class IsolatedRenderTests(unittest.TestCase):
    def test_render_uses_toml_without_changing_proofscript_exports(self):
        inputs = ROOT / ".lake/proofscript/ProofScript/Test/exports/module/Test/PageTheoremExpressionBoundaries"
        descriptor, build = inputs / "descriptor.json", inputs / "build.json"
        self.assertTrue(descriptor.is_file() and build.is_file(), "build the page-mode module first")
        self.assertEqual(json.loads(descriptor.read_text())["module"], ["Test", "PageTheoremExpressionBoundaries"])
        with tempfile.TemporaryDirectory(prefix="ps4html-render-") as directory:
            workspace = Path(directory)
            (workspace / "lakefile.toml").write_text("")
            exported = workspace / ".ProofScript"
            module_export.publish(descriptor, exported, ROOT, ROOT, build)
            target = target_manifest.publish(exported, "ProofScript", "Test", "module",
                                             "Test.PageTheoremExpressionBoundaries",
                                             ["Test.PageTheoremExpressionBoundaries=Test/PageTheoremExpressionBoundaries"])
            completion = exported / "manifests/modules/Test/PageTheoremExpressionBoundaries.json"
            original = hashlib.sha256(completion.read_bytes()).digest()
            info = json.loads((exported / "info/Test/PageTheoremExpressionBoundaries.json").read_text())
            self.assertEqual({record["identity"]["kind"] for record in info["records"]} - {"decl", "script"}, set())
            config = workspace / "ps4html-config.toml"
            config.write_text('[site]\ntitle = "First Title"\nbase_url = "https://example.org/notes/"\n'
                               '[render]\ndefault_language = "zh"\n', encoding="utf-8")
            with patch.dict(os.environ, {"PROOF_SCRIPT_VERSO_RENDERER": str(ROOT / ".lake/build/bin/proofscriptVersoRender")}), \
                    patch("PS4HTML.module_protocol.find_project_root", return_value=workspace):
                render_target(target)
            site = workspace / ".PS4HTML/build"
            home = site / "Test/index.html"
            page = site / "Test/Test/PageTheoremExpressionBoundaries.html"
            self.assertIn("First Title", home.read_text())
            self.assertIn('data-default-language="zh"', page.read_text())
            self.assertIn('data-project-url="https://example.org/notes/Test/"', page.read_text())
            config.write_text('[site]\ntitle = "Updated Title"\n', encoding="utf-8")
            with patch.dict(os.environ, {"PROOF_SCRIPT_VERSO_RENDERER": str(ROOT / ".lake/build/bin/proofscriptVersoRender")}), \
                    patch("PS4HTML.module_protocol.find_project_root", return_value=workspace):
                render_target(target)
            self.assertIn("Updated Title", home.read_text())
            self.assertIn('data-default-language="en"', page.read_text())
            self.assertNotIn("First Title", home.read_text())
            self.assertEqual(hashlib.sha256(completion.read_bytes()).digest(), original)
            previous = home.read_bytes()
            config.write_text('[render]\ndefault_language = "invalid"\n', encoding="utf-8")
            with patch("PS4HTML.module_protocol.find_project_root", return_value=workspace):
                with self.assertRaisesRegex(PS4HTMLError, "render.default_language"):
                    render_target(target)
            self.assertEqual(home.read_bytes(), previous)
            config.write_text("", encoding="utf-8")
            old_target = json.loads(target.read_text(encoding="utf-8"))
            target.write_text(json.dumps({**old_target, "target": "another-module"}), encoding="utf-8")
            with patch("PS4HTML.module_protocol.find_project_root", return_value=workspace):
                with self.assertRaisesRegex(PS4HTMLError, "Target manifest identity"):
                    render_target(target)
            self.assertEqual(home.read_bytes(), previous)


if __name__ == "__main__":
    unittest.main()
