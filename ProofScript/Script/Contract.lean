import ProofScript.Utils.SHA256
import ProofScript.Utils.Json
import ProofScript.Script.Registry

namespace ProofScript

open Lean
open scoped InfoJson

def recordingContractVersion : String := "1"
def recordingProtocolVersion : String := "0.1.0"

/-- Immutable invocation metadata; generated parser/elaborator names are not contract identity. -/
structure RecordingContract where
  contractVersion : String := recordingContractVersion
  recordingVersion : String := recordingProtocolVersion
  ruleId : Name
  name : String
  strategy : Bool
  continuation : Option Nat
  fields : Option (Array Recording.OutputField)
  deriving Inhabited, ToJson

def RecordingContract.ofRegistration (registration : ScriptTacticRegistration) : RecordingContract :=
  { ruleId := registration.ruleId, name := registration.name, strategy := registration.strategy,
    continuation := registration.continuation, fields := registration.recordedFields }

def RecordingContract.id (contract : RecordingContract) : String := (toJson contract).sha256

/-- Only presentation validation uses this descriptor; it cannot dispatch execution. -/
def RecordingContract.registration (contract : RecordingContract) : ScriptTacticRegistration :=
  { ruleId := contract.ruleId, name := contract.name, strategy := contract.strategy,
    continuation := contract.continuation, recordedFields := contract.fields,
    sourceKind := .anonymous, executionKind := .anonymous, recordingKind := none }

end ProofScript
