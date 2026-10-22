"""Exercise real Lake/Python page builds across two local user packages.

Run with:
    PYTHONPATH=tools/ps4html python3 -m unittest Test/test_page_mode_integration.py

The checkout's existing dependency directories are required. All dependencies are
overridden with local paths and artifact downloads are disabled; the test never
needs LaTeX, Wasm, or a network connection. A failed fixture and its command logs
remain in the temporary directory printed by the failure.
"""

import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
PROJECT = "PageMode.integration"
UPSTREAM_TITLE = "Upstream inline theorem"
DOWNSTREAM_TITLE = "Downstream inline theorem"


def _write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _local_entry(name, directory, *, inherited=True, config="lakefile.lean", scope=""):
    return {
        "name": name,
        "type": "path",
        "dir": str(directory),
        "scope": scope,
        "inherited": inherited,
        "configFile": config,
        "manifestFile": "lake-manifest.json",
    }


def _manifest(name, packages):
    return {
        "version": "1.2.0",
        "name": name,
        "lakeDir": ".lake",
        "packagesDir": ".lake/packages",
        "fixedToolchain": False,
        "packages": packages,
    }


@unittest.skipUnless(shutil.which("lake"), "Lean's Lake executable is not installed")
class PageModeIntegrationTest(unittest.TestCase):
    def setUp(self):
        self.fixture = Path(tempfile.mkdtemp(prefix="proofscript-page-mode-integration-", dir="/tmp")).resolve()
        self.upstream = self.fixture / "upstream"
        self.downstream = self.fixture / "downstream"
        self.logs = self.fixture / "logs"
        self.logs.mkdir()
        self.environment = os.environ.copy()
        # Do not inherit another running build's unpublished output or page context.
        for key in (
            "PROOF_SCRIPT_OUTPUT_ROOT", "PS4HTML_BUILD_SESSION", "PROOF_SCRIPT_BUILD_MANIFEST",
            "PS4HTML_LAKE_ARGS", "PS4HTML_LAKE_CONFIG", "PS4HTML_LAKE_CWD",
            "PS4HTML_PAGE_TEST_TARGET",
        ):
            self.environment.pop(key, None)
        self.environment.update({
            "PS4HTML_PYTHON": sys.executable,
            "PYTHONPATH": str(REPOSITORY / "tools/ps4html"),
            "MATHLIB_NO_CACHE_ON_UPDATE": "1",
            "LAKE_NO_CACHE": "true",
        })
        self.lake = shutil.which("lake")
        self.overrides = self.fixture / "packages.json"
        self.success = False

    def tearDown(self):
        if self.success:
            shutil.rmtree(self.fixture)
        else:
            print(f"\nPage-mode integration fixture and logs: {self.fixture}", file=sys.stderr)

    def _run(self, label, arguments, *, timeout=600):
        command = [self.lake, "--packages", str(self.overrides), "--no-cache", *arguments]
        log = self.logs / f"{label}.log"
        with log.open("w", encoding="utf-8") as stream:
            stream.write(shlex.join(command) + "\n")
            stream.flush()
            try:
                result = subprocess.run(
                    command, cwd=self.downstream, env=self.environment,
                    stdout=stream, stderr=subprocess.STDOUT, text=True, timeout=timeout,
                )
            except subprocess.TimeoutExpired:
                self.fail(f"{label} timed out; log: {log}")
        output = log.read_text(encoding="utf-8")
        self.assertEqual(result.returncode, 0, f"{label} failed; log: {log}\n{output[-24000:]}")
        return output

    def _prepare_packages(self):
        toolchain = (REPOSITORY / "lean-toolchain").read_text(encoding="utf-8")
        repository_manifest = json.loads((REPOSITORY / "lake-manifest.json").read_text())
        dependencies = []
        for entry in repository_manifest["packages"]:
            directory = (REPOSITORY / entry["dir"] if entry["type"] == "path" else
                         REPOSITORY / repository_manifest["packagesDir"] / entry["name"])
            directory = directory.resolve()
            self.assertTrue(directory.is_dir(),
                            f"Missing cached dependency {entry['name']}: {directory}; fetch dependencies first")
            dependencies.append(_local_entry(
                entry["name"], directory, config=entry.get("configFile", "lakefile.lean"),
                scope=entry.get("scope", ""),
            ))
        framework = _local_entry("ProofScript", REPOSITORY)
        upstream = _local_entry("Upstream", self.upstream, inherited=False)
        self.overrides.write_text(json.dumps(_manifest("Downstream", [upstream, framework, *dependencies])))
        for directory, name, direct, inherited in (
            (self.upstream, "Upstream", _local_entry("ProofScript", REPOSITORY, inherited=False), dependencies),
            (self.downstream, "Downstream", upstream, [framework, *dependencies]),
        ):
            _write(directory / "lean-toolchain", toolchain)
            _write(directory / "lake-manifest.json", json.dumps(_manifest(name, [direct, *inherited])))
            _write(directory / "lakefile.lean", "\n".join((
                "import Lake", "open Lake DSL", f"package {name}",
                f"require {direct['name']} from {json.dumps(direct['dir'])}",
                "@[default_target]", f"lean_lib {name}", "",
            )))
        _write(self.upstream / "Upstream.lean", f'''import ProofScript

project_info "{PROJECT}" {{ title := "Integration project" }}

namespace Upstream

@theorem base (info := {{ name := "{UPSTREAM_TITLE}", project := "{PROJECT}" }}) : True := script
  trivial

page_end
end Upstream
''')
        _write(self.downstream / "Downstream.lean", f'''import Upstream

namespace Downstream

@theorem usesUpstream (info := {{ name := "{DOWNSTREAM_TITLE}", project := "{PROJECT}" }}) : True := script
  cite Upstream.base
  exact Upstream.base

@references
page_end
end Downstream
''')

    def _inspect_imports(self, page, setup=None, *, label=None):
        expected = "true" if page else "false"
        source = self.fixture / ("InspectPage.lean" if page else "InspectVerification.lean")
        _write(source, f'''import Downstream

open Lean Elab Command ProofScript

run_cmd do
  let env ← getEnv
  for owner in #[`ProofScript.Builtin.Script, `ProofScript.Builtin.Lean2TeX,
      `ProofScript.Mathlib.Info] do
    unless (!(Info.moduleEvents env owner).isEmpty) == {expected} do
      throwError "framework Info defaults disagree with the imported build mode"
  if {expected} then
    for (rule, renderer) in #[(`ProofScript.Script.Basic.renderCalc, Info.ScriptRenderer.calc),
        (`ProofScript.Script.Basic.infer, Info.ScriptRenderer.infer)] do
      let resolved ← match Info.resolveScriptInfo env {{ moduleName := `Downstream }} rule with
        | .ok resolved => pure resolved.value
        | .error error => throwError error.render
      unless resolved.renderer == renderer do
        throwError "framework script renderer configuration was lost"
  for owner in #[`Upstream, `Downstream] do
    let some mode := moduleBuildMode? env owner | throwError "missing imported build-mode marker"
    unless mode.pageBuild == {expected} && mode.version == buildModeVersion do
      throwError "wrong imported build-mode marker"
  for (name, title) in #[(`Upstream.base, "{UPSTREAM_TITLE}"),
      (`Downstream.usesUpstream, "{DOWNSTREAM_TITLE}")] do
    let some (.thmInfo _) := env.find? name | throwError "declaration is not a native theorem"
    unless (Info.declarationFacts? env name).isSome == {expected} do
      throwError "proof facts disagree with the imported build mode"
    if {expected} then
      let info ← match Info.resolveTheoremInfo env {{ moduleName := `Downstream }} name with
        | .ok info => pure info.value
        | .error error => throwError error.render
      unless info.name == title && info.project == some "{PROJECT}" do
        throwError "imported inline metadata was lost"
    else
      match Info.resolveTheoremInfo env {{ moduleName := `Downstream }} name with
      | .error _ => pure ()
      | .ok _ => throwError "verification consumed inline page metadata"
''')
        arguments = ["env", "lean", str(source)]
        if setup is not None:
            arguments.extend(("--setup", str(setup)))
        self._run(label or ("inspect-page" if page else "inspect-verification"), arguments)

    @staticmethod
    def _content_state(paths):
        return {str(path): (path.stat().st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest())
                for path in paths}

    @staticmethod
    def _stat_state(paths):
        return {str(path): (path.stat().st_mtime_ns, path.stat().st_size) for path in paths}

    def test_two_packages_keep_verification_and_page_products_separate(self):
        self._prepare_packages()
        self._run("verification-build", ["build", "Downstream"])
        self._inspect_imports(False)
        for directory in (self.upstream, self.downstream):
            self.assertFalse((directory / ".ProofScript").exists(), "verification wrote page output")

        normal_products = [directory / ".lake/build/lib/lean" / f"{module}.olean"
                           for directory, module in ((self.upstream, "Upstream"), (self.downstream, "Downstream"))]
        normal_state = self._content_state(normal_products)
        normal_setup = json.loads((self.downstream / ".lake/build/ir/Downstream.setup.json").read_text())
        supports = {Path(path) for artifacts in normal_setup["importArts"].values() for path in artifacts
                    if path.endswith(".olean") and Path(path) not in normal_products}
        self.assertTrue(any(path.is_relative_to(REPOSITORY / ".lake/packages/mathlib") for path in supports),
                        "the fixture must reuse real mathlib support artifacts")
        ordinary_dependency_state = self._stat_state(supports)
        framework_bytes = self._content_state([
            REPOSITORY / ".lake/build/lib/lean/ProofScript/Core/BuildMode.olean",
            REPOSITORY / ".lake/build/lib/lean/ProofScript.olean",
            REPOSITORY / ".lake/build/lib/lean/ProofScript/Script/Basic.olean",
            REPOSITORY / ".lake/build/lib/lean/ProofScript/Builtin/Script.olean",
            REPOSITORY / ".lake/build/lib/lean/ProofScript/Builtin/Lean2TeX.olean",
            REPOSITORY / ".lake/build/lib/lean/ProofScript/Mathlib/Info.olean",
        ])

        output = self._run("page-facet", ["build", "Downstream:ps4html"])
        self.assertIn("[PS4HTML] Building and exporting Downstream/Downstream with Lake", output)
        self.assertEqual(self._content_state(normal_products), normal_state,
                         "page compilation modified ordinary user oleans")
        self.assertEqual(self._stat_state(supports), ordinary_dependency_state,
                         "page compilation modified ordinary dependency artifacts")
        self.assertEqual(self._content_state(map(Path, framework_bytes)), framework_bytes)

        page_root = self.downstream / ".lake/ps4html/Downstream/Downstream"
        page_products = {}
        for module in ("Upstream", "Downstream", "ProofScript", "ProofScript.Script.Basic", "ProofScript.Builtin.Script",
                       "ProofScript.Builtin.Lean2TeX", "ProofScript.Mathlib.Info"):
            relative = module.replace(".", "/")
            matches = list(page_root.glob(f"*/lib/lean/{relative}.olean"))
            self.assertEqual(len(matches), 1, f"missing isolated {module} olean")
            page_products[module] = matches[0]
            setup_path = next(page_root.glob(f"*/ir/{relative}.setup.json"))
            setup = json.loads(setup_path.read_text())
            self.assertTrue(any(key.removeprefix("weak.") == "proofScript.pageBuild" and value is True
                                for key, value in setup["options"].items()),
                            "page mode must be part of the traced module setup options")
            if module == "Downstream":
                page_setup = setup
        self.assertEqual(Path(page_setup["importArts"]["Upstream"][0]), page_products["Upstream"])
        self.assertEqual(Path(page_setup["importArts"]["ProofScript"][0]),
                         page_products["ProofScript"])
        page_setup.update(name="InspectPage", options={})
        page_setup["importArts"]["Downstream"] = [str(page_products["Downstream"])]
        inspect_setup = self.fixture / "inspect-page.setup.json"
        _write(inspect_setup, json.dumps(page_setup))
        self._inspect_imports(True, inspect_setup)

        export_root = self.downstream / ".PS4HTML/inputs/Downstream/Downstream/.ProofScript"
        index = json.loads((export_root / "info/index.json").read_text())
        self.assertEqual([module["module"] for module in index["modules"]], ["Downstream"],
                         "compiling an upstream package must not publish its pages as owners")
        artifact = next(item for item in index["artifacts"]
                        if item.get("declaration") == ["Downstream", "usesUpstream"])
        self.assertEqual(artifact["projectId"], PROJECT)
        self.assertEqual(artifact["proofDependencies"], [["Upstream", "base"]])
        snapshot_entry = next(item for item in index["snapshots"] if item["id"] == artifact["snapshotId"])
        snapshot = json.loads((export_root / snapshot_entry["path"]).read_text())
        theorem_records = {tuple(record["identity"]["target"]): record["value"]
                           for record in snapshot["payload"]["records"]
                           if record["identity"]["kind"] == "theorem"}
        self.assertEqual(theorem_records[("Downstream", "usesUpstream")]["name"], DOWNSTREAM_TITLE)
        script_records = {tuple(record["identity"]["target"]): record
                          for record in snapshot["payload"]["records"]
                          if record["identity"]["kind"] == "script"}
        exact = script_records[("ProofScript", "Script", "Basic", "exact")]
        self.assertTrue(exact["configured"], "framework script_info was lost during page compilation")
        self.assertEqual(len(exact["value"]["template"]), 2)
        for module, name in (("Upstream", "base"), ("Downstream", "usesUpstream")):
            proof = json.loads((export_root / f"proofs/{module}/{name}.json").read_text())
            self.assertTrue(proof["proof"], f"{module} was not recorded")
            self.assertTrue(all("_ruleId" in step for step in proof["proof"]))
        page = json.loads((export_root / "pages/Downstream.json").read_text())
        theorem = next(component["data"]["theorem"]["value"] for component in page["components"]
                       if "theorem" in component["data"])
        self.assertEqual(theorem["name"], DOWNSTREAM_TITLE)
        references = next(component["data"]["references"]["value"] for component in page["components"]
                          if "references" in component["data"])
        upstream_reference = next(item for item in references if item["name"] == "Upstream.base")
        self.assertEqual(upstream_reference["info"]["name"], UPSTREAM_TITLE)
        self.assertEqual(upstream_reference["info"]["project"], PROJECT)
        html = (self.downstream / ".PS4HTML/build/Downstream/Downstream/index.html").read_text()
        self.assertIn(DOWNSTREAM_TITLE, html)

        self._run("verification-rebuild", ["build", "Downstream"])
        self._inspect_imports(False)
        self.assertEqual(self._content_state(normal_products), normal_state,
                         "returning to verification recompiled ordinary user oleans")
        self.assertEqual(self._stat_state(supports), ordinary_dependency_state)
        self.assertEqual(self._content_state(map(Path, framework_bytes)), framework_bytes)
        for directory in (self.upstream, self.downstream):
            self.assertFalse((directory / ".ProofScript").exists())

        # Both targets share a parent Lake BuildStore. The pageTests coordinator
        # must still compile its own source closure in a fresh Lake process.
        recording_root = self.fixture / "page-test-output"
        self.environment["PROOF_SCRIPT_OUTPUT_ROOT"] = str(recording_root)
        try:
            self._run("combined-page-tests", ["build", "Downstream", "Downstream:pageTests"])
        finally:
            self.environment.pop("PROOF_SCRIPT_OUTPUT_ROOT", None)
        test_root = self.downstream / ".lake/ps4html-tests/Downstream/Downstream"
        test_products = {}
        for module in ("Upstream", "Downstream", "ProofScript", "ProofScript.Script.Basic", "ProofScript.Builtin.Script",
                       "ProofScript.Builtin.Lean2TeX", "ProofScript.Mathlib.Info"):
            relative = module.replace(".", "/")
            matches = list(test_root.glob(f"*/lib/lean/{relative}.olean"))
            self.assertEqual(len(matches), 1, f"pageTests did not isolate {module}")
            test_products[module] = matches[0]
            setup = json.loads(next(test_root.glob(f"*/ir/{relative}.setup.json")).read_text())
            self.assertTrue(any(key.removeprefix("weak.") == "proofScript.pageBuild" and value is True
                                for key, value in setup["options"].items()),
                            "pageTests did not trace page mode in the module setup")
            if module == "Downstream":
                test_setup = setup
        self.assertEqual(Path(test_setup["importArts"]["Upstream"][0]), test_products["Upstream"])
        self.assertEqual(Path(test_setup["importArts"]["ProofScript"][0]),
                         test_products["ProofScript"])
        test_setup.update(name="InspectPage", options={})
        test_setup["importArts"]["Downstream"] = [str(test_products["Downstream"])]
        test_inspect_setup = self.fixture / "inspect-page-tests.setup.json"
        _write(test_inspect_setup, json.dumps(test_setup))
        self._inspect_imports(True, test_inspect_setup, label="inspect-page-tests")
        for module, name in (("Upstream", "base"), ("Downstream", "usesUpstream")):
            proof = json.loads((recording_root / f"proofs/{module}/{name}.json").read_text())
            self.assertTrue(proof["proof"], f"pageTests did not record {module}")
            self.assertTrue(all("_ruleId" in step for step in proof["proof"]))
            self.assertTrue((recording_root / f"pages/{module}.json").is_file())
        self._inspect_imports(False, label="inspect-verification-after-page-tests")
        self.assertEqual(self._content_state(normal_products), normal_state,
                         "combined normal/pageTests targets modified ordinary user oleans")
        self.assertEqual(self._stat_state(supports), ordinary_dependency_state,
                         "combined normal/pageTests targets modified ordinary dependency artifacts")
        self.assertEqual(self._content_state(map(Path, framework_bytes)), framework_bytes)
        for directory in (self.upstream, self.downstream):
            self.assertFalse((directory / ".ProofScript").exists())
        self.success = True


if __name__ == "__main__":
    unittest.main()
