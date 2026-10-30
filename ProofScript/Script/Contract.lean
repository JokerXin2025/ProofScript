import ProofScript.Utils.SHA256
import ProofScript.Utils.Json
import ProofScript.Script.Registry

namespace ProofScript

open Lean
open scoped InfoJson

def recordingContractVersion : String := "2"
def recordingProtocolVersion : String := "0.4.0"

/-- Immutable invocation metadata; generated parser/elaborator names are not contract identity. -/
structure RecordingContract where
  contractVersion : String := recordingContractVersion
  recordingVersion : String := recordingProtocolVersion
  ruleId : Name
  name : String
  kind : ScriptKind
  continuation : Option Name
  deriving Inhabited, ToJson

def RecordingContract.ofRegistration (registration : ScriptTacticRegistration) : RecordingContract :=
  { ruleId := registration.ruleId, name := registration.name, kind := registration.config.kind,
    continuation := registration.config.continuation }

def RecordingContract.id (contract : RecordingContract) : String := (toJson contract).sha256

/-- Only presentation validation uses this descriptor; it cannot dispatch execution. -/
def RecordingContract.registration (contract : RecordingContract) : ScriptTacticRegistration :=
  { ruleId := contract.ruleId, name := contract.name,
     config := { kind := contract.kind, continuation := contract.continuation },
    sourceKind := .anonymous, executionKind := .anonymous,
    automaticRecordingKind := none, explicitRecordingKind := none,
    explicitRecordingParent := none }

end ProofScript
