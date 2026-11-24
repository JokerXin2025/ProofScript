import ProofScript.Script.Expression
import ProofScript.Script.Recording.Data

namespace ProofScript

open Lean Elab Tactic

/-- Recorder-specific wrapper around the reusable expression capture. -/
def recordExpression (expr : Expr) : TacticM RecordedValue :=
  return .expression (← captureExpression expr)

namespace ValueRecorder

scoped instance : RecordValue Expr where
  record expr _ := recordExpression expr

end ValueRecorder

end ProofScript
