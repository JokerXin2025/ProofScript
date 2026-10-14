import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parent.parent
PROOFS = ROOT / ".ProofScript" / "proofs" / "Test" / "StrategyPresentationPage"
PAGE = ROOT / ".PS4HTML" / "build" / "ProofScript" / "Test" / "Test" / "StrategyPresentationPage.html"


class StrategyPresentationTest(unittest.TestCase):
    def test_recorded_facts_and_branch_identity(self):
        expected = {
            "strategyInduction": ("induction", "n", ("zero", "succ")),
            "strategyCompleteInduction": ("complete_induction", "n", ("zero", "succ")),
            "strategyContra": ("contra", "hypothesis", ("proof",)),
            "strategyWitness": ("witness", None, ("data", "proof")),
            "strategyCases": ("cases_by", "subject", ("left", "right")),
            "strategyConstructor": ("constructor", None, ("left", "right")),
            "strategyNamedConstructor": ("constructor!", None, ("left", "right")),
        }
        for name, (strategy, field, branches) in expected.items():
            with self.subTest(name=name):
                document = json.loads((PROOFS / f"{name}.json").read_text(encoding="utf-8"))
                node = document["proof"][1]
                self.assertEqual(node["_ruleId"], f"ProofScript.Script.Basic.{strategy}")
                self.assertNotIn("name", node)
                self.assertNotIn("info", node)
                self.assertNotIn("_pending_strategy_", node)
                self.assertEqual(tuple(branch["name"] for branch in node["branches"]), branches)
                if field:
                    reference = node[field]["$ref"]
                    self.assertIn(reference, document["expressions"])
        for name, head in (("strategyContra", "And"), ("strategyCases", "Or")):
            document = json.loads((PROOFS / f"{name}.json").read_text(encoding="utf-8"))
            field = "hypothesis" if name == "strategyContra" else "subject"
            expression = document["expressions"][document["proof"][1][field]["$ref"]]
            self.assertEqual(expression["headConstant"], head)

    def test_bilingual_layout_from_real_export(self):
        html = PAGE.read_text(encoding="utf-8")
        for value in ("归纳对象", "基础情形", "归纳步骤", "On the induction variable,",
                      "In the base case,", "In the inductive step,", "分类依据", "情形 I",
                      "As the case distinction,", "In Case I,", "子目标 I", "Subgoal I,",
                       "反证法", "For the contrary assumption,", "强数学归纳法",
                       "By strong induction,", "Constructor layout", "Named constructor layout"):
            with self.subTest(value=value):
                self.assertIn(value, html)
        self.assertIn("--rule-tag-color: #2b6a4a", html)
        self.assertIn("--rule-tag-color: #a33b45", html)
        self.assertIn("--rule-tag-color: #166a80", html)
        self.assertIn("--rule-tag-color: #61519a", html)
        self.assertIn("--rule-tag-color: #a26423", html)
        self.assertIn('<div class="strategy-block " style="--rule-tag-color: #a26423', html)
        self.assertLess(html.index("基础情形"), html.index("归纳步骤"))
        self.assertLess(html.index("子目标 I"), html.index("子目标 II"))


if __name__ == "__main__":
    unittest.main()
