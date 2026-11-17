"""Build and check the recorded Mathlib optimization page end to end."""

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INFO = ROOT / ".ProofScript/info/Test/PageScriptBoard.json"
PAGE = ROOT / ".PS4HTML/build/Test/Test/PageScriptBoard.html"
ASSETS = ROOT / ".PS4HTML/build/assets"
PROOFS = ROOT / ".ProofScript/proofs/Test/PageScriptBoard"


def steps_in(steps):
    for step in steps:
        yield step
        for branch in step.get("$branches", []):
            yield from steps_in(branch["proof"])


def proof_for(name):
    return json.loads(next(PROOFS.rglob(f"{name}.json")).read_text())


class ScriptBoardIntegrationTest(unittest.TestCase):
    def test_lake_export_and_page(self):
        built = subprocess.run(["lake", "build", "+Test.PageScriptBoard:ps4html"],
                               cwd=ROOT, capture_output=True, text=True, timeout=240)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)

        records = json.loads(INFO.read_text())["records"]
        scripts = {record["identity"]["target"][-1]: record["value"]
                   for record in records if record["identity"]["kind"] == "script"}
        for rule, fields in {
            "boardSimp": {"requested_rules", "location", "used_lemmas", "duration_ns"},
            "boardLinear": {"premises", "conclusion", "proof_dependencies", "duration_ns"},
            "norm_num": {"verification", "duration_ns"},
        }.items():
            self.assertEqual({entry["value"] for entry in scripts[rule]["board"]}, fields)
            self.assertTrue(scripts[rule]["templates"])

        upper = proof_for("board_upper_bound")
        equality = proof_for("board_equality")
        optimum = proof_for("board_optimum")
        self.assertEqual([s["$ruleId"] for s in upper["proof"]],
                         ["unpack_and", "boardCases"])
        cases = upper["proof"][1]["$branches"]
        self.assertEqual({branch["name"] for branch in cases},
                         {"nonnegative", "negative"})
        self.assertIn("h", upper["proof"][0]["$context_before"])
        self.assertNotIn("h", upper["proof"][0]["$context_after"])
        self.assertTrue({"hx", "hy", "h₁", "h₂"}.issubset(
            upper["proof"][0]["$context_after"]))

        for document in (upper, equality, optimum):
            for step in steps_in(document["proof"]):
                self.assertIsInstance(step["$time_before"], int)
                self.assertIsInstance(step["$time_after"], int)
                self.assertLessEqual(step["$time_before"], step["$time_after"])
                if step["$ruleId"] in {"unpack_and", "boardCases", "boardSimp",
                                       "boardLinear", "norm_num"}:
                    self.assertIsInstance(step["duration_ns"], int, step["$ruleId"])
                    self.assertGreaterEqual(step["duration_ns"], 0)
                if step["$ruleId"] == "boardSimp":
                    self.assertTrue(step["used_lemmas"])
                    self.assertTrue(any("abs_of_" in lemma for lemma in step["used_lemmas"])
                                    or "heqx" in step["requested_rules"])
                    self.assertIn("$goal_before", step)
                    self.assertIn("$context_after", step)
                if step["$ruleId"] == "boardLinear":
                    self.assertTrue(step["premises"])
                    self.assertEqual(step["$goal_after"], None)
                    self.assertIn("$ref", step["conclusion"])
                    self.assertTrue(set(step["proof_dependencies"]).issubset(
                        step["$context_before"]))
                    self.assertTrue(set(step["proof_dependencies"]) & set(step["premises"]))
                if step["$ruleId"] == "norm_num":
                    self.assertIn("$ref", step["verification"])
                    self.assertIsNone(step["$goal_after"])

        self.assertEqual([step["$ruleId"] for step in optimum["proof"]], ["norm_num"])
        self.assertIn(["proof", 0, "verification"], optimum["expressionRoots"])
        self.assertIn(["proof", 0, "$context_before", "h"], upper["expressionRoots"])

        svg_proof = proof_for("svg_renderer_example")
        raw_svg, compiled_svg = svg_proof["proof"][:2]
        self.assertEqual(raw_svg["metadata"]["title"], "SVG example")
        self.assertIn("<svg", raw_svg["code"])
        self.assertNotIn("source", raw_svg)
        self.assertEqual(compiled_svg["metadata"]["title"], "LaTeX example")
        self.assertIn("<svg", compiled_svg["code"])
        self.assertEqual(compiled_svg["source"], {"lang": "latex", "code": "\\(P\\)"})

        page = PAGE.read_text()
        for text in ("board_upper_bound", "board_equality", "board_optimum",
                     "实际使用的引理", "输入算术事实", "证明项依赖的局部命题",
                     "执行耗时（纳秒）", "原状态", "新状态", "Original state", "New state"):
            self.assertIn(text, page)
        self.assertIn('class="proof-step-header" role="button" tabindex="0"', page)
        self.assertIn('class="proof-dashboard-reveal"', page)
        self.assertIn('aria-expanded="false"', page)
        self.assertIn('aria-hidden="true" inert', page)
        self.assertIn('class="proof-dashboard-marker removed"', page)
        self.assertIn('data-ps-render-root=', page)
        self.assertIn('href="../../assets/css/proof-dashboard.css"', page)
        self.assertIn('src="../../assets/js/proof-dashboard.js"', page)
        self.assertTrue((ASSETS / "css/proof-dashboard.css").is_file())
        self.assertTrue((ASSETS / "js/proof-dashboard.js").is_file())
        self.assertIn('page-media page-media-svg', page)
        self.assertIn('page-media page-media-latex', page)
        self.assertIn('class="code-header"><span>latex</span>', page)
        self.assertNotIn('diagram-figure', page)
        self.assertNotIn('css/diagram.css', page)
        self.assertNotIn('js/diagram.js', page)
        dynamic = proof_for("dynamic_strategy_example")
        self.assertEqual(len(dynamic["proof"][0]["$branches"]), 3)
        self.assertEqual(scripts["splitAnd!"]["renderer"], "default")
        self.assertEqual(scripts["splitAnd!"]["templates"][0]["kind"], "dynamicStrategy")
        self.assertIn('data-ps-render-root=', page)
        self.assertIn('子目标 <span data-ps-render-root=', page)
        self.assertIn('Subgoal <span data-ps-render-root=', page)
        interaction_data = json.loads(page.split('id="ps-expression-data">', 1)[1].split('</script>', 1)[0])
        number_roots = [root for root in interaction_data["renderRoots"].values()
                        if root["tree"]["kind"] == "literal" and
                        root["tree"]["metadata"].get("literalKind") == "literal.nat" and
                        root["tree"].get("generated")]
        self.assertGreaterEqual(len(number_roots), 3)
        self.assertEqual({"1", "2", "3"}, {root["tree"]["name"] for root in number_roots})
        self.assertEqual(number_roots[0]["tree"]["metadata"]["styles"]["roman"], "\\mathrm{I}")
        self.assertIn('["builtin", "literal.nat"]', number_roots[0]["catalog"])


if __name__ == "__main__":
    unittest.main()
