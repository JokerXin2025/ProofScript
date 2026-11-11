"""Integration checks for Lake's independent per-module export facets."""

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / ".ProofScript"
SITE = ROOT / ".PS4HTML/build/Test"
MODULE = "Test.ModuleResourceAudit"
COMPLETION = EXPORT / "manifests/modules/Test/ModuleResourceAudit.json"
TARGET = EXPORT / "manifests/targets/ProofScript/Test/module/Test.ModuleResourceAudit.json"


def build(*arguments):
    return subprocess.run(["lake", "build", *arguments], cwd=ROOT,
                          capture_output=True, text=True, timeout=240, check=True)


class LakeExportTests(unittest.TestCase):
    def test_module_cache_and_missing_output_recovery(self):
        build(f"+{MODULE}:proofscriptExport")
        first = json.loads(COMPLETION.read_text())
        self.assertEqual(json.loads(TARGET.read_text())["modules"][0]["module"],
                         ["Test", "ModuleResourceAudit"])
        page = EXPORT / "pages/Test/ModuleResourceAudit.json"
        stamp = COMPLETION.stat().st_mtime_ns
        build(f"+{MODULE}:proofscriptExport")
        self.assertEqual(COMPLETION.stat().st_mtime_ns, stamp)
        page.unlink()
        build(f"+{MODULE}:proofscriptExport")
        self.assertTrue(page.is_file())
        self.assertEqual(first["files"], json.loads(COMPLETION.read_text())["files"])

    def test_configuration_only_module_exports_no_info(self):
        build("+Test.InfoFreezeProjectBase:proofscriptExport")
        completion = json.loads((EXPORT / "manifests/modules/Test/InfoFreezeProjectBase.json").read_text())
        self.assertFalse(completion["hasComponents"])
        self.assertEqual(completion["files"], [])

    def test_render_waits_for_exports(self):
        build(f"+{MODULE}:ps4html")
        self.assertTrue(TARGET.is_file())
        self.assertTrue((SITE / "Test/ModuleResourceAudit.html").is_file())
        self.assertFalse((SITE / "Test/PageTitle.html").exists())

    def test_library_inventory_contains_only_current_modules(self):
        build("Test:proofscriptExport")
        target = json.loads((EXPORT / "manifests/targets/ProofScript/Test/library/Test.json").read_text())
        self.assertEqual(target["kind"], "library")
        names = {tuple(entry["module"]) for entry in target["modules"]}
        self.assertIn(("Test", "ModuleResourceAudit"), names)
        self.assertIn(("Test", "InfoFreezeProjectBase"), names)
        self.assertNotIn(("ProofScript", "Info", "Freeze"), names)


if __name__ == "__main__":
    unittest.main()
