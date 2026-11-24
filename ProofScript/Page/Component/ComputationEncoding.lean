/-
    ProofScript.Page.Component.ComputationEncoding
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import ProofScript.Script.Expression
import ProofScript.Script.ExpressionEncoding
import ProofScript.Utils.Tactic

namespace ProofScript

open Lean Elab Tactic

/-- Read computation provenance in the declaration's current context. The function
    and implementation retain native expressions independently of proof sessions
    and execution bundles. -/
def captureComputationFunction (declaration : Name)
    (implementation : Expr) : TacticM (Expr × Expr) := do
  try
    withoutModifyingState' <| Term.withoutErrToSorry <| withoutRecover do
      let expression ← captureExpression (← mkConstWithLevelParams declaration)
      let implementation ← captureExpression implementation
      return (expression, implementation)
  catch ex =>
    let message ← ex.toMessageData.toString
    throwError "failed to capture computation function `{declaration}`: {message}"

/-- Export one complete function owner without querying Lean. Root paths are
    relative to the function object, and both expressions share its node table. -/
def encodeComputationFunction (declaration : Name) (type : String)
    (expression implementation : Expr) : Except String Json :=
  return encodeExpressionDocument do
    let expression ← encodeNativeExpression expression #[.key "expression"]
    let implementation ← encodeNativeExpression implementation #[.key "implementation"]
    return [("declaration", toJson declaration.toString),
      ("type", toJson type), ("expression", expression),
      ("implementation", implementation)]

end ProofScript
