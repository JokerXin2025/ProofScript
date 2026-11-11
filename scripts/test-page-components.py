#!/usr/bin/env python3
"""Check persistent page components and pageBuild gating in both Lean modes."""

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PRELUDE = """import ProofScript
open Lean Elab Command ProofScript

page_component "widget" content:str => do
  logInfo "EDITOR_HOOK"
  when_page_build
    addPageComponent content.raw "widget" (toJson content.getString)
"""


def lean(path, source, mode, *, error=None, compile=False):
    path.write_text(PRELUDE + source)
    command = ["lake", "env", "lean", f"--root={path.parent}",
               f"-DpageBuild={str(mode).lower()}", str(path)]
    if compile:
        command.extend(["-o", str(path.with_suffix(".olean"))])
    env = dict(os.environ, PROOF_SCRIPT_OUTPUT_ROOT=str(path.parent / "output"))
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if error is None:
        assert result.returncode == 0, output
    else:
        assert result.returncode != 0 and error in output, output
    return output


def main():
    with tempfile.TemporaryDirectory(prefix="proofscript-page-components-") as directory:
        work = Path(directory)
        source = '''
#page widget "first"
set_option pageBuild false in
  #page widget "suppressed"
#page widget "last"
run_cmd do
  let state := getPageState (← getEnv)
  let expected := if ← pageBuild? then #["first", "last"] else #[]
  unless state.components.map (·.value) == expected.map toJson do
    throwError "pageBuild did not gate component recording"
  unless (modulePageDraft? (← getEnv) (← getMainModule)).isSome == (← pageBuild?) do
    throwError "incorrect persisted page draft"
'''
        for mode in (False, True):
            output = lean(work / "Page.lean", source, mode, compile=True)
            assert output.count("EDITOR_HOOK") == 3, output
            assert not (work / "output").exists(), "compilation wrote public ProofScript output"
            print(f"PASS pageBuild={mode}", flush=True)
        lean(work / "Bad.lean", '#page widget\n', True, error="unexpected")
    print("All page-component checks passed.", flush=True)


if __name__ == "__main__":
    main()
