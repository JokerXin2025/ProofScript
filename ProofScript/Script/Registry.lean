import Lean.Parser.Syntax
import Lean.EnvExtension
import ProofScript.Core.ModuleExtensionEntries

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
  deriving Inhabited, Repr, BEq

/-- Parameter timing for one explicitly generated automatic recorder. -/
structure AutoRecordingConfig where
  intro : Array Lean.Name := #[]
  clear : Array Lean.Name := #[]
  deriving Inhabited, Repr, BEq

def ScriptRecordingConfig.isStrategy (config : ScriptRecordingConfig) : Bool :=
  config.kind == .strategy

def ScriptRecordingConfig.isMetadata (config : ScriptRecordingConfig) : Bool :=
  config.kind == .metadata

/-- One generated recorder; the array index is its version number. -/
structure ScriptRecorderVersion where
  kind : Name
  label : Option String := none
  deriving Inhabited, Repr, BEq

structure ScriptTacticRegistration where
  ruleId : Lean.Name
  name : String
  sourceKind : Lean.Name
  executionKind : Lean.Name
  /-- Version zero is created with the script; later declarations append versions. -/
  recorders : Array ScriptRecorderVersion := #[]
  config : ScriptRecordingConfig := {}
  /-- The original declaration arguments, the sole source for recorder bindings. -/
  arguments : Array (TSyntax ``Lean.Parser.Command.macroArg) := #[]
  deriving Inhabited, Repr, BEq

/-- Recorder bodies are generated under a deterministic name from their parser kind. -/
def recorderBodyName (kind : Name) : Name := kind ++ `body

/-- The Environment is the source of truth. Editor re-elaboration rolls back the
    Environment, whereas process-wide IO refs survive the rollback. -/
inductive ScriptRegistrationEntry where
  | register (registration : ScriptTacticRegistration)
  | addRecorder (ruleId : Name) (recorder : ScriptRecorderVersion)
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
    | .addRecorder ruleId recorder =>
        registrations := registrations.map fun registration =>
          if registration.ruleId == ruleId then
            { registration with recorders := registration.recorders.push recorder }
          else registration
  return registrations

def scriptTacticRegistrations (env : Environment) : List ScriptTacticRegistration :=
  scriptRegistrationsFromEntries (scriptRegistrationExt.getState env)

def ScriptTacticRegistration.recordingKind (registration : ScriptTacticRegistration) : Option Name :=
  registration.recorders.back?.map (·.kind)

/-- Explicit module closure supplied by the caller; the exporter environment is not the view. -/
def scriptRegistrationsInModules (env : Environment) (modules : Array Name) : List ScriptTacticRegistration :=
  scriptRegistrationsFromEntries <| modules.flatMap fun owner =>
    moduleExtensionEntries scriptRegistrationExt env owner

def scriptRegistrationForRecorder (env : Environment) (ruleId : Name) :
    Except String ScriptTacticRegistration := do
  let some registration := (scriptTacticRegistrations env).find? (·.ruleId == ruleId)
    | throw s!"[script recorder] unknown registration `{ruleId}`"
  return registration

end ProofScript
