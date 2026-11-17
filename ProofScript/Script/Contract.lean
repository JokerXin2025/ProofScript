import ProofScript.Utils.SHA256
import ProofScript.Utils.Json
import ProofScript.Script.Registry

namespace ProofScript

open Lean
open scoped InfoJson

/-- Immutable invocation metadata; generated parser/elaborator names are not contract identity. -/
structure RecordingContract where
  ruleId : Name
  name : String
  kind : ScriptKind
  continuation : Option Name
  deriving Inhabited, ToJson

def RecordingContract.ofRegistration (registration : ScriptTacticRegistration) : RecordingContract :=
  { ruleId := registration.ruleId, name := registration.name, kind := registration.config.kind,
    continuation := registration.config.continuation }

def RecordingContract.id (contract : RecordingContract) : String := (toJson contract).sha256

end ProofScript
