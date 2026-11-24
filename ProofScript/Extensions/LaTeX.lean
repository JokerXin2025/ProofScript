import ProofScript.Script.Command
import ProofScript.Page.Component.Core
import ProofScript.Output.Path
import ProofScript.Info.Script.Commands

open Lean
open ProofScript


private structure LatexComponent where
  metadata : ComponentMetadata
  language : String := "latex"
  source : String
  svg : Json
deriving ToJson

private def latexPreamble :=
  "\\documentclass[border=2pt,varwidth]{standalone}\n" ++
  "\\def\\pgfsysdriver{pgfsys-dvisvgm.def}\n" ++
  "\\usepackage{amsmath,amssymb,bm,mathrsfs}\n" ++
  "\\usepackage{tikz,tikz-cd,graphicx,booktabs,array,longtable,tabularx,multirow , mathrsfs}\n" ++
  "\\usetikzlibrary{cd}\n"

private def cleanSvg (raw : String) : String :=
  let lines := raw.splitOn "\n"
  let afterStart := lines.dropWhile fun line => !(line.startsWith "<svg")
  String.intercalate "\n" <|
    match afterStart.findIdx? fun line => line.startsWith "</svg>" with
    | some index => afterStart.take (index + 1)
    | none => afterStart

private def processError (name : String) (output : IO.Process.Output) : String :=
  let details :=
    if output.stderr.trimAscii.isEmpty then output.stdout
    else output.stderr
  s!"{name} failed with exit code {output.exitCode}:\n{details}"

open IO.FS in
def compileLatexToSvg (source : String) : IO String :=
  withTempDir fun dir => do
    let tex := latexPreamble ++ "\\begin{document}\n" ++ source ++ "\n\\end{document}\n"
    writeFile (dir / "component.tex") tex
    let latex ← IO.Process.output {
      cmd := "latex"
      args := #["-interaction=nonstopmode", "-halt-on-error", "component.tex"]
      cwd := some dir
    }
    unless latex.exitCode == 0 do
      throw <| IO.userError (processError "latex" latex)
    let dvisvgm ← IO.Process.output {
      cmd := "dvisvgm"
      args := #["--no-fonts", "--exact", "-o", "component.svg", "component.dvi"]
      cwd := some dir
    }
    unless dvisvgm.exitCode == 0 do
      throw <| IO.userError (processError "dvisvgm" dvisvgm)
    cleanSvg <$> readFile (dir / "component.svg")

script_elab «latex» (kind := metadata)
"latex" metadata:componentMeta code:str =>
  addComponentMetadataInfo metadata.raw

script_recorder «latex» => do
  with_rollback do
    record_goal "$goal_before"
    record_context "$context_before"
    let metadata ←
      match parseComponentMetadata metadata.raw with
      | .ok value => pure value
      | .error message => throwErrorAt metadata message
    let content ← compileLatexToSvg code.getString
    record_value "metadata_title" metadata.title
    record_value "metadata_label" metadata.label
    record_value "metadata_extra_names" (metadata.extra.map Prod.fst)
    record_value "metadata_extra_values" (metadata.extra.map Prod.snd)
    record_value "code" content
    record_value "source_language" ("latex" : String)
    record_value "source_code" code.getString
  execute
  record_goal "$goal_after"
  record_context "$context_after"

script_info «latex» {
  renderer := «svg»
}

page_component "latex" metadata:componentMeta code:str => do
  addComponentMetadataInfo metadata.raw
  when_page_build do
    match parseComponentMetadata metadata.raw with
    | .ok metadata =>
        let content ← Lean.Elab.Command.liftIO <| compileLatexToSvg code.getString
        let svg := textResourceDescriptor "svg" "svg" "image/svg+xml" content
        let value : LatexComponent := {
          metadata := metadata
          source := code.getString
          svg := svg
        }
        let labels : Array (ReferenceKind × String) := match metadata.label with
          | some label => #[("figure", label)]
          | none => #[]
        let (env, _) := recordTextResource (← getEnv) "svg" "svg" "image/svg+xml" content
        match addComponent env { kind := "latex", value := toJson value } {} labels with
        | .ok env => setEnv env
        | .error message => throwErrorAt code.raw message
    | .error message => throwErrorAt metadata.raw message
