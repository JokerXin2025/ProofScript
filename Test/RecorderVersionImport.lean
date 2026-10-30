import ProofScript
import Test.RecorderVersionExtension

open Lean ProofScript

set_option proofScript.pageBuild true

script_recorder importedVersionRule => do
  execute
  record_value "fourth" true

#page theorem importedRecorderProof (P : Prop) (h : P) : P := script
  imported_version h

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find?
       (·.ruleId == `importedVersionRule)
    | throwError "missing imported registration"
  unless registration.explicitRecordingKind.isSome &&
      registration.explicitRecordingBody.isSome &&
      registration.explicitRecordingParent.isSome do
    throwError "cross-module recorder extension was not imported"
  let moduleName ← getMainModule
  let path ← Lean.Elab.Command.liftIO <| activeOutputPath
    (proofOutputPath moduleName (moduleName ++ `importedRecorderProof))
  let text ← Lean.Elab.Command.liftIO <| IO.FS.readFile path
  let .ok document := Json.parse text | throwError "invalid imported recorder JSON"
  let .ok proof := document.getObjValAs? (Array Json) "proof"
    | throwError "imported recorder did not export proof steps"
  unless proof.size == 1 && (proof[0]!.getObjVal? "first").isOk &&
      (proof[0]!.getObjVal? "second").isOk &&
      (proof[0]!.getObjVal? "third").isOk &&
      (proof[0]!.getObjVal? "fourth").isOk do
    throwError "cross-module recorder versions did not share one step"
