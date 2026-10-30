#!/usr/bin/env python3
"""Real Lean capture -> expression ownership -> statement HTML and shared fvar IDs."""
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/ps4html"))
from Lean2TeX.configuration import EffectiveConfiguration, interpret
from Lean2TeX.macros import MacroRegistry
from PS4HTML.engine import ProofEngine, render_proof
from PS4HTML.schema import validate_document
from PS4HTML.statement import render_statement
from PS4HTML.project import PS4HTMLError
from PS4HTML.info import name_text
from PS4HTML.page import _render_code_only_declaration
from jsonschema import Draft202012Validator


def main():
    with tempfile.TemporaryDirectory(prefix="statement-") as directory:
        work = Path(directory)
        source = work / "Statement.lean"
        source.write_text('''import ProofScript
import ProofScript.Info.Snapshot
def_info Real { parameter_template := some "$#self\\\\in\\\\mathbb{R}$", styles := [{ template := "\\\\mathbb{R}" }] }
def_info Set { parameter_template := some "$#self\\\\subseteq #0$", styles := [{ template := "\\\\mathcal{P}(#0)" }] }
def_info Set.Icc { styles := [{ template := "[#0,#1]" }] }
def_info Set.Elem { parameter_template := some "$#self\\\\in #0$", styles := [{ template := "#0" }] }
namespace Statement
#page theorem identity (n : Nat) (h : n = n) : n = n := script
  trivial
#page theorem interval (a b : Real) (x : Set.Icc a b) (s : Set Real)
    (f : Real → Real) : x = x := script
  trivial
#page theorem native (n : Nat) (h : n = n) : n = n := by
  exact h
#page lemma nativeLemma (n : Nat) : n = n := by
  rfl
end Statement
open Lean Elab Command ProofScript in
run_cmd do
  let deps := #[`Nat, `Real, `Set, `Set.Icc, `Set.Elem, `Eq].map fun name =>
    { kind := "definition", target := Sum.inl name : RenderDependency }
  let snapshot ← match freezeSnapshot (← getEnv) { moduleName := ← getMainModule } deps #[] with
    | .ok value => pure value
    | .error error => throwError error.render
  liftIO <| IO.FS.writeFile SNAPSHOT snapshot.payload.pretty
'''.replace('SNAPSHOT', json.dumps(str(work / 'snapshot.json'))))
        env = dict(os.environ, PROOF_SCRIPT_OUTPUT_ROOT=str(work / "output"))
        subprocess.run(["lake", "env", "lean", f"--root={work}",
                        "-DproofScript.pageBuild=true", str(source)], cwd=ROOT, env=env, check=True)
        proofs = list((work / "output").rglob("*.json"))
        documents = [data for path in proofs if "statement" in (data := json.loads(path.read_text()))]
        schema = json.loads((ROOT / 'docs/schema/recording-proof.schema.json').read_text())
        for data in documents:
            Draft202012Validator(schema).validate(data)
        document = next(data for data in documents if 'identity' in data['code'])
        resolver = validate_document(document)
        config = EffectiveConfiguration(MacroRegistry(), {}, {"Nat": (r"$#self\in\mathbb{N}$", [])})
        engine = ProofEngine(document["proof"], expression_resolver=resolver, lean2tex_config=config)
        text = render_statement(document["statement"], engine)
        assert 'statement-parameters' in text and 'statement-conditions' in text
        assert text.count('statement-conclusion') == 1
        refs = re.findall(r"l2t-ref=(f-[0-9a-f]+)", text)
        assert refs and refs.count(refs[0]) >= 3, text
        statement = resolver.resolve(document["statement"])
        ordinary = engine.tex(statement["parameters"][0]["variable"])
        assert refs[0] in ordinary and "mathbb" not in ordinary
        rendered = render_proof("", "Identity", "proof", "Statement.lean", 4, "", statement=text)
        assert rendered.index('proof-flip-front') < rendered.index('theorem-statement') < rendered.index('proof-children')
        # Real recorded goal occurrences use the same fvar IDs as the header.
        proof_text = "".join(engine.tex(resolver.node(document["proof"][path[1]][path[2]]))
                             for path in resolver.roots if len(path) == 3 and path[0] == "proof")
        assert refs[0] in proof_text
        fn_type = {"kind": "forall", "name": "x", "binderInfo": "default",
                   "type": {"kind": "const", "name": "Nat", "levels": []},
                   "body": {"kind": "const", "name": "Nat", "levels": []}}
        function = engine.renderer.render_parameter(statement["parameters"][0]["variable"], fn_type)
        assert r"\to" in function and r"\implies" not in function
        records = json.loads((work / "snapshot.json").read_text())["records"]
        values = {(record['identity']['kind'], name_text(record['identity']['target'])): record['value'] for record in records}
        real_config = interpret(values)
        interval = next(data for data in documents if 'interval' in data['code'])
        interval_engine = ProofEngine(interval['proof'], expression_resolver=validate_document(interval), lean2tex_config=real_config)
        interval_html = render_statement(interval['statement'], interval_engine)
        assert r'\subseteq' in interval_html and r'\to' in interval_html and r'\in' in interval_html, interval_html
        assert '[missing' not in interval_html
        broken = copy.deepcopy(document)
        broken["expressionRoots"].remove(["statement", "conclusion"])
        try:
            validate_document(broken)
        except PS4HTMLError:
            pass
        else:
            raise AssertionError("unregistered statement expression accepted")
        for native in (data for data in documents if "proof" not in data):
            assert native['statement']['parameters']
            native_resolver = validate_document(native)
            native_engine = ProofEngine([], expression_resolver=native_resolver, lean2tex_config=real_config)
            native_html = _render_code_only_declaration('theorem', 'Native', 'native', 'rfl', 1, 'native',
                                                       render_statement(native['statement'], native_engine))
            assert native_html.index('theorem-statement') < native_html.index('proof-source-card')
        assert len([data for data in documents if "proof" not in data]) == 2
        for source in documents:
            broken = copy.deepcopy(source)
            del broken['statement']
            try:
                validate_document(broken)
            except PS4HTMLError:
                pass
            else:
                raise AssertionError('missing statement accepted')
        try:
            validate_document({"schemaVersion": "0.3.0", "module": "Old", "code": ""})
        except PS4HTMLError:
            pass
        else:
            raise AssertionError('old protocol accepted')
        print("PASS script/native theorem/native lemma capture, shared fvar identity, required statement and protocol validation")


if __name__ == "__main__":
    main()
