import ProofScript.Script.Config
import Test.RecordingKernelTest

open Lean ProofScript Lean.Elab.Tactic

-- Reuse the surviving cross-module instance rather than the removed category fixture.
declare_syntax_cat kernelLabel
syntax ident : kernelLabel

script_elab labelSingle "label_single" _x:kernelLabel => pure ()
script_elab labelMany "label_many" _xs:kernelLabel+ => pure ()
script_elab labelStar "label_star" _xs:kernelLabel* => pure ()
script_elab labelOptional "label_optional" _x:(kernelLabel)? => pure ()
script_elab labelSeparated "label_separated" _xs:sepBy(kernelLabel, ",") => pure ()
script_elab labelSeparatedOne "label_separated_one" _xs:sepBy1(kernelLabel, ",") => pure ()
script_elab labelIndented "label_indented" _xs:(colGt kernelLabel)+ => pure ()

declare_syntax_cat unrecordedLabel
syntax ident : unrecordedLabel
script_elab noCodec "no_codec" _x:unrecordedLabel => pure ()

run_cmd do
  let some registration := (scriptTacticRegistrations (← getEnv)).find?
      (·.ruleId == `Test.RecordingNormalizeTest.noCodec)
    | throwError "missing unsupported registration"
  unless registration.autoRecordingError.isSome && registration.recordingKind.isNone do
    throwError "missing instance did not defer automatic recording"

script_recorder noCodec "no_codec" _x:unrecordedLabel => recordStep []

run_cmd do
  for registration in scriptTacticRegistrations (← getEnv) do
    if registration.ruleId.getPrefix == `Test.RecordingNormalizeTest then
      if let some error := registration.autoRecordingError then
        throwError "{error}"

example : True := by
  run_tac do
    let saved ← Lean.Elab.Tactic.saveState
    try
      modifyEnv (recordingSessionExt.setState · (some {}))
      ensureBox "test"
      pushRecordingTag "test"
      withExprJsonExport do
        withRecordingRule `test (← `(tactic| skip)) do
          evalTactic (← `(tactic| _script_label_single alpha))
          evalTactic (← `(tactic| _script_label_many alpha beta))
          evalTactic (← `(tactic| _script_label_star))
          evalTactic (← `(tactic| _script_label_optional))
          evalTactic (← `(tactic| _script_label_optional alpha))
          evalTactic (← `(tactic| _script_label_separated alpha, beta))
          evalTactic (← `(tactic| _script_label_separated_one alpha))
        let records ← takeBox "test"
        unless records.size == 14 do throwError "missing generated records"
        unless (records[3]!.getObjVal? "_xs_before").toOption ==
            some (Json.arr #[Json.str "alpha", Json.str "beta"]) do
          throwError "array codec did not record both labels: {records[3]!.compress}"
        unless (records[5]!.getObjVal? "_xs_before").toOption == some (Json.arr #[]) do
          throwError "empty star parameter lost its array shape"
        unless (records[7]!.getObjVal? "_x_before").toOption == some Json.null do
          throwError "absent optional parameter was not captured"
        unless (records[13]!.getObjVal? "_xs_before").toOption ==
            some (Json.arr #[Json.str "alpha"]) do
          throwError "single separated value lost its array shape"
    finally
      saved.restore
  trivial
