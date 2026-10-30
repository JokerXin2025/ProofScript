import ProofScript.Script.Recording.Parameter

open Lean Elab Tactic


namespace ProofScript

private def recordLocation (value : TSyntax `location) : TacticM RecordedValue := do
  let (wildcard, target, hypotheses) ←
    match expandLocation value.raw with
    | .wildcard => withMainContext do
      let lctx := ← getLCtx
      let hypotheses ← lctx.getFVarIds.filterM fun fvarId => return !(← fvarId.getDecl).isImplementationDetail
      let values ← hypotheses.mapM fun fvarId => recordExpression (mkFVar fvarId)
      pure (true, true, values)
    | .targets hypotheses target => pure (false, target, ← hypotheses.mapM expression)
  return .object [
    ("kind", .plain (toJson "location")),
    ("wildcard", .plain (toJson wildcard)),
    ("goal", .plain (toJson target)),
    ("hypotheses", .array hypotheses)
  ]

namespace ParamRecorder

scoped instance recordParamLocation : RecordValue (TSyntax `location) where
  record value _ := recordLocation value

scoped instance recordParamParserTacticLocation : RecordValue (TSyntax ``Parser.Tactic.location) where
  record value _ := recordLocation ⟨value.raw⟩

end ParamRecorder
