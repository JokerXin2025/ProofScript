from pathlib import Path
import re
import unittest


PAGE = (Path(__file__).resolve().parent.parent / ".PS4HTML" / "build" /
        "ProofScript" / "Test" / "Test" / "LatexComponentsTest.html")


class LatexPresentationTest(unittest.TestCase):
    def test_inline_latex_has_zoom_without_its_own_flip(self):
        html = PAGE.read_text(encoding="utf-8")
        figures = re.findall(r'<figure class="diagram-figure inline-latex-figure".*?</figure>',
                             html, re.DOTALL)
        self.assertEqual(len(figures), 6)  # Three inline figures in each language.
        for figure in figures:
            self.assertIn('class="diagram-zoom"', figure)
            self.assertIn('max="400" value="100"', figure)
            self.assertIn('class="diagram-zoom-stage"', figure)
            self.assertIn('<svg xmlns="http://www.w3.org/2000/svg"', figure)
            self.assertNotIn('<ns0:svg', figure)
            self.assertNotIn('<img ', figure)
            self.assertNotIn('class="flip-btn', figure)
        self.assertEqual(html.count('class="flip-btn page-media-flip-button"'), 1)


if __name__ == "__main__":
    unittest.main()
