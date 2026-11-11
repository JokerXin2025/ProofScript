import ProofScript.Info.Derive
import ProofScript.Info.Target
import ProofScript.Core.BuildMode

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

/-- The event belongs to its source module until Lake identifies its library at export. -/
def updateProjectInfo (patch : Patch) (ref : Syntax) : CommandElabM Unit := do
  let env ← getEnv
  commitInfoCommand projectSpec env.mainModule.toString patch ref

end ProofScript
