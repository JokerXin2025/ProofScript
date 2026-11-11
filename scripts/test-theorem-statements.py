#!/usr/bin/env python3
"""Check exported theorem statements and their rendered expression identities."""

import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/ps4html"))

from Lean2TeX.configuration import interpret
from PS4HTML.engine import ProofEngine
from PS4HTML.info import name_text
from PS4HTML.schema import validate_document
from PS4HTML.statement import render_statement


def main():
    module = "Test.PageTheoremExpressionBoundaries"
    module_path = module.replace(".", "/")
    subprocess.run(["lake", "build", f"+{module}:ps4html"],
                   cwd=ROOT, check=True, capture_output=True, text=True, timeout=600)
    exported = ROOT / ".ProofScript"
    completion = json.loads((exported / f"manifests/modules/{module_path}.json").read_text())
    proofs = [exported / entry["path"] for entry in completion["files"]
              if entry["path"].startswith("proofs/")]
    assert proofs, "module export has no theorem proofs"
    page = json.loads((exported / f"pages/{module_path}.json").read_text())
    theorems = {}
    for component in page["components"]:
        for kind in ("theorem", "lemma"):
            if kind in component["data"]:
                value = component["data"][kind]["value"]
                theorems[value["proof"]["$resource"]["path"]] = (kind, value)
    info = json.loads((exported / f"info/{module_path}.json").read_text())
    values = {}
    for record in info["records"]:
        identity = record["identity"]
        if identity["kind"] not in ("definition", "theorem"):
            continue
        fields = {key: value for key, value in record["value"].items() if key != "extra"}
        if identity["kind"] == "definition" and fields["alias_info"]["target"] is not None:
            fields["alias_info"] = {"target": name_text(fields["alias_info"]["target"])}
        values[(identity["kind"], name_text(identity["target"]))] = fields
    configuration = interpret(values)
    recorded = native = 0
    for proof in proofs:
        document = json.loads(proof.read_text())
        resolver = validate_document(document, module_protocol=True)
        assert document["statement"]["parameters"] is not None
        assert "theoremFacts" not in document and "declaration" not in document
        kind, value = theorems[".ProofScript/" + proof.relative_to(exported).as_posix()]
        assert value["declaration"] and value["projectId"]
        assert isinstance(value["proofRefs"], list) and isinstance(value["proofDependencies"], list)
        assert kind in ("theorem", "lemma")
        engine = ProofEngine(document.get("proof", []), expression_resolver=resolver,
                             lean2tex_config=configuration)
        rendered = render_statement(document["statement"], engine)
        assert "statement-conclusion" in rendered, proof
        assert document["expressionRoots"] and document["expressions"], proof
        if "proof" in document:
            recorded += 1
        else:
            native += 1
    assert native, (recorded, native)
    site = ROOT / f".PS4HTML/build/Test/{module_path}.html"
    html = site.read_text()
    assert html.count("theorem-statement") >= recorded + native
    print(f"PASS {recorded} recorded and {native} native theorem statements from module export")


if __name__ == "__main__":
    main()
