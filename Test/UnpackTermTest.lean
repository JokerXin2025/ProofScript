import ProofScript

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
    unless (expr.getObjValAs? String "headConstant").toOption ==
        (if head.isEmpty then none else some head) do
      throwError "wrong input recorded for {decl}"
    for binder in binders do
      unless (step.getObjVal? binder).isOk do
        throwError "missing {binder} for {decl}"

open Lean Elab Command in
private partial def termUnpackBinders : InfoTree → Array (Name × Syntax)
  | .context _ tree => termUnpackBinders tree
  | .node info children =>
    let binders := match info with
      | .ofTermInfo ti =>
        if ti.isBinder && ti.expr.isFVar then #[(ti.stx.getId, ti.stx)] else #[]
      | _ => #[]
    children.foldl (fun acc tree => acc ++ termUnpackBinders tree) binders
  | .hole _ => #[]

open Lean Elab Command in
elab "check_term_unpack_hover " cmd:command : command => do
  let before := (← getInfoState).trees.size
  withEnableInfoTree true <| elabCommand cmd
  let trees := (← getInfoState).trees.toArray.extract before
  let binders := trees.foldl (fun acc tree => acc ++ termUnpackBinders tree) #[]
  for name in [`hoverWhole, `hoverP, `hoverQ, `hoverForward, `hoverBackward,
      `hoverX, `hoverMember, `hoverProof] do
    unless binders.any (fun (n, stx) => n == name && stx.getHeadInfo matches .original ..) do
      throwError "missing source binder hover for {name}"

check_term_unpack_hover
example (S : List Nat) (Q : Nat → Prop) (h : ∃ x ∈ S, Q x) : ∃ x, Q x := by
  script_unpack_and ⟨hoverWhole⟩ := (And.intro True.intro True.intro)
  script_unpack_and ⟨hoverP, hoverQ⟩ := (And.intro True.intro True.intro)
  script_unpack_iff ⟨hoverForward, hoverBackward⟩ := (Iff.refl True)
  script_obtain_exist ⟨hoverX, hoverMember, hoverProof⟩ := (id h)
  exact ⟨hoverX, hoverProof⟩

check_term_unpack_hover
@theorem recordedTermUnpackHover (S : List Nat) (Q : Nat → Prop)
    (h : ∃ x ∈ S, Q x) : ∃ x, Q x := script
  unpack_and ⟨hoverWhole⟩ := (And.intro True.intro True.intro)
  unpack_and ⟨hoverP, hoverQ⟩ := (And.intro True.intro True.intro)
  unpack_iff ⟨hoverForward, hoverBackward⟩ := (Iff.refl True)
  obtain_exist ⟨hoverX, hoverMember, hoverProof⟩ := (id h)
  provide hoverX
