"""Re-export a compiled page from its .olean into an isolated module output tree."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE = "Test.PagePersistence"


class LeanModuleExportTests(unittest.TestCase):
    def export_module(self, module: str, source: str):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        manifest = directory / "build.json"
        descriptor = directory / "descriptor.json"
        output = directory / ".ProofScript"
        project = {"package": "ProofScript", "library": "Test"}
        module_path = module.replace(".", "/")
        manifest.write_text(json.dumps({
            "schemaVersion": 1,
            "moduleManifest": f"manifests/modules/{module_path}.json",
            "selectedProject": project,
            "projects": [project],
            "projectRoots": ["Test"],
            "libraryModules": [module],
            "moduleProjects": [{"module": module, **project}],
            "closureProjects": [{"module": module, **project}],
            "modules": [{"name": module, "package": "ProofScript",
                         "source": source,
                         "olean": str(ROOT / f".lake/build/lib/lean/{module_path}.olean"),
                         "c": str(ROOT / f".lake/build/ir/{module_path}.c"),
                         "setup": str(ROOT / f".lake/build/ir/{module_path}.setup.json")}],
        }))
        environment = os.environ.copy()
        environment["PROOF_SCRIPT_BUILD_MANIFEST"] = str(manifest)
        subprocess.run([
            "lake", "env", str(ROOT / ".lake/build/bin/proofscriptModuleExport"),
            str(descriptor), str(output), str(ROOT / "tools/proofscript/module_export.py"),
            str(ROOT), module,
        ], cwd=ROOT, env=environment, check=True)
        return output

    def test_persisted_page_exports_without_ps4html(self):
        output = self.export_module(MODULE, "Test/PagePersistence.lean")
        page = json.loads((output / "pages/Test/PagePersistence.json").read_text())
        info = json.loads((output / "info/Test/PagePersistence.json").read_text())
        completion = json.loads((output / "manifests/modules/Test/PagePersistence.json").read_text())
        theorem = page["components"][1]["data"]["theorem"]["value"]
        self.assertEqual(theorem["name"],
                         "模块最终标题")
        self.assertEqual(theorem["declaration"], ["PagePersistence", "laterInfo"])
        self.assertIn("projectId", theorem)
        self.assertIsInstance(theorem["proofRefs"], list)
        self.assertIsInstance(theorem["proofDependencies"], list)
        self.assertEqual(info["schemaVersion"], "14.0.0")
        self.assertEqual(completion["complete"], True)
        self.assertTrue(any(entry["path"].startswith("proofs/") for entry in completion["files"]))
        proof = json.loads((output /
            "proofs/Test/PagePersistence/%X/PagePersistence/laterInfo.json").read_text())
        self.assertNotIn("theoremFacts", proof)
        self.assertNotIn("declaration", proof)
        self.assertIn("bindings", proof)
        self.assertEqual(completion["module"], ["Test", "PagePersistence"])
        files = {item["path"] for item in completion["files"]}
        self.assertEqual(files, {
            "info/Test/PagePersistence.json", "pages/Test/PagePersistence.json",
            "proofs/Test/PagePersistence/%X/PagePersistence/laterInfo.json",
        })

    def test_wasm_is_executable_after_module_export(self):
        output = self.export_module("Test.ModuleComputation", "Test/ModuleComputation.lean")
        page = json.loads((output / "pages/Test/ModuleComputation.json").read_text())
        execution = page["components"][0]["data"]["computation"]["value"]["execution"]
        self.assertEqual(execution["status"], "ready")
        wasm = output / execution["wasm"]["$resource"]["path"].removeprefix(".ProofScript/")
        self.assertEqual(wasm.read_bytes()[:4], b"\x00asm")
        self.assertIn("moduleComputation", execution["entry"])
        environment = os.environ.copy()
        environment["PROOF_SCRIPT_PROJECT_ROOT"] = str(output.parent)
        completed = subprocess.run([
            "node", str(ROOT / "scripts/invoke-finalized-computation.mjs"),
            str(output / "pages/Test/ModuleComputation.json"), execution["entry"], "41",
        ], cwd=output.parent, env=environment, capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(json.loads(completed.stdout), {"ok": True, "value": 42})

    def test_figure_uses_copied_export_resource(self):
        output = self.export_module("Test.ModuleFigure", "Test/ModuleFigure.lean")
        page = json.loads((output / "pages/Test/ModuleFigure.json").read_text())
        figure = page["components"][0]["data"]["figure"]["value"]
        resource = figure["resource"]["$resource"]
        self.assertEqual(figure["path"], resource["path"])
        self.assertEqual(resource["encoding"], "binary")
        image = output / resource["path"].removeprefix(".ProofScript/")
        self.assertEqual(image.read_bytes(), (ROOT / "Test/fixtures/module-figure.svg").read_bytes())

    def test_configuration_only_module_has_only_completion_manifest(self):
        output = self.export_module("Test.InfoFreezeProjectBase", "Test/InfoFreezeProjectBase.lean")
        manifest = json.loads((output / "manifests/modules/Test/InfoFreezeProjectBase.json").read_text())
        self.assertFalse(manifest["hasComponents"])
        self.assertEqual(manifest["files"], [])
        self.assertFalse((output / "info/Test/InfoFreezeProjectBase.json").exists())

    def test_proof_resource_relocation_does_not_rewrite_plain_text(self):
        output = self.export_module("Test.ModuleResourceAudit", "Test/ModuleResourceAudit.lean")
        page = json.loads((output / "pages/Test/ModuleResourceAudit.json").read_text())
        self.assertEqual(page["components"][0]["data"]["title"]["value"],
                         "Test/fixtures/module-figure.svg")
        figure = page["components"][1]["data"]["figure"]["value"]
        self.assertTrue(figure["path"].startswith(".ProofScript/resources/Test/ModuleResourceAudit/images/"))
        proof = json.loads((output / "proofs/Test/ModuleResourceAudit/%X/ModuleResourceAudit/proof.json").read_text())
        path = proof["svg"]["$resource"]["path"]
        self.assertTrue(path.startswith(".ProofScript/resources/Test/ModuleResourceAudit/generated/"))
        self.assertEqual((output / path.removeprefix(".ProofScript/")).read_text(), "<svg/>")


if __name__ == "__main__":
    unittest.main()
