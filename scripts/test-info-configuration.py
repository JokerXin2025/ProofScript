#!/usr/bin/env python3
"""Frozen declaration names are adapted from a module's exported records."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from Lean2TeX.configuration import interpret


def definition(name):
    return {"name": name, "var_name": "", "kind": "concept",
            "parameter_template": None, "alias_info": {"target": None},
            "concept_info": {"templates": []}}


def theorem(name):
    return {"name": name, "tags": []}


class FrozenNamesTest(unittest.TestCase):
    def test_module_records_select_names_without_expression_metadata(self):
        config = interpret({("definition", "Names.value"): definition("Earlier value"),
                            ("theorem", "Names.result"): theorem("Earlier theorem")})
        self.assertEqual(config.definition_names["Names.value"], "Earlier value")
        self.assertEqual(config.theorem_names["Names.result"], "Earlier theorem")
        defaults = interpret({("definition", "Names.value"): definition(""),
                              ("theorem", "Names.result"): theorem("")})
        self.assertEqual(defaults.definition_names["Names.value"], "Names.value")
        self.assertEqual(defaults.theorem_names["Names.result"], "Names.result")
        self.assertEqual(defaults.variable_prefixes["Names.value"], "")


if __name__ == "__main__":
    unittest.main()
