"""Run with PYTHONPATH=tools/ps4html python3 -m unittest Test/test_ps4html_build.py."""

import importlib
import json
import os
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch


make = importlib.import_module("PS4HTML.make")


class LibraryBuildTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / "lakefile.lean").write_text("-- test project\n")
        self.normal_build = self.root / ".lake" / "build"
        self.build_dir = self.root / ".lake" / "ps4html" / "Demo" / "Demo"
        self.lake = str(self.root / "tools" / "lake")
        self.modules_and_sources = []
        for module, relative in (("Demo", "Demo.lean"), ("Demo.Page", "Demo/Page.lean")):
            source = self.root / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("-- test module\n")
            self.modules_and_sources.extend((module, str(source)))
        self.builds = []
        self.commands = []
        self.exports = []
        self.renders = []
        self.generation = 0
        self.fail_build = False
        self.fail_render = False

    def _warm_artifacts(self):
        stale = self.build_dir / "lib" / "lean" / "Stale.olean"
        stale.parent.mkdir(parents=True, exist_ok=True)
        stale.write_text("old Lean artifact")
        return stale

    def _run_lake(self, command, project_root, environment=None):
        self.commands.append(list(command))
        self.assertEqual(Path(project_root), self.root)
        self.assertIsNotNone(environment)
        self.assertEqual(command[0], self.lake, "Use Lake rather than recompiling sources directly")
        if "build" in command:
            self.assertTrue(self.build_dir.is_dir())
            self.assertEqual(list(self.build_dir.iterdir()), [], "Only the page build artifacts must be removed")
            self.assertEqual(environment.get("LAKE_RESTORE_ARTIFACTS"), "true")
            session_path = Path(environment["PS4HTML_BUILD_SESSION"])
            session = json.loads(session_path.read_text())
            self.assertEqual(Path(session["buildRoot"]), self.build_dir)
            self.assertEqual(session["package"], "Demo")
            self.assertEqual(session["library"], "Demo")
            self.assertEqual(environment["PROOF_SCRIPT_BUILD_MANIFEST"], str(session_path))
            self.builds.append(list(command))
            if self.fail_build:
                raise make.PS4HTMLError("test compilation failure")
            self.generation += 1
            export_root = Path(environment["PROOF_SCRIPT_OUTPUT_ROOT"])
            self.assertEqual(str(export_root), session["exportRoot"])
            export_root.mkdir(parents=True, exist_ok=True)
            (export_root / "compiled.txt").write_text(str(self.generation))
            self._warm_artifacts()
            # The internal facet exports while its isolated workspace is active.
            modules = self.modules_and_sources[::2]
            self.exports.append(set(modules))
            session.update(owners=sorted(modules), sourcePackages=["Demo"], modules=[])
            session_path.write_text(json.dumps(session))
            info = export_root / "info"
            info.mkdir(parents=True, exist_ok=True)
            (info / "index.json").write_text(json.dumps({
                "artifacts": [], "files": [], "modules": modules,
            }))
            return
        self.fail("Build and export must run in one internal Lake invocation")

    def _render(self, project_root, build_root, modules=None, export_root=None):
        self.assertEqual(Path(project_root), self.root)
        modules = set(modules)
        exported = json.loads((Path(export_root) / "info" / "index.json").read_text())
        self.assertEqual(set(exported["modules"]), modules)
        self.renders.append(modules)
        if self.fail_render:
            raise make.PS4HTMLError("test rendering failure")
        build_root = Path(build_root)
        build_root.mkdir(parents=True, exist_ok=True)
        (build_root / "index.html").write_text(
            f"generation {self.generation}: {','.join(sorted(modules))}")

    def _build_library(self, *, lake_environment=None):
        environment = {
            "LAKE": self.lake,
            "PS4HTML_LAKE_CONFIG": "",
            "PS4HTML_LAKE_ARGS": "[]",
            "PS4HTML_LAKE_CWD": str(self.root),
        }
        environment.update(lake_environment or {})
        with ExitStack() as stack:
            stack.enter_context(patch.dict(os.environ, environment))
            stack.enter_context(patch.object(make, "find_project_root", return_value=self.root))
            stack.enter_context(patch.object(make, "_run_lake", side_effect=self._run_lake))
            stack.enter_context(patch.object(make, "_build_computations"))
            stack.enter_context(patch.object(make, "_seal_resources"))
            stack.enter_context(patch.object(make, "render_site", side_effect=self._render))
            return make.build_library("Demo", "Demo", self.modules_and_sources,
                                      build_dir=self.build_dir)

    def _published(self, library="Demo"):
        return self.root / ".PS4HTML" / "build" / "Demo" / library

    def _snapshot(self):
        site = self._published()
        inputs = self.root / ".PS4HTML" / "inputs" / "Demo" / "Demo" / ".ProofScript"
        return (
            site.resolve(),
            (site / "index.html").read_text(),
            inputs.resolve(),
            (inputs / "compiled.txt").read_text(),
            (self.root / ".PS4HTML" / "build" / "index.html").read_text(),
        )

    def test_cleans_warm_artifacts_before_one_library_build(self):
        self._warm_artifacts()
        self._build_library()

        self.assertEqual(self.builds, [[self.lake, "--no-cache", "build", "@Demo/Demo:ps4htmlInputs"]])
        self.assertEqual(self.exports, [{"Demo", "Demo.Page"}])
        self.assertEqual(self.renders, [{"Demo", "Demo.Page"}])
        self.assertIn("generation 1", (self._published() / "index.html").read_text())
        self.assertFalse((self._published().parent / "session.json").exists())

    def test_preserves_normal_verification_artifacts(self):
        normal = self.normal_build / "lib" / "lean" / "Demo.olean"
        normal.parent.mkdir(parents=True)
        normal.write_bytes(b"ordinary Lean verification artifact")
        self._warm_artifacts()

        self._build_library()

        self.assertEqual(normal.read_bytes(), b"ordinary Lean verification artifact")
        self.assertEqual(len(self.builds), 1)

    def test_session_manifest_is_not_published(self):
        self._build_library()

        release = (self.root / ".PS4HTML" / "releases" / "Demo" / "Demo" / "current").resolve()
        self.assertEqual({path.name for path in release.iterdir()}, {".ProofScript", "site"})

    def test_preserves_dependency_build_artifacts(self):
        dependency = self.root / ".lake" / "packages" / "Dependency" / ".lake" / "build" / "Dependency.olean"
        dependency.parent.mkdir(parents=True)
        dependency.write_text("cached dependency")
        self._warm_artifacts()
        self._build_library()

        self.assertEqual(dependency.read_text(), "cached dependency")
        self.assertEqual(len(self.builds), 1)

    def test_rejects_build_directory_overlapping_published_outputs(self):
        self._build_library()
        previous = self._snapshot()
        previous_commands = list(self.commands)

        for relative in (".PS4HTML", ".PS4HTML/staging"):
            with self.subTest(build_dir=relative):
                self.build_dir = self.root / relative
                with self.assertRaisesRegex(make.PS4HTMLError, "page build directory"):
                    self._build_library()
                self.assertEqual(self._snapshot(), previous)
                self.assertEqual(self.commands, previous_commands)

    def test_rejects_normal_build_directory(self):
        self.build_dir = self.normal_build
        normal = self._warm_artifacts()

        with self.assertRaisesRegex(make.PS4HTMLError, "page build directory"):
            self._build_library()

        self.assertEqual(normal.read_text(), "old Lean artifact")
        self.assertEqual(self.commands, [])

    def test_rejects_symlinked_page_build_directory(self):
        ordinary = self.normal_build
        ordinary.mkdir(parents=True)
        marker = ordinary / "must-survive"
        marker.write_text("verification cache")
        self.build_dir.parent.mkdir(parents=True)
        self.build_dir.symlink_to(ordinary, target_is_directory=True)

        with self.assertRaisesRegex(make.PS4HTMLError, "page build directory"):
            self._build_library()

        self.assertEqual(marker.read_text(), "verification cache")
        self.assertEqual(self.commands, [])

    def test_build_and_export_inherit_outer_lake_configuration(self):
        self._build_library(lake_environment={
            "PS4HTML_LAKE_CONFIG": "/tmp/custom.lean",
            "PS4HTML_LAKE_ARGS": json.dumps([
                "--dir", "elsewhere", "-Kfeature=true", "-K", "another=1",
                "--packages", "overrides.json", "build", "Old:ps4html",
            ]),
            "PS4HTML_LAKE_CWD": "/tmp/original",
        })

        prefix = [self.lake, "--file", "/tmp/custom.lean", "-Kfeature=true",
                  "-K", "another=1", "--packages", "/tmp/original/overrides.json"]
        self.assertEqual(len(self.commands), 1)
        self.assertEqual(self.builds, [[*prefix, "--no-cache", "build", "@Demo/Demo:ps4htmlInputs"]])
        for command in self.commands:
            self.assertNotIn("--dir", command)
            self.assertNotIn("elsewhere", command)
            self.assertNotIn("Old:ps4html", command)

    def test_compilation_failure_preserves_previous_inputs_and_site(self):
        self._build_library()
        previous = self._snapshot()
        self.fail_build = True

        with self.assertRaisesRegex(make.PS4HTMLError, "test compilation failure"):
            self._build_library()

        self.assertEqual(self._snapshot(), previous)
        self.assertEqual(len(self.builds), 2)
        self.assertEqual(len(self.exports), 1)
        self.assertEqual(len(self.renders), 1)

    def test_rendering_failure_preserves_previous_inputs_and_site(self):
        self._build_library()
        previous = self._snapshot()
        self.fail_render = True

        with self.assertRaisesRegex(make.PS4HTMLError, "test rendering failure"):
            self._build_library()

        self.assertEqual(self._snapshot(), previous)
        self.assertEqual(len(self.builds), 2)

    def test_repeated_build_cleans_artifacts_and_compiles_once_each_time(self):
        self._warm_artifacts()
        self._build_library()
        first_release = self._published().resolve()
        self.assertTrue((self.build_dir / "lib" / "lean" / "Stale.olean").exists())

        self._build_library()

        self.assertEqual(len(self.builds), 2)
        self.assertEqual(len(self.exports), 2)
        self.assertEqual(len(self.renders), 2)
        self.assertNotEqual(self._published().resolve(), first_release)
        self.assertIn("generation 2", (self._published() / "index.html").read_text())


if __name__ == "__main__":
    unittest.main()
