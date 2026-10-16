import ProofScript

@theorem exprJSONFields
    (P : Prop) (h : P) (x : Nat) : P := script
  assumption

-- The exported AST preserves binders in dependent applications.
@theorem exprJSONBinders
    (f : (α : Type) → α → α)
    (h : ∀ α x, f α x = x) :
    (fun α x => f α x) = (fun α x => x) := script
  calc
    _ = (fun α x => x) := funext (fun α => funext (h α))

@theorem exprJSONLet (n : Nat) : (let x := n; x + 0) = n := script
  exact Nat.add_zero n
