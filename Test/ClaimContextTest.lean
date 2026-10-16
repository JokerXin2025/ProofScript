import ProofScript

set_option linter.unusedVariables false

-- Check the elaborator independently of script branch parsing, including a local instance
-- introduced after the initial theorem context and a hypothesis depending on another proof.
example (P : Prop) (hp : P) (Q : P → Prop) (hq : Q hp) : Q hp := by
  letI : Inhabited (Q hp) := ⟨hq⟩
  script_claim hc : Q hp
  case proof =>
    fail_if_success exact hc
    exact (default : Q hp)
  exact (fun (_ : P) (h : Q hp) => h) hp hc

-- Both sibling branches have nested claim proofs and continuations using local hypotheses.
example (P : Prop) (hp : P) (Q : P → Prop) (hq : Q hp) : Q hp ∧ Q hp := script
  split_and
  | left =>
    claim hc : Q hp ∧ Q hp
    | proof =>
      split_and
      | left => exact hq
      | right => exact hq
    have hd := (fun (h : Q hp ∧ Q hp) => h.1) hc
    exact (fun (_ : P) (_ : Q hp) => hd) hp hq
  | right =>
    claim hc : Q hp
    | proof => exact hq
    exact (fun (_ : Q hp) => hc) hq

@theorem recordedClaimContext (P : Prop) (hp : P) (Q : P → Prop)
    (hq : Q hp) [Inhabited (Q hp)] : Q hp ∧ Q hp := script
  split_and
  | left =>
    claim hc : Q hp ∧ Q hp
    | proof =>
      split_and
      | left => exact (default : Q hp)
      | right => exact hq
    have hd := (fun (h : Q hp ∧ Q hp) => h.1) hc
    exact (fun (_ : P) (_ : Q hp) => hd) hp hq
  | right =>
    claim hc : Q hp
    | proof => exact hq
    exact (fun (_ : Q hp) => hc) (default : Q hp)

open Lean Elab Command in
run_cmd do
  let path := ProofScript.proofOutputPath `Test.ClaimContextTest `recordedClaimContext
  let .ok json := Json.parse (← IO.FS.readFile path)
    | throwError "invalid recorded proof"
  let steps ← ofExcept (json.getObjValAs? (Array Json) "proof")
  let some split := steps.find? fun j =>
       (j.getObjValAs? String "_ruleId").toOption == some "ProofScript.Script.Basic.split_and"
    | throwError "missing outer split"
  let branches ← ofExcept (split.getObjValAs? (Array Json) "branches")
  for branch in ["left", "right"] do
    let some record := branches.find? fun j =>
        (j.getObjValAs? String "name").toOption == some branch
      | throwError "missing {branch} branch"
    let entries ← ofExcept (record.getObjValAs? (Array Json) "proof")
    let some claim := entries.find? fun j =>
         (j.getObjValAs? String "_ruleId").toOption == some "ProofScript.Script.Basic.claim"
      | throwError "missing claim in {branch}"
    let claimBranches ← ofExcept (claim.getObjValAs? (Array Json) "branches")
    let some claimProof := claimBranches.find? fun j =>
        (j.getObjValAs? String "name").toOption == some "proof"
      | throwError "missing claim proof branch"
    let proof ← ofExcept (claimProof.getObjValAs? (Array Json) "proof")
    unless !proof.isEmpty do throwError "empty claim proof"
    unless (claim.getObjVal? "h").isOk do throwError "missing claimed hypothesis"
    unless entries.any (fun j =>
        (j.getObjValAs? String "_ruleId").toOption == some "ProofScript.Script.Basic.exact") do
      throwError "continuation escaped {branch}"
    if branch == "left" then
      unless proof.any (fun j =>
           (j.getObjValAs? String "_ruleId").toOption == some "ProofScript.Script.Basic.split_and") do
        throwError "nested split escaped claim proof"
