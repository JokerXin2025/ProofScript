import ProofScript
import ProofScript.Script.Embed
import Lean.Server.References

open Lean Elab Command
open ProofScript.Recording

namespace EmbedIDEInfoTest

set_option Elab.async false

-- A recorded replay owns the original theorem's syntax. None of its source
-- positions may be reported as references belonging to the caller's command.
elab "check_embed_source_info " command:command : command => do
  let before ← getResetInfoTrees
  elabCommand command
  let trees ← getResetInfoTrees
  modifyInfoState fun state => { state with trees := before ++ trees }
  let some start := command.raw.getPos? | throwError "missing command source"
  let some stop := command.raw.getTailPos? | throwError "missing command source"
  let refs := Server.findReferences (← getFileMap) trees.toArray
  for reference in refs do
    if let some range := reference.info.range? then
      unless start ≤ range.start && range.stop ≤ stop do
        throwError m!"embed replay leaked an editor reference outside the caller: {repr reference.range}"
  let resultRefs := refs.filter fun reference =>
    reference.info.stx.isIdent && reference.info.stx.getId == `embeddedResult
  unless resultRefs.any (·.isBinder) && resultRefs.any (!·.isBinder) do
    throwError "embed execution lost its result binder or usage information"

@theorem sourceProof : True := script
  exact True.intro

check_embed_source_info
@theorem callerProof : True := script
  embed sourceProof as embeddedResult
  exact embeddedResult

-- A capture restores temporary elaboration on success and failure. Its editor
-- information must have the same lifetime, including nested capture attempts.
elab "check_capture_info_isolation" : command => liftTermElabM do
  let action : Tactic.TacticM Unit := do
    let ref ← getRef
    let capture : CaptureM RecordedData := do
      Elab.addConstInfo ref ``True
      return .plain Json.null
    let before ← getInfoState
    let _ ← CaptureM.run capture
    unless (← getInfoState).trees.size == before.trees.size do
      throwError "successful capture leaked temporary editor information"
    let failed ← try
        let _ ← CaptureM.run do
          let _ ← capture
          throwError "expected capture failure"
        pure false
      catch _ => pure true
    unless failed do throwError "failing capture unexpectedly succeeded"
    unless (← getInfoState).trees.size == before.trees.size do
      throwError "failed capture leaked temporary editor information"
    let _ ← CaptureM.run do
      let before ← getInfoState
      let result ← tryCapture capture
      unless result.isOk do throwError "nested capture unexpectedly failed"
      unless (← getInfoState).trees.size == before.trees.size do
        throwError "successful nested capture leaked temporary editor information"
      let result ← tryCapture do
        let _ ← capture
        throwError "expected nested capture failure"
      if result.isOk then throwError "failing nested capture unexpectedly succeeded"
      unless (← getInfoState).trees.size == before.trees.size do
        throwError "failed nested capture leaked temporary editor information"
      return .plain Json.null
  (action { elaborator := .anonymous }).run' { goals := [] }

check_capture_info_isolation

end EmbedIDEInfoTest
