import ProofScript

@theorem exprJSONFields
    (P : Prop) (h : P) (x : Nat) : P := script
  assumption

-- Bodies retain raw de Bruijn indices in the exported AST. In particular,
-- dependent applications can also make applicationBinderInfos encounter open
-- types after substituting an argument.
@theorem exprJSONBinders
    (f : (α : Type) → α → α)
    (h : ∀ α x, f α x = x) :
    (fun α x => f α x) = (fun α x => x) := script
  calc
    _ = (fun α x => x) := funext (fun α => funext (h α))

@theorem exprJSONLet (n : Nat) : (let x := n; x + 0) = n := script
  exact Nat.add_zero n

open Lean Meta ProofScript in
run_cmd withExprJsonExport <| Lean.Elab.Command.liftTermElabM do
  -- isProp on this open application used to panic in whnfEasyCases.
  let expr := mkApp (mkBVar 0) (mkConst ``Nat)
  let ref ← Expr2JSON expr
  let table ← getExprJsonTable
  let .ok id := (ref.getObjValAs? String "$ref") | throwError "missing expression reference"
  let .ok node := table.getObjVal? id | throwError "missing expression node"
  if (node.getObjVal? "typeOf").isOk then
    throwError "open expressions must not have inferred standalone types"
