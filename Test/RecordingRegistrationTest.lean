import Test.RecordingComplexRules
import Test.TacticRewriteTest

open Lean Elab Command ProofScript ProofScript.Recording

set_option linter.unusedVariables false

-- The imported .olean carries parser/field metadata and a recorder declaration name.
-- The category instance and the handwritten override remain usable in this module.
run_cmd do
  let registrations := scriptTacticRegistrations (← getEnv)
  let some labels := registrations.find? (·.ruleId == `Test.RecordingComplexRules.labels)
    | throwError "missing imported external-category registration"
  unless labels.parameters == #[("labels", .normalized (.array (.category `recordingLabel) true))] &&
      labels.recordingKind.isSome && labels.recordedFields == some #[{
        name := "items", schema := .array .name, nullable := false
      }] do
    throwError "imported registration lost its parser or output contract"
  let some manual := registrations.find? (·.ruleId == `Test.TacticRewriteTest.recordedIdentity)
    | throwError "missing imported handwritten registration"
  unless (scriptRegistrationExt.getState (← getEnv)).any (fun entry => match entry with
      | .setRecorder id kind fields => id == manual.ruleId &&
          manual.recordingKind == some kind && manual.recordedFields == fields
      | _ => false) do
    throwError "handwritten override did not survive module import"
  let some render := (renderRegistrationExt.getState (← getEnv)).find? (·.id == manual.ruleId)
    | throwError "missing imported render registration"
  unless render.parameters == #[("_proof", some (.category `term))] &&
      render.recordedFields == manual.recordedFields do
    throwError "imported execution/render metadata disagree"

-- Unsupported compound parsers need structural comparison, rather than none == none.
script_elab compoundParser "signature_compound" value:(ident term) => pure ()

/--
error: [script recorder] parameters of `Test.RecordingRegistrationTest.compoundParser` do not match its registration
-/
#guard_msgs in
script_recorder compoundParser "signature_compound" value:(ident str) => recordStep []

-- The same parser at a different source position must still match.
script_recorder compoundParser "signature_compound" value:(ident term) => recordStep []

-- Equal semantic shapes are insufficient when quotation binders require different extraction.
script_elab separatedParser "signature_separated" values:sepBy(ident, ",") => pure ()

/--
error: [script recorder] parameters of `Test.RecordingRegistrationTest.separatedParser` do not match its registration
-/
#guard_msgs in
script_recorder separatedParser "signature_separated" values:ident* => recordStep []

script_recorder separatedParser "signature_separated" values:sepBy(ident, ",") => recordStep []

script_elab scalarParser "signature_scalar" value:str => pure ()

/--
error: [script recorder] parameters of `Test.RecordingRegistrationTest.scalarParser` do not match its registration
-/
#guard_msgs in
script_recorder scalarParser "signature_scalar" value:num => recordStep []

-- Simulate editor re-elaboration: a declaration, override and template are rolled back,
-- then the same ID is declared with a different category. No obsolete metadata may survive.
run_cmd do
  let saved ← get
  let oldIds := (scriptTacticRegistrations (← getEnv)).map (·.ruleId)
  let oldRender := (renderRegistrationExt.getState (← getEnv)).map RenderRegistration.toJson
  let oldUpdates := (renderUpdateExt.getState (← getEnv)).map RenderUpdate.toJson
  let elaborate := fun source => do
    let .ok command := Parser.runParserCategory (← getEnv) `command source
      | throwError "invalid registration test command: {source}"
    elabCommand command
    if (← get).messages.hasErrors then
      throwError "registration test command failed: {source}"
  elaborate "script_elab editorProbe (params := [value(timing := once, failure := required)]) \"record_editor_probe\" value:str => pure ()"
  elaborate "script_recorder editorProbe (fields := #[{ name := \"label\", schema := .string, nullable := false }]) \"record_editor_probe\" value:str => recordStep [(\"label\", Lean.Json.str value.getString)]"
  elaborate "script_info editorProbe { template := [{ lang := \"en\", tag := \"Editor\", content := \"${label}\" }] }"
  let ruleId := (← getMainModule) ++ `editorProbe
  let some overridden := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == ruleId)
    | throwError "editor declaration was not registered"
  unless overridden.recordedFields == some #[{
      name := "label", schema := .string, nullable := false
    }] && (renderUpdateExt.getState (← getEnv)).size == oldUpdates.size + 1 do
    throwError "editor override/template was not registered"
  set saved
  unless (scriptTacticRegistrations (← getEnv)).map (·.ruleId) == oldIds &&
      (renderRegistrationExt.getState (← getEnv)).map RenderRegistration.toJson == oldRender &&
      (renderUpdateExt.getState (← getEnv)).map RenderUpdate.toJson == oldUpdates do
    throwError "registrations or render metadata survived command rollback"
  if (Parser.runParserCategory (← getEnv) `scriptTactic "record_editor_probe \"old\"").isOk then
    throwError "rolled-back parser survived command rollback"
  elaborate "script_elab editorProbe (params := [value(timing := once, failure := required)]) \"record_editor_probe\" value:num => pure ()"
  let some edited := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == ruleId)
    | throwError "re-elaborated registration is missing"
  unless edited.parameters == #[("value", .normalized (.category `num))] &&
      edited.recordingKind.isSome && edited.recordedFields == some #[{
        name := "value", schema := .number, nullable := false
      }] do
    throwError "re-elaboration retained the previous category or output contract"
  if (scriptRegistrationExt.getState (← getEnv)).any (fun entry => match entry with
      | .setRecorder id _ _ => id == ruleId
      | _ => false) then
    throwError "rolled-back handwritten override survived re-elaboration"

@theorem recordingRegistrationEdited : True := script
  record_editor_probe 42
  trivial

@theorem recordingRegistrationImported (P : Prop) (h : P) : P := script
  record_labels [alpha]
  recorded_identity h

-- A structurally unsupported parameter can still use its handwritten recorder.
@theorem recordingRegistrationCompound : True := script
  signature_compound label True.intro
  signature_separated first, second
  trivial
