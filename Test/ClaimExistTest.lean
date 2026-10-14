import ProofScript

set_option linter.unusedVariables false

open Lean Elab Command in
run_cmd do
  for (category, spelling) in [(`scriptTactic, ""), (`tactic, "script_")] do
    for binders in ["", "x", "x, hp, hq, extra"] do
      let input := spelling ++ "claim_exist ⟨" ++ binders ++ "⟩ : ∃ n : Nat, True"
      if (Parser.runParserCategory (← getEnv) category input).isOk then
        throwError "wrong arity accepted: {input}"

example (P : Nat → Prop) (h : ∃ n, P n) : ∃ n, P n := by
  script_claim_exist ⟨n, hn⟩ : ∃ n, P n
  case proof =>
    fail_if_success exact hn
    exact h
  exact ⟨n, hn⟩

example (P Q : Nat → Prop) (h : ∃ n, P n ∧ Q n) : ∃ n, Q n := script
  claim_exist ⟨n, hp, hq⟩ : ∃ n, P n ∧ Q n
  | proof => exact h
  provide n

example (P : Nat → Prop) (h : ∃ n, P n) : ∃ n, P n := by
  fail_if_success script_claim_exist ⟨n, hp, hq⟩ : ∃ n, P n
  exact h

example (h : True) : True := by
  fail_if_success script_claim_exist ⟨n, hn⟩ : True
  exact h

@theorem recordedClaimExistTwo (P : Nat → Prop) (h : ∃ n, P n) : ∃ n, P n := script
  claim_exist ⟨n, hn⟩ : ∃ n, P n
  | proof => exact h
  provide n

@theorem recordedClaimExistThree (P Q : Nat → Prop) (h : ∃ n, P n ∧ Q n) : ∃ n, Q n := script
  claim_exist ⟨n, hp, hq⟩ : ∃ n, P n ∧ Q n
  | proof => exact h
  provide n

@theorem replayClaimExistThree (P Q : Nat → Prop) (h : ∃ n, P n ∧ Q n) : ∃ n, Q n := script
  embed recordedClaimExistThree P Q h as result
  exact result

open Lean Elab Command in
run_cmd do
  for (decl, keys) in [(`recordedClaimExistTwo, ["h₁", "h₂"]),
      (`recordedClaimExistThree, ["h₁", "h₂", "h₃"])] do
    let path := ProofScript.proofOutputPath `Test.ClaimExistTest decl
    let .ok json := Json.parse (← IO.FS.readFile path)
      | throwError "invalid recorded proof"
    let steps ← ofExcept (json.getObjValAs? (Array Json) "proof")
    let some claim := steps.find? fun j =>
         (j.getObjValAs? String "_ruleId").toOption == some (if decl == `recordedClaimExistTwo then "ProofScript.Script.Basic.claimExistTwo" else "ProofScript.Script.Basic.claimExistThree")
      | throwError "missing claim_exist strategy"
    let branches ← ofExcept (claim.getObjValAs? (Array Json) "branches")
    let some branch := branches.find? fun j =>
        (j.getObjValAs? String "name").toOption == some "proof"
      | throwError "missing claim proof branch"
    let proof ← ofExcept (branch.getObjValAs? (Array Json) "proof")
    unless proof.any (fun j =>
        (j.getObjValAs? String "_ruleId").toOption == some "ProofScript.Script.Basic.exact") do
      throwError "missing claim proof"
    for key in keys do
      let .ok value := claim.getObjVal? key | throwError "missing binder {key}"
      if value == Json.null then throwError "null binder {key}"
    if (json.compress.splitOn "existBody").length != 1 then
      throwError "temporary leaked into recording"
