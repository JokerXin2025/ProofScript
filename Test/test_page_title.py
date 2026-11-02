#!/usr/bin/env python3
"""Check the real Lean title gallery, heading references and rendered depth markers.

Run after `lake build ProofScript`: python3 Test/test_page_title.py.
"""

import dataclasses
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/ps4html"))

from PS4HTML.page import Page, build_label_index
from PS4HTML.project import PS4HTMLError
from PS4HTML.Rules.proof_text import ProofTextRenderer
from PS4HTML.Rules.title import TitleRenderer


def main():
    with tempfile.TemporaryDirectory(prefix="proofscript-title-") as directory:
        work = Path(directory)
        source = work / "PageTitle.lean"
        output = work / "page.json"
        source.write_text((ROOT / "Test/PageTitle.lean").read_text() + '''
run_cmd do
  let some page := modulePageDraft? (← getEnv) (← getMainModule)
    | throwError "missing title page"
  liftIO <| IO.FS.writeFile OUTPUT (toJson page).pretty
'''.replace("OUTPUT", json.dumps(str(output))))
        env = dict(os.environ, PROOF_SCRIPT_OUTPUT_ROOT=str(work / "output"))
        subprocess.run(["lake", "env", "lean", f"--root={work}", str(source)],
                       cwd=ROOT, env=env, check=True)
        components = json.loads(output.read_text())["components"]
        page = Page(output, "Test.PageTitle", source, components)
        labels = build_label_index([page])
        assert len(labels) == 7, labels
        for (kind, label), target in labels.items():
            assert kind == "heading" and target.anchor == f"heading-{label}"
            line = source.read_text().splitlines()[target.line - 1]
            # A multiline command starts on #page; the labeled text can follow it.
            assert line.startswith("#page "), (label, target.line, line)
        assert labels[("heading", "after-text")].line > labels[("heading", "title-eight")].line

        rendered = []
        for component in components:
            tag, envelope = next(iter(component["data"].items()))
            renderer = TitleRenderer if tag == "title" else ProofTextRenderer
            rendered.append(renderer(labels, work, page.output_path).render(envelope["value"]))
        tree = ET.fromstring("<article>" + "\n".join(rendered) + "</article>")
        titles = tree.findall("./*[@data-title-level]")
        levels = [1, 2, 3, 4, 5, 6, 7, 8, 2, 64, 2]
        assert [int(title.get("data-title-level")) for title in titles] == levels
        for title, level in zip(titles, levels):
            assert title.tag == f"h{min(5, level)}"
            arrows = title.find("./span[@class='page-title-depth']")
            if level <= 5:
                assert arrows is None
            else:
                assert arrows is not None and arrows.text == "→" * (level - 5)
                assert arrows.get("aria-hidden") == "true"
                assert title.get("aria-level") == str(level)
        assert titles[0].find("strong") is not None
        assert "$x^2$" in "".join(titles[0].itertext())
        for section in tree.findall("./section"):
            assert not any(node.tag in {"h1", "h2", "h3", "h4", "h5", "h6"}
                           for node in section.iter())
        assert any("= 普通段落 <title-main>\n= 这行仍属于同一段落" == "".join(p.itertext())
                   for p in tree.findall(".//p"))
        assert any(mark.text == "段落开头的高亮" for mark in tree.findall(".//mark/span"))
        links = [link.get("href") for link in tree.findall(".//a")]
        assert "PageTitle.html#heading-title-six" in links
        assert "PageTitle.html#heading-after-text" in links
        assert tree.find(".//*[@class='unresolved-reference']") is None

        # The same exported title resolves from a different page with the correct relative URL.
        foreign = dataclasses.replace(page, module="Other.Page")
        foreign_html = ProofTextRenderer(labels, work, foreign.output_path).render({
            "blocks": [{"paragraph": {"content": [{
                "reference": {"kind": "heading", "label": "title-main"}
            }]}}]
        })
        assert '../Test/PageTitle.html#heading-title-main' in foreign_html
        try:
            build_label_index([page, foreign])
        except PS4HTMLError as error:
            assert "Duplicate heading label" in str(error)
        else:
            raise AssertionError("duplicate cross-page title labels were accepted")

        # Ordinary verification skips both title branches' content validation.
        verification = work / "Verification.lean"
        verification.write_text('''import ProofScript.Page.Command
import ProofScript.Extensions.Title
open Lean Elab Command ProofScript
#page title (label := "2-invalid") "*unclosed"
#page sub sub title (label := "also.invalid") "*unclosed"
run_cmd do
  unless (getPageState (← getEnv)).components.isEmpty do
    throwError "verification registered title components"
#page end
/-- error: page component appears after #page end -/
#guard_msgs in
#page sub title "closed"
''')
        subprocess.run(["lake", "env", "lean", f"--root={work}", str(verification)],
                       cwd=ROOT, env=env, check=True)
        print("PASS title levels, arrows, inline formatting, references, removed ProofText headings and gating")


if __name__ == "__main__":
    main()
