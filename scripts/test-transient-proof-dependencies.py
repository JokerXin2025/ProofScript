#!/usr/bin/env python3
"""Export nested tactic proofs and check their final declaration Info."""

import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/ps4html"))

from PS4HTML.info import name_text


def main():
    module = "Test.TransientProofDependencies"
    module_path = module.replace(".", "/")
    result = subprocess.run(
        ["lake", "build", f"+{module}:ps4html"], cwd=ROOT,
        capture_output=True, text=True, timeout=600,
    )
    assert result.returncode == 0, result.stdout + result.stderr

    exported = ROOT / ".ProofScript"
    info = json.loads((exported / f"info/{module_path}.json").read_text())
    declarations = {
        name_text(record["identity"]["target"])
        for record in info["records"] if record["identity"]["kind"] == "decl"
    }
    for name in ("nested_grind", "user_dependencies", "publicValue", "proof_1"):
        assert f"TransientProofDependencies.{name}" in declarations, declarations
    assert any(name.endswith(".TransientProofDependencies.privateValue")
               for name in declarations), declarations
    assert not any("._proof_" in name or "._hyg" in name
                   for name in declarations), declarations

    completion = json.loads(
        (exported / f"manifests/modules/{module_path}.json").read_text()
    )
    proofs = [exported / entry["path"] for entry in completion["files"]
              if entry["path"].startswith("proofs/")]
    assert len(proofs) == 2, proofs
    for path in proofs:
        assert json.loads(path.read_text())["proof"], path
    site = ROOT / f".PS4HTML/build/Test/{module_path}.html"
    assert site.is_file(), site
    print("PASS transient proof auxiliaries excluded; user and private declaration Info retained")


if __name__ == "__main__":
    main()
