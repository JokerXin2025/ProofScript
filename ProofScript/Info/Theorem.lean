import ProofScript.Info.Project

open Lean Elab.Command

namespace ProofScript

structure TheoremInfo where
  name : String := ""
  tags : List String := []
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

def theoremSpec : InfoSpec TheoremInfo := { kind := "theorem" }

def resolveTheoremInfo (env : Environment) (query : Query) (declaration : Name)
    : Except Diagnostic (ResolvedInfo TheoremInfo) :=
  (do
    unless env.contains declaration do throw { message := "unknown declaration" }
    let view ← resolvePartial theoremSpec env query declaration
    unless view.created do throw { message := "theorem metadata is not configured" }
    consumeView theoremSpec view : Except Diagnostic (ResolvedInfo TheoremInfo)).mapError fun error =>
      { error with kind := some theoremSpec.kind, target := some declaration.toString }

def parseTheoremInfo (fields : Array InputField) : CommandElabM Patch := do
  for field in fields do
    if field.key == "project" then
      throwErrorAt field.ref "theorem_info.project has been removed; project ownership comes from the defining Lake library"
  parsePatch (inferInstance : InfoSchema TheoremInfo) fields

end ProofScript
