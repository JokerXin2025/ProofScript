"""The frozen board wire format preserves order and duplicate display names."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ps4html"))

from PS4HTML.recording import PROOF_SCHEMA_VERSION
from PS4HTML.render_rules import validate_rules


def document(board):
    return {"schemaVersion": PROOF_SCHEMA_VERSION, "module": "Test.ScriptBoard", "imports": [],
            "rules": [{"ruleId": "Test.board", "kind": "tactic",
                       "fields": {"renderer": "none", "display": True,
                                  "template": [{"lang": "zh", "tag": "步骤", "content": ""}],
                                  "board": board}}]}


class ScriptBoardProtocolTest(unittest.TestCase):
    def test_duplicate_names_and_literal_dotted_keys(self):
        board = [{"name": "使用的假设", "value": "h"},
                 {"name": "使用的假设", "value": "foo.bar"}]
        rules = validate_rules(document(board), "Test.ScriptBoard")
        self.assertEqual(rules["Test.board"]["fields"]["board"], board)

    def test_invalid_board_entries(self):
        for board in ({"name": "h"}, [{"name": "h"}],
                      [{"name": "h", "value": 2}],
                      [{"name": "h", "value": "x", "extra": "y"}]):
            with self.subTest(board=board), self.assertRaisesRegex(ValueError, "Invalid board"):
                validate_rules(document(board), "Test.ScriptBoard")


if __name__ == "__main__":
    unittest.main()
