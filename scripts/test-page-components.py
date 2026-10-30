#!/usr/bin/env python3
"""Check page command gating, IDE hooks and closure in both Lean build modes.

Run after `lake build ProofScript`: python3 scripts/test-page-components.py.
All Lean artifacts and resource IO stay in a temporary directory. Fake TeX
commands make the LaTeX component check independent of a TeX installation.
"""

import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PRELUDE = """import ProofScript.Page.Command
import ProofScript.Page.Component.Figure
import ProofScript.Page.Component.Latex
import ProofScript.Page.Component.ProofText
import ProofScript.Page.Component.Computation
open Lean Elab Command ProofScript
"""


def main():
    with tempfile.TemporaryDirectory(prefix="proofscript-page-components-") as directory:
        work = Path(directory)
        tex_log = work / "tex.log"
        bin_dir = work / "bin"
        bin_dir.mkdir()
        for name, output in [("latex", ""), ("dvisvgm", "printf '<svg></svg>' > component.svg\n")]:
            executable = bin_dir / name
            executable.write_text(
                "#!/bin/sh\n"
                f"printf '{name}\\n' >> {shlex.quote(str(tex_log))}\n" + output
            )
            executable.chmod(0o755)
        env = dict(os.environ)
        env.update({
            "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
            "LEAN_PATH": str(work) + os.pathsep + env.get("LEAN_PATH", ""),
            "PROOF_SCRIPT_OUTPUT_ROOT": str(work / "output"),
        })

        def lean(name, source, page_build, *, error=None, absent=(), compile=False):
            path = work / f"{name}.lean"
            path.write_text(source.replace("__WORK__", json.dumps(str(work))))
            command = ["lake", "env", "lean", f"--root={work}",
                       f"-DproofScript.pageBuild={str(page_build).lower()}", str(path)]
            if compile:
                command.extend(["-o", str(path.with_suffix(".olean"))])
            result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if (result.returncode == 0) != (error is None):
                raise AssertionError(f"{name}, pageBuild={page_build}:\n{result.stdout}")
            if error is not None and error not in result.stdout:
                raise AssertionError(f"{name}: missing {error!r}:\n{result.stdout}")
            for text in absent:
                if text in result.stdout:
                    raise AssertionError(f"{name}: unexpected {text!r}:\n{result.stdout}")
            print(f"PASS {name} pageBuild={page_build}", flush=True)
            return result.stdout

        for mode in (False, True):
            output = lean("Gating", PRELUDE + r'''
run_cmd do
  unless (moduleBuildMode? (← getEnv) (← getMainModule)).isNone do
    throwError "importing a component definition locked this module's build mode"

namespace Widgets
private def payload (source : String) : Json := toJson source
/-- A component with editor hooks and compound syntax parameters. -/
page_component "widget" context:str extra:(str)? "[" names:ident,* "]" => do
  logInfo "EDITOR_BEFORE"
  when_page_build
    let value := dbg_trace "GATED_PURE_WORK"; payload context.getString
    addPageComponent context.raw "widget" (json% {
      value: $value, extra: $(extra.map TSyntax.getString),
      names: $(names.getElems.map TSyntax.getId |>.map Name.toString) })
    when_page_build
      pure ()
  logInfo "EDITOR_AFTER"
  when_page_build
    return
  logInfo "AFTER_INNER_RETURN"

page_component "ending" => do
  pure ()

macro "make_widget" : command =>
  `(command| page_component "generated" source:str => do
    when_page_build
      addPageComponent source.raw "generated" (toJson source.getString))
make_widget

run_cmd do
  unless (moduleBuildMode? (← getEnv) (← getMainModule)).isNone do
    throwError "defining components locked this module's build mode"
  let call ← ofExcept <| Parser.runParserCategory (← getEnv) `command
    "#page widget \"hello\" []"
  let doc ← liftIO <| findDocString? (← getEnv) call.getKind
  unless doc.any (·.contains "editor hooks") do throwError "component doc comment was lost"
end Widgets

-- Component names are ordinary identifiers outside the #page directive.
def widget : Nat := 42
def text : Nat := widget

#page widget "hello" "optional" [alpha, beta]
#page generated "from macro"
#page ending

run_cmd do
  let pageBuild ← pageBuildEnabled
  let state := getPageState (← getEnv)
  unless state.components.size == (if pageBuild then 2 else 0) do
    throwError "wrong component count"
  if pageBuild then
    let component := state.components[0]!
    unless component.kind == "widget" &&
        (component.value.getObjValAs? String "value").toOption == some "hello" &&
        (component.value.getObjValAs? (Option String) "extra").toOption == some (some "optional") &&
        (component.value.getObjValAs? (Array String) "names").toOption == some #["alpha", "beta"] do
      throwError "syntax bindings or component JSON changed"
    let source := String.Pos.Raw.extract (← getFileMap).source
      ⟨component.source.start⟩ ⟨component.source.stop⟩
    unless source == "\"hello\"" do throwError "component invocation source range was lost"
#page end
def afterPage : Nat := text
project_info "after-page" { title := "Info after closing" }
run_cmd do
  let draft := modulePageDraft? (← getEnv) (← getMainModule)
  unless draft.isSome == (← pageBuildEnabled) do
    throwError "verification persisted a draft, or page build did not persist it"
''', mode)
            for token in ("EDITOR_BEFORE", "EDITOR_AFTER", "AFTER_INNER_RETURN"):
                assert output.count(token) == 1, output
            assert output.count("GATED_PURE_WORK") == int(mode), output

            if tex_log.exists():
                tex_log.unlink()
            lean("Builtins", PRELUDE + r'''
#page text "= Heading <test-heading>\n\nA paragraph."
#page figure (title := "Figure", label := "test-figure") "assets/example.png"
#page latex (title := "LaTeX") "x + y"
run_cmd stageTheoremRef { name := ``True.intro, isDependency := false }
#page references
run_cmd do
  let expected := if ← pageBuildEnabled then 4 else 0
  let state := getPageState (← getEnv)
  unless state.components.size == expected do throwError "wrong builtin component count"
  if expected > 0 then
    unless state.components.map (·.kind) == #["text", "figure", "latex", "references"] do
      throwError "builtin component kinds changed"
    unless state.components[3]!.references == #[{ name := ``True.intro, isDependency := false }] do
      throwError "references changed"
    unless (← getTheoremRefs).isEmpty do throwError "references were not consumed"
  else
    unless (← getTheoremRefs).length == 1 do throwError "verification consumed references"
#page end
''', mode)
            assert tex_log.exists() == mode
            if mode:
                assert tex_log.read_text() == "latex\ndvisvgm\n"

            output = lean("IdeAnnotations", PRELUDE + '''
#info_trees in
#page figure (title := "IDE", label := "annotation-figure") "assets/a.png"
#info_trees in
#page latex (title := "IDE", label := "annotation-latex") "x"
''', mode)
            assert output.count("ComponentMetadata.title") == 2, output
            assert output.count("ComponentMetadata.label") == 2, output

            lean("Validation", PRELUDE + '''
#page figure (title := "invalid") "/absolute.png"
''', mode, error="relative resource path" if mode else None)

            lean("Closure", PRELUDE + r'''
page_component "late" =>
  let action := dbg_trace "BODY_CONSTRUCTED"; (pure () : CommandElabM Unit)
  do
    action
    liftIO <| IO.FS.writeFile (System.FilePath.mk __WORK__ / "late.txt") "ran"
    logInfo "BODY_BEFORE"
    when_page_build
      logInfo "BODY_INSIDE"
#page end
#page late
''', mode, error="page component appears after #page end",
                 absent=("BODY_CONSTRUCTED", "BODY_BEFORE", "BODY_INSIDE"))
            assert not (work / "late.txt").exists()

            closed_components = {
                "Text": '#page text "*unclosed"',
                "Figure": '#page figure (label := "!") "/absolute"',
                "Latex": '#page latex (label := "!") "invalid"',
                "References": '#page references',
                "Computation": '#page computation { function := missing, payload := "invalid" }',
                "Theorem": '#page theorem lateTheorem : True := by trace "PROOF_RAN"; trivial',
                "Lemma": '#page lemma lateLemma : True := by trace "PROOF_RAN"; trivial',
            }
            if tex_log.exists():
                tex_log.unlink()
            for name, invocation in closed_components.items():
                output = lean("Closed" + name, PRELUDE + r'''
run_cmd stageTheoremRef { name := ``True.intro, isDependency := false }
#page end
''' + invocation + r'''
run_cmd do
  unless (← getTheoremRefs).length == 1 do throwError "closed component consumed references"
  if (← getEnv).contains `lateTheorem || (← getEnv).contains `lateLemma then
    throwError "closed declaration was elaborated"
''', mode, error="page component appears after #page end", absent=("PROOF_RAN",))
                assert output.count("error:") == 1, output
            assert not tex_log.exists()

            lean("DuplicateEnd", PRELUDE + "#page end\n#page end\n", mode,
                 error="#page end may only appear once")
            lean("ReservedEnd", PRELUDE + 'page_component " end " => pure ()\n', mode,
                 error="reserved for `#page end`")
            lean("Scope", PRELUDE + '''
def outside : CommandElabM Unit := do
  when_page_build
    pure ()
''', mode, error="PageComponentScope")
            lean("ModeLock", PRELUDE + f'''
page_component "lock" => pure ()
#page lock
set_option proofScript.pageBuild {str(not mode).lower()} in
#page lock
''', mode, error="cannot change `proofScript.pageBuild`")
            lean("SpecialDeclarations", PRELUDE + r'''
project_info "special-declarations" { title := "Special declarations" }
/-- Public theorem documentation. -/
#page theorem normalTheorem : True := by exact True.intro
#page lemma normalLemma : True := by exact normalTheorem
run_cmd do
  for name in [`normalTheorem, `normalLemma] do
    unless ((← getEnv).find? name).any (fun info => match info with
      | .thmInfo _ => true | _ => false) do throwError "missing native theorem"
    if (← collectAxioms name).contains ``sorryAx then throwError "proof was replaced by sorry"
  let doc ← liftIO <| findDocString? (← getEnv) `normalTheorem
  unless doc.any (·.contains "Public theorem documentation") do throwError "theorem doc lost"
#page end
''', mode)

        for mode in (False, True):
            lean("RootImport", "import ProofScript\nopen Lean ProofScript\n" + r'''
page_component "myWidget" source:str => do
  when_page_build
    addPageComponent source.raw "myWidget" (toJson source.getString)
#page myWidget "Hello"
#page end
''', mode)

        lean("Register", PRELUDE + r'''
namespace Imported
private def payload (s : String) : Json := toJson ("imported:" ++ s)
page_component "imported" source:str => do
  when_page_build
    addPageComponent source.raw "imported" (payload source.getString)
end Imported
''', False, compile=True)
        lean("ClosedModule", "import Register\n#page end\n", False, compile=True)
        for mode in (False, True):
            lean("Import", "import ClosedModule\nopen Lean ProofScript\n" + r'''
run_cmd do
  if (getPageState (← getEnv)).closed then throwError "imported a closed page state"
#page imported "hello"
run_cmd do
  let state := getPageState (← getEnv)
  if ← pageBuildEnabled then
    unless state.components.size == 1 && state.components[0]!.value == toJson "imported:hello" do
      throwError "imported component lost its private helper or scope"
  else
    unless state.components.isEmpty do throwError "verification collected an imported component"
#page end
''', mode)
    print("All page-component checks passed.", flush=True)


if __name__ == "__main__":
    main()
