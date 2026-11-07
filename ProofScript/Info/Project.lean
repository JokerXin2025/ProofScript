import ProofScript.Info.Derive
import ProofScript.Info.Target

namespace ProofScript

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

def projectSpec : InfoSpec ProjectInfo := { kind := "project" }

def validateProjectInfo (patch : Patch) (ref : Syntax) : CommandElabM Unit := do
  let schema : InfoSchema ProjectInfo := inferInstance
  if let .error error := applyPatch schema (json% {}) patch >>= schema.decode then
    throwErrorAt ref error.render

/-- The event belongs to its source module until Lake identifies its library at export. -/
def updateProjectInfo (patch : Patch) (ref : Syntax) : CommandElabM Unit := do
  let env ← getEnv
  let prior := (moduleEvents env env.mainModule).find? fun event =>
    event.identity.kind == projectSpec.kind && !event.reset
  if prior.isSome then
    throwErrorAt ref "project_info may only appear once in this module"
  commitInfoCommand projectSpec env.mainModule.toString patch ref

end ProofScript
