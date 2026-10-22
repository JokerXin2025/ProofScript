import ProofScript

-- Application heads are derived from structural fn edges; they are not wire fields.
private def structuralHeadConstant (table initial : Lean.Json) : Except String (Option String) := do
  let mut current := initial
  for _ in [:((← table.getObj?).size + 1)] do
    match (← current.getObjValAs? String "kind") with
    | "app" =>
      let fn ← current.getObjVal? "fn"
      current ← table.getObjVal? (← fn.getObjValAs? String "$ref")
    | "const" => return some (← current.getObjValAs? String "name")
    | _ => return none
  throw "cyclic structural application"

set_option linter.unusedVariables false

example (P Q R : Prop) (h : (P ∧ Q) ∧ R) : P := script
  unpack_and ⟨hp, hq⟩ := h.1
  exact hp

example (P Q : Prop) (h : P ∧ Q) (f : P ∧ Q → P ∧ Q) : Q := by
  script_unpack_and ⟨hp, hq⟩ := (f h)
  exact hq

example (P Q : Prop) (h : P ∧ Q) : P ∧ Q := by
  script_unpack_and ⟨whole⟩ := (id h)
  exact whole

example (P Q : Prop) (h : P ∧ Q) : P ∧ Q := by
  script_unpack_and ⟨whole⟩ := h
  fail_if_success exact h
  exact whole

example (P Q R : Prop) (h : (P ↔ Q) ∧ R) : P → Q := script
  unpack_iff ⟨forward, backward⟩ := h.1
  exact forward

example (P Q : Prop) (h : P ↔ Q) (f : (P ↔ Q) → (P ↔ Q)) : Q → P := by
  script_unpack_iff ⟨forward, backward⟩ := (f h)
  exact backward

example (P Q : Prop) (h : P ↔ Q) : P → Q := by
  script_unpack_iff ⟨forward, backward⟩ := h
  fail_if_success exact h
  exact forward

example (P : Nat → Prop) (h : (∃ n, P n) ∧ True) : ∃ n, P n := script
  obtain_exist ⟨n, hn⟩ := h.1
  provide n

example (P : Nat → Prop) (h : ∃ n, P n)
    (f : (∃ n, P n) → ∃ n, P n) : ∃ n, P n := by
  script_obtain_exist ⟨n, hn⟩ := (f h)
  exact ⟨n, hn⟩

example (P : Nat → Prop) (h : ∃ n, P n) : ∃ n, P n := by
  script_obtain_exist ⟨n, hn⟩ := h
  fail_if_success exact h
  exact ⟨n, hn⟩

example (S : List Nat) (Q : Nat → Prop)
    (h : (∃ x ∈ S, Q x) ∧ True) : ∃ x, Q x := script
  obtain_exist ⟨x, hx, hq⟩ := h.1
  provide x

example (S : List Nat) (Q : Nat → Prop) (h : ∃ x ∈ S, Q x)
    (f : (∃ x ∈ S, Q x) → ∃ x ∈ S, Q x) : ∃ x, Q x := by
  script_obtain_exist ⟨x, hx, hq⟩ := (f h)
  exact ⟨x, hq⟩

example (S : List Nat) (Q : Nat → Prop) (h : ∃ x ∈ S, Q x) : ∃ x, Q x := by
  script_obtain_exist ⟨x, hx, hq⟩ := h
  fail_if_success exact h
  exact ⟨x, hq⟩

example (unpackProof : False) (h : P ∧ Q) : False := by
  script_unpack_and ⟨hp, hq⟩ := (id h)
  exact unpackProof

example (P : Prop) (h : P) : P := by
  fail_if_success script_unpack_and ⟨hp, hq⟩ := (id h)
  fail_if_success script_unpack_and ⟨whole⟩ := (id h)
  fail_if_success script_unpack_iff ⟨hp, hq⟩ := (id h)
  fail_if_success script_obtain_exist ⟨x, hx⟩ := (id h)
  fail_if_success script_obtain_exist ⟨x, hx, hy⟩ := (id h)
  exact h

@theorem recordedUnpackAnd (P Q R : Prop) (h : (P ∧ Q) ∧ R) : P := script
  unpack_and ⟨hp, hq⟩ := h.1
  exact hp

