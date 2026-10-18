import ProofScript.Info.Derive
import ProofScript.Info.Target

namespace ProofScript.Info

open Lean Elab Command

structure ProjectInfo where
  title : String := ""
  authors : List String := []
  keywords : List String := []
  description : String := ""
  year : String := ""
  license : String := ""
  base_url : String := ""
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

def projectSpec : InfoSpec ProjectInfo :=
  { kind := "project" }

/-- References never enter this table: only committed project configurations do. -/
def knownProjects (env : Environment) (query : Query) : Except Diagnostic (Array String) := do
  let mut projects := #[]
  for event in ← queryEvents env query do
    if event.identity.kind == projectSpec.kind then
      let .inr id := event.identity.target
        | throw { message := "project targets must be strings" }
      if !projects.contains id then projects := projects.push id
  return projects

def resolveProjectInfo (env : Environment) (query : Query) (name : String) :
    Except Diagnostic (ResolvedInfo ProjectInfo) :=
  (do
    let view ← resolvePartial projectSpec env query name
    unless view.created do throw { message := "project is not configured" }
    consumeView projectSpec view : Except Diagnostic (ResolvedInfo ProjectInfo)).mapError fun error =>
      { error with kind := some projectSpec.kind, target := some name }

def activeProjectBinding : String := "ProofScript.Info.activeProject"

def activeProject (env : Environment) (query : Query) : Except Diagnostic (Option String) := do
  let unit ← resolveContext env query activeProjectBinding
  let value ← unit.value.mapError fun error => {
    error with message := "ambiguous active project; select one with `project_info \"P\" { ... }`"
               path := #[.field "project"] }
  value.mapM fun value => (fromJson? value).mapError fun message => { message }

/-- Project IDs are nonempty string literals, matched by their full text. -/
def resolveProjectTarget (stx : TSyntax `str) (allowNew := false) : CommandElabM String := do
  let name := stx.getString
  if name.isEmpty then throwErrorAt stx "project names must not be empty"
  unless allowNew do
    let env ← getEnv
    let projects ← match knownProjects env { moduleName := env.mainModule } with
      | .ok projects => pure projects
      | .error error => throwErrorAt stx error.render
    unless projects.contains name do
      throwErrorAt stx m!"unknown project `{name}`; configure it with `project_info` first"
  return name

/-- Project references use string literals and must name a configured project. -/
@[implicit_reducible] def projectReferenceCodec : InfoCodec (Option String) :=
  let _ : InfoCodec String := {
    parse := fun stx => do
      let `(term| $name:str) := stx
        | throwErrorAt stx "expected a string literal"
      resolveProjectTarget name
    toJson := toJson
    decode := fun value => do
      let name : String ← decodeJson value
      if name.isEmpty then throw { message := "project names must not be empty" }
      return name
    jsonSchema := json% { type: "string", minLength: 1 } }
  optionalInputCodec

def updateProjectInfo (target : Option (TSyntax `str)) (fields : Array InputField)
    (ref : Syntax) : CommandElabM Unit := do
  let patch ← parsePatch (inferInstance : InfoSchema ProjectInfo) fields
  let env ← getEnv
  let project ← match target with
    | some id => resolveProjectTarget id (allowNew := true)
    | none => match activeProject env { moduleName := env.mainModule } with
      | .ok project => pure (project.getD env.mainModule.toString)
      | .error error => throwErrorAt ref error.render
  let source := Foundation.SourceLocation.ofSyntax (← getFileName) ref
  commitInfoCommand projectSpec project patch ref none
    #[{ key := activeProjectBinding, value := toJson project, source }]

end ProofScript.Info
