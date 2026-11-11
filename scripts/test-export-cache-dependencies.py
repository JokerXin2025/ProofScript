"""An imported Info-only update must invalidate the dependent module's export."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools/proofscript/export_cache.py"
SPEC = importlib.util.spec_from_file_location("export_cache", SCRIPT)
cache = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cache)


class ExportCacheDependenciesTests(unittest.TestCase):
    def test_imported_info_change_invalidates_unchanged_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = {name: root / name for name in ("owner.olean", "import.olean", "exporter", "publisher")}
            for name, path in paths.items():
                path.write_text(name)
            build = root / "build.json"
            build.write_text(json.dumps({
                "selectedProject": {"package": "Demo", "library": "Project"},
                "projectRoots": ["Project"], "libraryModules": ["Project.A"],
                "sourcePackages": ["Demo"],
                "closureProjects": [{"module": "Project.A", "package": "Demo", "library": "Project"},
                                    {"module": "Project.Base", "package": "Demo", "library": "Project"}],
                "moduleProjects": [{"module": "Project.A", "package": "Demo", "library": "Project"}],
                "modules": [{"name": "Project.A", "package": "Demo", "olean": str(paths["owner.olean"])},
                            {"name": "Project.Base", "package": "Demo", "olean": str(paths["import.olean"])}],
            }))
            def fingerprint():
                return cache.fingerprint(build, paths["exporter"], paths["publisher"], [])
            before = fingerprint()
            paths["import.olean"].write_text("new Info value")
            self.assertNotEqual(before, fingerprint())


if __name__ == "__main__":
    unittest.main()
