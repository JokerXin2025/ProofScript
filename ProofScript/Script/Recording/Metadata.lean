import ProofScript.Script.Recording.Plan
import Lean.Elab.ConfigEval

namespace ProofScript.Recording

open Lean Elab Command
open scoped Lean.Elab.ConfigEval

-- These infrequently evaluated declaration values use Lean's supported expression interpreter.
derive_eval_expr_instance_using_meta_eval ParamSchema
derive_eval_expr_instance_using_meta_eval OutputField

def evalSchema (schema : TSyntax `term) : CommandElabM ParamSchema :=
  liftTermElabM <| Elab.ConfigEval.evalExprWithElab schema

def evalOutputFields (fields : TSyntax `term) : CommandElabM (Array OutputField) :=
  liftTermElabM <| Elab.ConfigEval.evalExprWithElab fields

def emittedFields (name : String) (schema : ParamSchema) (timing : CaptureTiming)
    (failure : FailurePolicy) : Array OutputField :=
  let names := if timing == .both then #[name ++ "_before", name ++ "_after"] else #[name]
  names.map fun name => { name, schema, nullable := failure == .bestEffort }

end ProofScript.Recording
