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
                               cwd=ROOT, capture_output=True, text=True, timeout=600)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)

        records = json.loads(INFO.read_text())["records"]
        scripts = {record["identity"]["target"][-1]: record["value"]
                   for record in records if record["identity"]["kind"] == "script"}
        for rule, fields in {
            "boardSimp": {"requested_rules", "location", "used_lemmas", "duration_ns"},
            "boardLinear": {"premises_names", "premises_types", "conclusion", "proof_dependencies", "duration_ns"},
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
        self.assertIn("h", [item["value"] for item in upper["proof"][0]["$context_names_before"]["value"]])
        self.assertNotIn("h", [item["value"] for item in upper["proof"][0]["$context_names_after"]["value"]])
        self.assertTrue({"hx", "hy", "h₁", "h₂"}.issubset(
            {item["value"] for item in upper["proof"][0]["$context_names_after"]["value"]}))

        for document in (upper, equality, optimum):
            for step in steps_in(document["proof"]):
                self.assertEqual(step["$time_before"]["kind"], "plain")
                self.assertEqual(step["$time_after"]["kind"], "plain")
                self.assertLessEqual(step["$time_before"]["value"], step["$time_after"]["value"])
                if step["$ruleId"] in {"unpack_and", "boardCases", "boardSimp",
                                       "boardLinear", "norm_num"}:
                    self.assertIsInstance(step["duration_ns"]["value"], int, step["$ruleId"])
                    self.assertGreaterEqual(step["duration_ns"]["value"], 0)
                if step["$ruleId"] == "boardSimp":
                    self.assertTrue(step["used_lemmas"]["value"])
                    self.assertTrue(any("abs_of_" in lemma["value"] for lemma in step["used_lemmas"]["value"])
                                    or "heqx" in step["requested_rules"]["value"])
                    self.assertIn("$goal_before", step)
                    self.assertIn("$context_names_after", step)
                if step["$ruleId"] == "boardLinear":
                    self.assertTrue(step["premises_names"]["value"])
                    self.assertEqual(step["$goal_after"], {"kind": "plain", "value": "completed"})
                    self.assertIn("$ref", step["conclusion"]["value"])
                    dependencies = {item["value"] for item in step["proof_dependencies"]["value"]}
                    context_names = {item["value"] for item in step["$context_names_before"]["value"]}
                    premises = {item["value"] for item in step["premises_names"]["value"]}
                    self.assertTrue(dependencies.issubset(context_names))
                    self.assertTrue(dependencies & premises)
                if step["$ruleId"] == "norm_num":
                    self.assertIn("$ref", step["verification"]["value"])
                    self.assertEqual(step["$goal_after"], {"kind": "plain", "value": "completed"})

        self.assertEqual([step["$ruleId"] for step in optimum["proof"]], ["norm_num"])
        self.assertIn(["proof", 0, "verification", "value"], optimum["expressionRoots"])
        self.assertIn(["proof", 0, "$context_types_before", "value", 0, "value"], upper["expressionRoots"])

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
        self.assertNotIn('diagram-figure', page)
        self.assertNotIn('css/diagram.css', page)
        self.assertNotIn('js/diagram.js', page)
        interaction_data = json.loads(page.split('id="ps-expression-data">', 1)[1].split('</script>', 1)[0])
        self.assertTrue(interaction_data["renderRoots"])


if __name__ == "__main__":
    unittest.main()