@theorem recordedUnpackIff (P Q : Prop) (h : P ↔ Q)
    (f : (P ↔ Q) → (P ↔ Q)) : P → Q := script
  unpack_iff ⟨forward, backward⟩ := (f h)
  exact forward

@theorem recordedUnpackExistTwo (P : Nat → Prop) (h : ∃ n, P n)
    (f : (∃ n, P n) → ∃ n, P n) : ∃ n, P n := script
  obtain_exist ⟨n, hn⟩ := (f h)
  provide n

@theorem recordedUnpackExistThree (S : List Nat) (Q : Nat → Prop)
    (h : (∃ x ∈ S, Q x) ∧ True) : ∃ x, Q x := script
  obtain_exist ⟨x, hx, hq⟩ := h.1
  provide x

open Lean Elab Command in
run_cmd do
    for (decl, tactic, ruleId, head, binders) in [
       (`recordedUnpackAnd, "unpack_and", "unpack_and", "And.left", ["names"]),
       (`recordedUnpackIff, "unpack_iff", "unpack_iff", "", ["h₁", "h₂"]),
       (`recordedUnpackExistTwo, "obtain_exist", "obtain_exist", "", ["h₁", "h₂"]),
       (`recordedUnpackExistThree, "obtain_exist", "obtain_exist'", "And.left", ["h₁", "h₂", "h₃"])] do
    let path := ProofScript.proofOutputPath `Test.UnpackTermTest decl
    let .ok json := Json.parse (← IO.FS.readFile path)
      | throwError "invalid proof for {decl}"
    let steps ← ofExcept (json.getObjValAs? (Array Json) "proof")
    let steps := steps.filter (fun step => (step.getObjVal? "_ruleId").isOk)
    unless steps.size == 2 do throwError "synthetic steps leaked for {decl}"
    let step := steps[0]!
    unless (step.getObjValAs? String "_ruleId").toOption == some ("ProofScript.Script.Basic." ++ ruleId) do
      throwError "missing {tactic} step for {decl}"
    let input ← ofExcept (step.getObjVal? "h")
    let ref ← ofExcept (input.getObjValAs? String "$ref")
    let expressions ← ofExcept (json.getObjVal? "expressions")
    let expr ← ofExcept (expressions.getObjVal? ref)
    unless (expr.getObjValAs? String "kind").toOption == some "app" do
      throwError "nonlocal input missing for {decl}"
    unless (← ofExcept (structuralHeadConstant expressions expr)) ==
        (if head.isEmpty then none else some head) do
      throwError "wrong input recorded for {decl}"
    let display ← ofExcept (step.getObjVal? "h_display")
    unless (display.getObjValAs? String "field").toOption == some "h" do
      throwError "compound input lost its explicit display companion for {decl}"
    let views ← ofExcept (display.getObjValAs? (Array Json) "views")
    unless views.any (fun view => (view.getObjVal? "root").toOption ==
        some (json% { kind: "field", path: [] })) do
      throwError "compound input display is not anchored at its field root for {decl}"
    for binder in binders do
      unless (step.getObjVal? binder).isOk do
        throwError "missing {binder} for {decl}"


example (S : List Nat) (Q : Nat → Prop) (h : ∃ x ∈ S, Q x) : ∃ x, Q x := by
  script_unpack_and ⟨hoverWhole⟩ := (And.intro True.intro True.intro)
  script_unpack_and ⟨hoverP, hoverQ⟩ := (And.intro True.intro True.intro)
  script_unpack_iff ⟨hoverForward, hoverBackward⟩ := (Iff.refl True)
  script_obtain_exist ⟨hoverX, hoverMember, hoverProof⟩ := (id h)
  exact ⟨hoverX, hoverProof⟩

@theorem recordedTermUnpackHover (S : List Nat) (Q : Nat → Prop)
    (h : ∃ x ∈ S, Q x) : ∃ x, Q x := script
  unpack_and ⟨hoverWhole⟩ := (And.intro True.intro True.intro)
  unpack_and ⟨hoverP, hoverQ⟩ := (And.intro True.intro True.intro)
  unpack_iff ⟨hoverForward, hoverBackward⟩ := (Iff.refl True)
  obtain_exist ⟨hoverX, hoverMember, hoverProof⟩ := (id h)
  provide hoverX
