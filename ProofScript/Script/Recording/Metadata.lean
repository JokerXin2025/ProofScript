import ProofScript.Script.Recording.Plan
import Lean.Elab.ConfigEval

namespace ProofScript.Recording

open Lean Elab Command
open scoped Lean.Elab.ConfigEval

inductive CaptureTiming where
| once
| before
| after
| both
deriving Inhabited, BEq, Repr

/-- Validate declaration names and emitted names against the recording envelope. -/
def validateOutputFields (parameters : List (String × CaptureTiming)) : Except String Unit := do
  let mut bases : List String := []
  let mut names : List String := []
  for (name, timing) in parameters do
    validateFieldName name
    if bases.contains name then throw s!"duplicate recorded parameter field `{name}`"
    bases := name :: bases
    let emitted := if timing == .both then
      [name ++ "_before", name ++ "_after"]
    else [name]
    for name in emitted do
      validateFieldName name
      if names.contains name then
        throw s!"duplicate recorded parameter field `{name}`"
      names := name :: names

-- These infrequently evaluated declaration values use Lean's supported expression interpreter.
derive_eval_expr_instance_using_meta_eval ParamSchema
derive_eval_expr_instance_using_meta_eval OutputField

/-- Evaluate the complete field declaration, including schema-driven helpers;
    the generic Array interpreter only reduces constructor-visible arrays. -/
private structure OutputFieldsValue where
  fields : Array OutputField

derive_eval_expr_instance_using_meta_eval OutputFieldsValue

def evalSchema (schema : TSyntax `term) : CommandElabM ParamSchema :=
  liftTermElabM <| Elab.ConfigEval.evalExprWithElab schema

def evalOutputFields (fields : TSyntax `term) : CommandElabM (Array OutputField) := do
  let wrapped ← `(term| OutputFieldsValue.mk $fields)
  let result : OutputFieldsValue ← liftTermElabM <| Elab.ConfigEval.evalExprWithElab wrapped
  return result.fields

def emittedFields (name : String) (schema : ParamSchema) (timing : CaptureTiming)
    (failure : FailurePolicy) : Array OutputField :=
  let names := if timing == .both then #[name ++ "_before", name ++ "_after"] else #[name]
  names.map fun name => { name, schema, nullable := failure == .bestEffort }

end ProofScript.Recording
