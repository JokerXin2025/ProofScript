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

project_info "Test.CasesByTermTest" { title := "CasesByTermTest" }

private def OrAlias (P Q : Prop) := P ∨ Q

example (P Q R : Prop) (h : (P ∨ Q) ∧ R) : R := script
  cases_by h.1
  | left => exact_proj h
  | right => exact_proj h

example (P Q R : Prop) (h : (P ∨ Q) ∧ R) : R := by
  script_cases_by h.1
  case left => exact h.2
  case right => exact h.2

example (P Q : Prop) (h : P ∨ Q) (f : P ∨ Q → OrAlias P Q) : P ∨ Q := script
  cases_by (f h)
  | left =>
    left
    exact hp
  | right =>
    right
    exact hq

example (P Q : Prop) (h : P ∨ Q) : P ∨ Q := script
  cases_by h
  | left =>
    left
    exact hp
  | right =>
    right
    exact hq

example (P Q R : Prop) (h : ((P ∨ Q) ∨ R) ∧ True) : True := script
  cases_by! h.1
  | goalI => trivial
  | goalII => trivial
  | goalIII => trivial

example (P Q : Prop) (h : P ∨ Q) : True := by
  script_cases_by! (id h)
  case goalI => trivial
  case goalII => trivial
  case goalIII => trivial
  case goalIV => trivial

example (P Q : Prop) (h : P ∨ Q) : True := script
  cases_by! h
  | goalI => trivial
  | goalII => trivial

example (P : Prop) (_h : P) : True := by
  fail_if_success script_cases_by _h
  fail_if_success script_cases_by! (id _h)
  trivial

@theorem recordedCasesBy (P Q R : Prop) (h : (P ∨ Q) ∧ R) : R := script
  cases_by h.1
  | left =>
    cases_by! (id h.1)
    | goalI => exact_proj h
    | goalII => exact_proj h
  | right => exact_proj h

@theorem recordedCasesByBang (P Q : Prop) (h : P ∨ Q)
    (f : P ∨ Q → P ∨ Q) : True := script
  cases_by! (f h)
  | goalI => trivial
  | goalII => trivial
  | goalIII => trivial
  | goalIV => trivial

open Lean Elab Command in
run_cmd do
  for (name, tactic, branches) in [
      (`recordedCasesBy, "cases_by", ["left", "right"]),
      (`recordedCasesByBang, "cases_by!", ["goalI", "goalII", "goalIII", "goalIV"])] do
    let path := ProofScript.proofOutputPath `Test.CasesByTermTest name
    let .ok json := Json.parse (← IO.FS.readFile path)
      | throwError "invalid recorded proof for {name}"
    let steps ← ofExcept (json.getObjValAs? (Array Json) "proof")
    let ruleId := if tactic == "cases_by" then "ProofScript.Script.Basic.cases_by" else "ProofScript.Script.Basic.cases_by!"
    let some node := steps.find? fun j =>
        (j.getObjValAs? String "_ruleId").toOption == some ruleId
      | throwError "missing {tactic} strategy"
    let proof ← ofExcept (node.getObjVal? "h")
    let ref ← ofExcept (proof.getObjValAs? String "$ref")
    let expressions ← ofExcept (json.getObjVal? "expressions")
    let expr ← ofExcept (expressions.getObjVal? ref)
    unless (expr.getObjValAs? String "kind").toOption == some "app" do
      throwError "{tactic} did not record the compound proof term"
    if tactic == "cases_by" then
      unless (← ofExcept (structuralHeadConstant expressions expr)) == some "And.left" do
        throwError "cases_by did not record the projection proof"
    let display ← ofExcept (node.getObjVal? "h_display")
    unless (display.getObjValAs? String "field").toOption == some "h" do
      throwError "{tactic} lost its compound input display companion"
    let views ← ofExcept (display.getObjValAs? (Array Json) "views")
    unless views.any (fun view => (view.getObjVal? "root").toOption ==
        some (json% { kind: "field", path: [] })) do
      throwError "{tactic} input display is not anchored at its field root"
    let records ← ofExcept (node.getObjValAs? (Array Json) "branches")
    let branchProof (label : String) : CommandElabM (Array Json) := do
      let some record := records.find? fun j =>
          (j.getObjValAs? String "name").toOption == some label
        | throwError "missing {tactic} branch {label}"
      ofExcept (record.getObjValAs? (Array Json) "proof")
    for branch in branches do
      let entries ← branchProof branch
      unless !entries.isEmpty do throwError "empty {tactic} branch {branch}"
    if tactic == "cases_by" then
      let left ← branchProof "left"
      let some nested := left.find? fun j =>
          (j.getObjValAs? String "_ruleId").toOption == some "ProofScript.Script.Basic.cases_by!"
        | throwError "nested cases_by! escaped left branch"
      let nestedProof ← ofExcept (nested.getObjVal? "h")
      let nestedRef ← ofExcept (nestedProof.getObjValAs? String "$ref")
      let nestedExpr ← ofExcept (expressions.getObjVal? nestedRef)
      unless (nestedExpr.getObjValAs? String "kind").toOption == some "app" do
        throwError "nested application proof term not recorded"
