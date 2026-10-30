import Lean.Parser.Syntax
import Lean.EnvExtension

namespace ProofScript

open Lean

/-- Reserved recording identity for a script invocation whose data could not be exported. -/
def unrecordedRuleId : Name := `ProofScript.unrecorded

inductive ScriptKind where
  | tactic | strategy | metadata
  deriving Inhabited, Repr, BEq

instance : ToJson ScriptKind where
  toJson
    | .tactic => "tactic"
    | .strategy => "strategy"
    | .metadata => "metadata"

structure ScriptRecordingConfig where
  /-- How the declaration participates in script execution and recording. -/
  kind : ScriptKind := .tactic
  /-- The named goal which continues the parent recording, when present. -/
  continuation : Option Lean.Name := none
  /-- Parameters introduced by the tactic and therefore unavailable before it runs. -/
  intro : Array Lean.Name := #[]
  /-- Parameters that are only available before the tactic runs. -/
  clear : Array Lean.Name := #[]
  deriving Inhabited, Repr, BEq

def ScriptRecordingConfig.isStrategy (config : ScriptRecordingConfig) : Bool :=
  config.kind == .strategy

def ScriptRecordingConfig.isMetadata (config : ScriptRecordingConfig) : Bool :=
  config.kind == .metadata

structure ScriptTacticRegistration where
  ruleId : Lean.Name
  name : String
  sourceKind : Lean.Name
  executionKind : Lean.Name
  /-- Recorder generated from the declaration's automatic parameter recorder. -/
  automaticRecordingKind : Option Lean.Name
  /-- Body corresponding to the automatic recorder entry. -/
  automaticRecordingBody : Option Lean.Name := none
  /-- Per-registration execution-only recorder for unsupported automatic parameters. -/
  fallbackRecordingKind : Option Lean.Name := none
  /-- Body corresponding to the fallback recorder entry. -/
  fallbackRecordingBody : Option Lean.Name := none
  /-- Most recently declared handwritten recorder, if any. -/
  explicitRecordingKind : Option Lean.Name := none
  /-- Callable body of the latest handwritten recorder. -/
  explicitRecordingBody : Option Lean.Name := none
  /-- The handwritten recorder that the current explicit recorder supersedes. -/
  explicitRecordingParent : Option Lean.Name := none
  autoRecordingError : Option String := none
  config : ScriptRecordingConfig := {}
  /-- The original declaration arguments, the sole source for recorder bindings. -/
  arguments : Array (TSyntax ``Lean.Parser.Command.macroArg) := #[]
  deriving Inhabited, Repr, BEq

/-- The Environment is the source of truth. Editor re-elaboration rolls back the
    Environment, whereas process-wide IO refs survive the rollback. -/
inductive ScriptRegistrationEntry where
  | register (registration : ScriptTacticRegistration)
  | setRecorder (ruleId recorderKind recorderBody : Name) (parentKind : Option Name)
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
    | .setRecorder ruleId recorderKind recorderBody parentKind =>
        registrations := registrations.map fun registration =>
          if registration.ruleId == ruleId then
            { registration with
              explicitRecordingKind := some recorderKind
              explicitRecordingBody := some recorderBody
              explicitRecordingParent := parentKind }
          else registration
  return registrations

def scriptTacticRegistrations (env : Environment) : List ScriptTacticRegistration :=
  scriptRegistrationsFromEntries (scriptRegistrationExt.getState env)

def ScriptTacticRegistration.recordingKind (registration : ScriptTacticRegistration) : Option Name :=
  match registration.explicitRecordingKind with
  | some kind => some kind
  | none => registration.automaticRecordingKind.or registration.fallbackRecordingKind

/-- Explicit module closure supplied by the caller; the exporter environment is not the view. -/
def scriptRegistrationsInModules (env : Environment) (modules : Array Name) : List ScriptTacticRegistration :=
  scriptRegistrationsFromEntries <| modules.flatMap fun owner =>
    if owner == env.mainModule then (scriptRegistrationExt.getEntries env).reverse.toArray
    else (env.getModuleIdx? owner).map (scriptRegistrationExt.getModuleEntries env) |>.getD #[]

def scriptRegistrationForRecorder (env : Environment) (ruleId : Name) :
    Except String ScriptTacticRegistration := do
  let some registration := (scriptTacticRegistrations env).find? (·.ruleId == ruleId)
    | throw s!"[script recorder] unknown registration `{ruleId}`"
  return registration

end ProofScript
