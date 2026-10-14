import ProofScript

set_option linter.unusedVariables false

open Lean Elab Command in
run_cmd do
  for (category, spelling) in [(`scriptTactic, ""), (`tactic, "script_")] do
    for binders in ["", "x", "x, hp, hq, extra"] do
      let input := spelling ++ "obtain_exist ⟨" ++ binders ++ "⟩ := h"
      if (Parser.runParserCategory (← getEnv) category input).isOk then
        throwError "wrong arity accepted: {input}"

example (P Q : Nat → Prop) (h : ∃ n, P n ∧ Q n) : ∃ n, P n ∧ Q n := by
  script_obtain_exist ⟨n, hn⟩ := h
  fail_if_success exact h
  exact ⟨n, hn⟩

example (P Q : Nat → Prop) (h : ∃ n, P n ∧ Q n) : ∃ n, Q n := script
  obtain_exist ⟨n, hn⟩ := h
  unpack_and ⟨hp, hq⟩ := hn
  provide n

example (α : Type) (P Q : α → Prop) (h : ∃ x, P x ∧ Q x) : ∃ x, Q x := by
  script_obtain_exist ⟨x, hp, hq⟩ := h
  fail_if_success exact h
  have : P x := hp
  exact ⟨x, hq⟩

example (P Q R : Nat → Prop) (h : ∃ n, P n ∧ Q n ∧ R n) : ∃ n, Q n ∧ R n := script
  obtain_exist ⟨n, hp, rest⟩ := h
  provide n

example (S : List Nat) (Q : Nat → Prop) (h : ∃ x ∈ S, Q x) : ∃ x ∈ S, Q x := by
  script_obtain_exist ⟨x, hx, hq⟩ := h
  have : x ∈ S := hx
  have : Q x := hq
  exact ⟨x, hx, hq⟩

example (h : ∃ n : Nat, n = n) : ∃ n : Nat, n = n := by
  fail_if_success script_obtain_exist ⟨n, hp, hq⟩ := h
  exact h

example (h : ∃ n m : Nat, n = m) : ∃ n m : Nat, n = m := by
  fail_if_success script_obtain_exist ⟨n, m, hnm⟩ := h
  script_obtain_exist ⟨n, rest⟩ := h
  exact ⟨n, rest⟩

example (h : True ∧ True) : True := by
  fail_if_success script_obtain_exist ⟨x, hp, hq⟩ := h
  trivial

-- A user local with the temporary's base name must remain untouched.
example (existBody : False) (h : ∃ n : Nat, True ∧ True) : False := by
  script_obtain_exist ⟨n, hp, hq⟩ := h
  exact existBody

@theorem recordedObtainTwo (P : Nat → Prop) (h : ∃ n, P n) : ∃ n, P n := script
  obtain_exist ⟨n, hn⟩ := h
  provide n

@theorem recordedObtainThree (S : List Nat) (Q : Nat → Prop)
    (h : ∃ x ∈ S, Q x) : ∃ x, Q x := script
  obtain_exist ⟨x, hx, hq⟩ := h
  provide x

open Lean Elab Command in
run_cmd do
  for (decl, ruleId, keys) in [
      (`recordedObtainTwo, "ProofScript.Script.Basic.obtain_exist", ["h₁", "h₂"]),
      (`recordedObtainThree, "ProofScript.Script.Basic.obtain_exist'", ["h₁", "h₂", "h₃"])] do
    let path := ProofScript.proofOutputPath `Test.ObtainExistTest decl
    let .ok json := Json.parse (← IO.FS.readFile path)
      | throwError "invalid recorded proof"
    let .ok steps := json.getObjValAs? (Array Json) "proof"
      | throwError "missing recorded steps"
    let steps := steps.filter (fun step => (step.getObjVal? "_ruleId").isOk)
    unless steps.size == 2 do throwError "synthetic steps leaked into recording"
    let step := steps[0]!
    unless (step.getObjValAs? String "_ruleId").toOption == some ruleId do
      throwError "missing obtain_exist step"
    for key in "h" :: keys do
      let .ok value := step.getObjVal? key | throwError "missing parameter {key}"
      if value == Json.null then throwError "null parameter {key}"
    if (json.compress.splitOn "existBody").length != 1 then
      throwError "temporary leaked into recording"

open Lean Elab Command in
private partial def obtainBinders : InfoTree → Array (Name × Syntax)
  | .context _ tree => obtainBinders tree
  | .node info children =>
    let binders := match info with
      | .ofTermInfo ti =>
        if ti.isBinder && ti.expr.isFVar then #[(ti.stx.getId, ti.stx)] else #[]
      | _ => #[]
    children.foldl (fun acc tree => acc ++ obtainBinders tree) binders
  | .hole _ => #[]

open Lean Elab Command in
elab "check_obtain_hover " cmd:command : command => do
  let before := (← getInfoState).trees.size
  withEnableInfoTree true <| elabCommand cmd
  let trees := (← getInfoState).trees.toArray.extract before
  let binders := trees.foldl (fun acc tree => acc ++ obtainBinders tree) #[]
  for name in [`hoverX, `hoverMember, `hoverProof] do
    unless binders.any (fun (n, stx) => n == name && stx.getHeadInfo matches .original ..) do
      throwError "missing source binder hover for {name}"

check_obtain_hover
example (S : List Nat) (Q : Nat → Prop) (h : ∃ x ∈ S, Q x) : ∃ x, Q x := by
  script_obtain_exist ⟨hoverX, hoverMember, hoverProof⟩ := h
  exact ⟨hoverX, hoverProof⟩

check_obtain_hover
example (S : List Nat) (Q : Nat → Prop) (h : ∃ x ∈ S, Q x) : ∃ x, Q x := script
  obtain_exist ⟨hoverX, hoverMember, hoverProof⟩ := h
  provide hoverX

check_obtain_hover
@theorem recordedObtainHover (S : List Nat) (Q : Nat → Prop)
    (h : ∃ x ∈ S, Q x) : ∃ x, Q x := script
  obtain_exist ⟨hoverX, hoverMember, hoverProof⟩ := h
  provide hoverX
