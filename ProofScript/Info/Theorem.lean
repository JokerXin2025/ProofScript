import ProofScript.Info.Project

open Lean Elab.Command


namespace ProofScript.Info

structure TheoremInfo where
  project : Option String := none
  name : String := ""
  tags : List String := []
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

def theoremSchema : Schema TheoremInfo :=
  InfoSchema.schema.withOverrides! {
    fields := #[TheoremInfo.infoFields.project.withCodec projectReferenceCodec] }

instance (priority := high) : InfoCodec TheoremInfo := schemaCodec theoremSchema

def theoremSpec : InfoSpec TheoremInfo := {
  kind := "theorem",
  schema := theoremSchema,
  dependencies := fun value => value.project.toList.toArray.map fun name => (projectSpec.kind, .inr name)
}

def resolveTheoremInfo (env : Environment) (query : Query) (declaration : Name)
    : Except Diagnostic (ResolvedInfo TheoremInfo) :=
  (do
    unless env.contains declaration do throw { message := "unknown declaration" }
    let view ← resolvePartial theoremSpec env query declaration
    unless view.created do throw { message := "theorem metadata is not configured" }
    consumeView theoremSpec view : Except Diagnostic (ResolvedInfo TheoremInfo)).mapError fun error =>
      { error with kind := some theoremSpec.kind, target := some declaration.toString }

def updateTheoremInfo (id : TSyntax `ident) (fields : Array InputField)
    (ref : Syntax) : CommandElabM Unit := do
  let declaration ← resolveDeclaration id
  let patch ← parsePatch theoremSpec.schema fields
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  let view ←
    match resolvePartial theoremSpec env query declaration with
    | .ok view => pure view
    | .error error => throwErrorAt ref error.render
  let initialization ←
    if view.created || patch.any (·.key == .builtin TheoremInfo.infoFields.project.name) then pure none else do
    let project ←
      match activeProject env query with
      | .ok project => pure project
      | .error error => throwErrorAt ref error.render
    let source := Foundation.SourceLocation.ofSyntax (← getFileName) ref
    pure <| some #[TheoremInfo.infoFields.project.assignment project source]
  commitInfoCommand theoremSpec declaration patch ref initialization

end ProofScript.Info
