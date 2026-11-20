"""End-to-end checks for rendering verified Lake target manifests.

Prerequisite: lake build Test:proofscriptExport.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / ".ProofScript"
SITE = ROOT / ".PS4HTML/build/Test"
MODULES = EXPORT / "manifests/targets/ProofScript/Test/module"
LIBRARY = EXPORT / "manifests/targets/ProofScript/Test/library/Test.json"
MODULE = "Test.PageTheoremExpressionBoundaries"
sys.path.insert(0, str(ROOT / "tools/ps4html"))

from PS4HTML.page import Page, build_label_index
from PS4HTML.engine import render_details, render_module_navigation, render_page, render_proof
from PS4HTML.module_protocol import _publish_library_navigation
from PS4HTML.project import PS4HTMLError
from PS4HTML.Rules.media import render_figure


def render(manifest):
    env = dict(os.environ, PYTHONPATH=str(ROOT / "tools/ps4html"))
    return subprocess.run([sys.executable, "-m", "PS4HTML", "_render-target", str(manifest)],
                          cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)


class ModuleRenderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["lake", "build", f"+{MODULE}:proofscriptExport"],
                       cwd=ROOT, capture_output=True, text=True, timeout=600, check=True)

    def test_theorem_labels_use_exported_identity(self):
        component = {"data": {"theorem": {"value": {
            "declaration": ["OtherNamespace", "name.with.dots", 3],
            "proof": {"$resource": {"path": ".ProofScript/proofs/Test/Opaque.json"}},
        }}}}
        page = Page(Path("pages/Test/Page.json"), "Test.Page", Path("Test/Page.lean"),
                    [component], Path("Test/Page.json"))
        labels = build_label_index([page])
        target = labels[("theorem", "OtherNamespace.«name.with.dots».3")]
        self.assertEqual(target.anchor, "theorem-OtherNamespace.«name.with.dots».3")
        self.assertEqual(target.output_path, Path("Test/Page.html"))
        self.assertEqual(len(labels), 1)

    def test_layout_does_not_indent_preformatted_code(self):
        code = "first\n  second\nthird"
        blocks = (
            f'<pre class="page-code"><code>{code}</code></pre>',
            f'<pre class="verso-source"><code class="hl lean block">{code}</code></pre>',
            f'<pre><code>{code}</code></pre>',
        )
        proof = render_proof("", "example", render_details(True, "", "Details", blocks[0]), 3, blocks[1])
        page = render_page("Example", proof + blocks[2], "index.html")
        for block in blocks:
            self.assertIn(block, page)

    def test_figures_require_verified_exported_resources(self):
        with tempfile.TemporaryDirectory() as temporary:
            exported = Path(temporary) / ".ProofScript"
            source = exported / "resources/figure.svg"
            source.parent.mkdir(parents=True)
            content = b'<svg xmlns="http://www.w3.org/2000/svg"/>'
            source.write_bytes(content)
            descriptor = {"path": ".ProofScript/resources/figure.svg",
                          "hash": hashlib.sha256(content).hexdigest(),
                          "mediaType": "application/octet-stream", "encoding": "binary",
                          "byteSize": len(content)}
            value = {"metadata": {"title": "Figure"}, "path": descriptor["path"], "extension": "svg",
                     "resource": {"$resource": descriptor}}
            html, diagnostics = render_figure(value, exported)
            self.assertIn("data:image/svg+xml;base64,", html)
            self.assertEqual(diagnostics, [])
            with self.assertRaisesRegex(PS4HTMLError, "no matching exported resource"):
                render_figure({key: item for key, item in value.items() if key != "resource"}, exported)
            source.write_bytes(content + b" ")
            with self.assertRaisesRegex(PS4HTMLError, "hash mismatch"):
                render_figure(value, exported)

    def test_single_module_scope_and_frozen_proof(self):
        result = render(MODULES / (MODULE + ".json"))
        self.assertEqual(result.returncode, 0, result.stderr)
        page = (SITE / "Test/PageTheoremExpressionBoundaries.html").read_text()
        self.assertIn("theorem-PageTheoremExpressionBoundaries.boundary_wrapper_alias", page)
        self.assertIn("theorem-PageTheoremExpressionBoundaries.boundary_string_layout", page)
        self.assertFalse((SITE / "Test/PageTitle.html").exists())
        self.assertIn('class="hl lean block"', page)
        self.assertNotIn('<pre><code>', page)
        self.assertIn('id="ps-verso-data"', page)

    def test_verso_failure_keeps_previous_site(self):
        manifest = MODULES / (MODULE + ".json")
        self.assertEqual(render(manifest).returncode, 0)
        page = SITE / "Test/PageTheoremExpressionBoundaries.html"
        original = page.read_bytes()
        env = dict(os.environ, PYTHONPATH=str(ROOT / "tools/ps4html"),
                   PROOF_SCRIPT_VERSO_RENDERER=str(ROOT / ".lake/build/bin/does-not-exist"))
        result = subprocess.run([sys.executable, "-m", "PS4HTML", "_render-target", str(manifest)],
                                cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Verso renderer executable missing", result.stderr)
        self.assertEqual(page.read_bytes(), original)

    def test_failure_keeps_previous_site(self):
        manifest = MODULES / (MODULE + ".json")
        result = render(manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        home = SITE / "index.html"
        page = SITE / "Test/PageTheoremExpressionBoundaries.html"
        before = (home.read_bytes(), page.read_bytes())
        bad = EXPORT / "manifests/modules/Test/PageTheoremExpressionBoundaries.json"
        original = bad.read_bytes()
        try:
            bad.write_bytes(original + b" ")
            result = render(manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("digest mismatch", result.stderr)
            self.assertEqual((home.read_bytes(), page.read_bytes()), before)
        finally:
            bad.write_bytes(original)

    def test_current_template_contract_is_published(self):
        result = render(MODULES / (MODULE + ".json"))
        self.assertEqual(result.returncode, 0, result.stderr)
        page = (SITE / "Test/PageTheoremExpressionBoundaries.html").read_text()
        data = json.loads(re.search(r'<script[^>]*id="ps-expression-data"[^>]*>(.*?)</script>',
                                    page, re.S)[1])
        self.assertTrue(data["renderRoots"])
        templates = [template for root in data["renderRoots"].values()
                     for entry in root["catalog"].values() if entry["kind"] != "builtin"
                     for template in entry["templates"]]
        self.assertTrue(templates)
        self.assertTrue(all("argumentIndices" in template and "instructions" in template
                            for template in templates))
        self.assertTrue(any(template["label"] == "$infixl" for template in templates))
        info = json.loads((EXPORT / "info/Test/PageTheoremExpressionBoundaries.json").read_text())
        self.assertEqual(info["module"], ["Test", "PageTheoremExpressionBoundaries"])
        self.assertTrue(all(record["identity"]["kind"] in ("decl", "script")
                            for record in info["records"]))

    def test_library_scope(self):
        result = render(LIBRARY)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ("PageTitle", "ClassicalFormula", "PageTheoremExpressionGallery",
                     "PageTheoremExpressionInteractions", "PageTheoremExpressionBoundaries", "PageScriptBoard"):
            self.assertTrue((SITE / f"Test/{name}.html").is_file(), name)
        self.assertFalse((SITE / "Test/UnusedModule.html").exists())
        report = json.loads((SITE / "lean2tex-report.json").read_text())
        self.assertEqual(report["summary"]["total"], 0, report["summary"])

    def test_package_index_and_shared_assets(self):
        result = render(LIBRARY)
        self.assertEqual(result.returncode, 0, result.stderr)
        build = SITE.parent
        index = (build / "index.html").read_text()
        page = (SITE / "Test/PageTheoremExpressionBoundaries.html").read_text()
        self.assertIn("<title>ProofScript</title>", index)
        self.assertIn('class="module-sidebar"', index)
        self.assertIn('href="Test/index.html"', index)
        self.assertIn('href="./assets/css/layout.css"', index)
        self.assertIn('href="../assets/css/layout.css"', (SITE / "index.html").read_text())
        self.assertIn('href="../../assets/css/layout.css"', page)
        self.assertIn('ps4html-libraries-before:Test', page)
        self.assertNotIn('js/libraries.js', page)
        self.assertFalse((SITE / "assets").exists())

    def test_library_navigation_is_published_in_html(self):
        pages = [Page(Path("Test/Area.json"), "Test.Area", Path("Test/Area.lean"), [], Path("Test/Area.json"))]
        with tempfile.TemporaryDirectory() as temporary:
            build = Path(temporary)
            for library in ("Alpha", "Test", "Zeta"):
                (build / library / "Test").mkdir(parents=True)
                (build / library / "index.html").write_text("index", encoding="utf-8")
            output = build / "Test/Test/Area.html"
            navigation = render_module_navigation(pages, Path("Test/Area.html"), "Test.Area", "../../index.html")
            output.write_text(navigation, encoding="utf-8")
            _publish_library_navigation(build, ["Alpha", "Test", "Zeta"])
            content = output.read_text()
            self.assertLess(content.index('>Alpha</a>'), content.index('>Test</a>'))
            self.assertLess(content.index('>Test</a>'), content.index('>Zeta</a>'))
            self.assertIn('href="../../Alpha/index.html"', content)
            _publish_library_navigation(build, ["Alpha", "Test", "Zeta"])
            self.assertEqual(output.read_text(), content)
            (build / "Beta").mkdir()
            (build / "Beta/index.html").write_text("index", encoding="utf-8")
            _publish_library_navigation(build, ["Alpha", "Beta", "Test", "Zeta"])
            updated = output.read_text()
            self.assertLess(updated.index('>Alpha</a>'), updated.index('>Beta</a>'))
            self.assertLess(updated.index('>Beta</a>'), updated.index('>Test</a>'))
            self.assertEqual(updated.count('>Alpha</a>'), 1)


if __name__ == "__main__":
    unittest.main()
