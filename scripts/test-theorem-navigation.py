#!/usr/bin/env python3
"""Dependency labels use frozen Info even without a theorem page destination."""

from pathlib import Path
from types import SimpleNamespace
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/ps4html"))

from PS4HTML.info import RefInfo, TheoremRecord
from PS4HTML.page import Page, PageRenderer
from PS4HTML.theorem_graph import TheoremDestination, TheoremGraph


class TheoremNavigationTests(unittest.TestCase):
    def setUp(self):
        self.owner = ("Test", "Page")
        self.auxiliary = ("Aux", "taylor")
        self.record = TheoremRecord(("result",), "theorem", "project",
            (RefInfo(self.auxiliary, True),), (self.auxiliary,), self.owner, "proof.json")
        self.names = {"Aux.taylor": [
            {"lang": "zh", "value": "泰勒公式"},
            {"lang": "en", "value": "Taylor's formula"},
        ]}
        self.page = Page(Path("page.json"), "Test.Page", Path("Test/Page.lean"),
                         [{"data": {"theorem": {"value": {"proof": {}}}}}], Path("Test/Page.json"))

    def render(self, language, *, destination=None):
        records = [self.record]
        destinations = {}
        if destination is not None:
            records.append(TheoremRecord(self.auxiliary, "theorem", "project", (), (),
                                          ("Aux", "Page"), "auxiliary.json"))
            destinations[("project", self.auxiliary)] = destination
        graph = TheoremGraph(records, destinations=destinations)

        def configuration(owner):
            self.assertEqual(owner, self.owner)
            return SimpleNamespace(declaration_names=self.names)

        bundle = SimpleNamespace(theorem=lambda _: self.record, configuration=configuration)
        renderer = PageRenderer(ROOT, ROOT / ".PS4HTML/build/Test", {}, [self.page],
                                theorem_graph=graph, bundle=bundle, verso=object())
        return renderer._theorem_navigation_panel(self.page, self.page.output_path, language)

    def test_unlinked_dependency_uses_owners_localized_names(self):
        rendered = self.render("zh")
        self.assertIn("泰勒公式</span>", rendered)
        self.assertIn('title="Aux.taylor"', rendered)
        self.assertNotIn(">Aux.taylor</span>", rendered)
        self.assertIn("Taylor&#x27;s formula</span>", self.render("en"))

    def test_missing_configuration_keeps_lean_name(self):
        self.names.clear()
        self.assertIn("Aux.taylor</span>", self.render("zh"))

    def test_page_destination_retains_its_own_title(self):
        destination = TheoremDestination(Path("Aux/Page.html"), "theorem-Aux.taylor",
            [{"lang": "zh", "value": "辅助页面的标题"}], "taylor", 0)
        rendered = self.render("zh", destination=destination)
        self.assertIn("辅助页面的标题</span>", rendered)
        self.assertNotIn(">泰勒公式</span>", rendered)


if __name__ == "__main__":
    unittest.main()
