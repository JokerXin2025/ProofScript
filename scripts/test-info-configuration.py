#!/usr/bin/env python3
"""Frozen declaration names are adapted from a module's exported records."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from Lean2TeX.configuration import interpret
from Lean2TeX.names import select_name
from Lean2TeX.names import validate_names


def definition(name, *, default_template=None, kind="concept", default=False):
    return {"names": [] if default else [{"lang": "zh", "value": name}],
            "tags": [], "var_name": "", "kind": kind, "wrapper_index": None,
            "alias_target": None, "templates": [], "default_template": default_template,
            "calc_symbol": None, "parameter_template": None, "extra": {}, "arity": 0,
             "binder_infos": [], "parameter_argument_indices": []}


class FrozenNamesTest(unittest.TestCase):
    def test_module_records_select_names_without_expression_metadata(self):
        config = interpret({("decl", "Names.value"): definition("Earlier value"),
                            ("decl", "Names.result"): definition("Earlier theorem", kind="theorem")})
        self.assertEqual(select_name(config.declaration_names["Names.value"], "zh", "Names.value"), "Earlier value")
        self.assertEqual(select_name(config.theorem_names["Names.result"][0], "zh", "Names.result", theorem=True), "Earlier theorem")
        defaults = interpret({("decl", "Names.value"): definition("Names.value", default_template=None, default=True),
                              ("decl", "Names.result"): definition("Names.result", kind="theorem", default=True)})
        self.assertEqual(select_name(defaults.declaration_names["Names.value"], "en", "Names.value"), "Names.value")
        self.assertEqual(select_name(defaults.theorem_names["Names.result"][0], "en", "Names.result", theorem=True), "result")
        self.assertEqual(defaults.variable_prefixes["Names.value"], "")
        self.assertIn("Names.result", defaults.registry.theorems)
        self.assertNotIn("Names.value", defaults.registry.theorems)

    def test_language_fallbacks_and_tag_multiplicity(self):
        names = [{"lang": "zh", "value": "中文"}, {"lang": "en", "value": "English"}]
        self.assertEqual(select_name(names, "zh", "Names.result", theorem=True), "中文")
        self.assertEqual(select_name(names, "fr", "Names.result", theorem=True), "English")
        self.assertEqual(select_name([{"lang": None, "value": "Neutral"}], "zh", "Names.result"), "Neutral")
        self.assertEqual(select_name([{"lang": "zh", "value": "中文"}], "en", "Names.result", theorem=True), "result")
        self.assertEqual(select_name([], "en", "Names.result"), "Names.result")
        fields = definition("Example")
        fields["tags"] = [{"lang": "zh", "value": "重复"}, {"lang": "zh", "value": "重复"}]
        validate_names(fields, "Names.result")
        fields["names"].append({"lang": "zh", "value": "Duplicate"})
        with self.assertRaisesRegex(ValueError, "duplicate name language"):
            validate_names(fields, "Names.result")

    def test_old_export_requires_rebuild(self):
        fields = definition("Example")
        fields["name"] = "old"
        with self.assertRaisesRegex(ValueError, "rebuild exports"):
            interpret({("decl", "Names.result"): fields})


if __name__ == "__main__":
    unittest.main()
