import ProofScript.Script.Recording.Parser
import Lean.EnvExtension

namespace ProofScript

open Lean

/-- Reserved recording identity for a script invocation whose data could not be exported. -/
def unrecordedRuleId : Name := `ProofScript.Recording.unrecorded

structure ScriptTacticRegistration where
  ruleId : Lean.Name
  name : String
  sourceKind : Lean.Name
  executionKind : Lean.Name
  recordingKind : Option Lean.Name
  autoRecordingError : Option String := none
  strategy : Bool
  /-- Proof goals precede the optional continuation at this index. -/
  continuation : Option Nat := none
  parameters : Array (String × Recording.ParamParserSignature) := #[]
  recordedFields : Option (Array Recording.OutputField) := none
  deriving Inhabited, Repr

/-- The Environment is the source of truth. Editor re-elaboration rolls back the
    Environment, whereas process-wide IO refs survive the rollback. -/
inductive ScriptRegistrationEntry where
  | register (registration : ScriptTacticRegistration)
  | setRecorder (ruleId recordingKind : Name) (fields : Option (Array Recording.OutputField))
  deriving Inhabited

initialize scriptRegistrationExt : SimplePersistentEnvExtension ScriptRegistrationEntry
    (Array ScriptRegistrationEntry) ← registerSimplePersistentEnvExtension {
  name := `ProofScript.scriptRegistrations
  addEntryFn := fun state entry => state.push entry
  addImportedFn := fun entries => entries.foldl (· ++ ·) #[]
}

def scriptRegistrationsFromEntries (entries : Array ScriptRegistrationEntry) : List ScriptTacticRegistration := Id.run do
  let mut registrations := []
  for entry in entries do
    match entry with
    | .register registration =>
        registrations := registrations.filter (·.ruleId != registration.ruleId) ++ [registration]
    | .setRecorder ruleId recordingKind fields =>
        registrations := registrations.map fun registration =>
          if registration.ruleId == ruleId then
            { registration with
              recordingKind := some recordingKind
              autoRecordingError := none
              recordedFields := fields }
          else registration
  return registrations

def scriptTacticRegistrations (env : Environment) : List ScriptTacticRegistration :=
  scriptRegistrationsFromEntries (scriptRegistrationExt.getState env)

/-- Explicit module closure supplied by the caller; the exporter environment is not the view. -/
def scriptRegistrationsInModules (env : Environment) (modules : Array Name) : List ScriptTacticRegistration :=
  scriptRegistrationsFromEntries <| modules.flatMap fun owner =>
    if owner == env.mainModule then (scriptRegistrationExt.getEntries env).reverse.toArray
    else (env.getModuleIdx? owner).map (scriptRegistrationExt.getModuleEntries env) |>.getD #[]

def scriptRegistrationForRecorder (env : Environment) (ruleId : Name) :
    Except String ScriptTacticRegistration := do
  let some registration := (scriptTacticRegistrations env).find? (·.ruleId == ruleId)
    | throw s!"[script recorder] unknown registration `{ruleId}`"
  if (scriptRegistrationExt.getState env).any (fun entry =>
      match entry with
      | .setRecorder id _ _ => id == ruleId
      | .register _ => false) then
    throw s!"[script recorder] `{ruleId}` already has a handwritten recorder"
  return registration

end ProofScript
