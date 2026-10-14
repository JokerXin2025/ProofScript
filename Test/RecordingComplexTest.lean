import Test.RecordingComplexRules

open Lean Elab Tactic Meta ProofScript ProofScript.Recording
open Lean.Parser.Tactic

set_option linter.unusedVariables false

private def field (value : Json) (key : String) : TacticM Json :=
  ofExcept (value.getObjVal? key)

example (h : True) : True := by
  run_tac withExprJsonExport do
    let hi : TSyntax `ident := ⟨mkIdent `h⟩
    let ht : TSyntax `term := ⟨mkIdent `h⟩
    let .success explicit ← tryCapture (captureLocation ⟨(← `(location| at $hi:ident ⊢)).raw⟩)
      | throwError "explicit location capture failed"
    let loc ← commitValue explicit
    unless (← field loc "goal") == toJson true && (← field loc "wildcard") == toJson false do
      throwError "location roles changed"
    let hypotheses ← ofExcept ((← field loc "hypotheses").getArr?)
    unless hypotheses.size == 1 do throwError "location lost hypothesis"
    let .success wildcard ← tryCapture (captureLocation ⟨(← `(location| at *)).raw⟩)
      | throwError "wildcard capture failed"
    unless (← field (← commitValue wildcard) "wildcard") == toJson true do
      throwError "wildcard role lost"
    let .success absent ← captureParam (.optional (.category `location)) none
      | throwError "missing location capture failed"
    unless absent.toJson == Json.null do throwError "missing location is not null"

    for (raw, count) in [(← `(rwRuleSeq| []), 0), (← `(rwRuleSeq| [$ht:term]), 1),
        (← `(rwRuleSeq| [$ht:term, ← $ht:term]), 2)] do
      let .success rules ← tryCapture (captureRewriteRules ⟨raw.raw⟩)
        | throwError "rewrite capture failed"
      let values ← ofExcept ((← commitValue rules).getArr?)
      unless values.size == count do throwError "rewrite array changed shape"
      if count == 2 then
        unless (← field values[0]! "reverse") == toJson false &&
            (← field values[1]! "reverse") == toJson true do
          throwError "rewrite directions lost"

    let .success simpValue ← tryCapture (captureSimpArguments ⟨(← `(simpArgs| [↓$ht:term, ← $ht:term, -$hi:ident, *])).raw⟩)
      | throwError "simp argument capture failed"
    let args ← ofExcept ((← commitValue simpValue).getArr?)
    unless args.size == 4 && (← field args[0]! "phase") == toJson "pre" &&
        (← field args[1]! "reverse") == toJson true &&
        (← field args[2]! "kind") == toJson "erase" &&
        (← field args[3]! "kind") == toJson "star" do
      throwError "simp roles lost"
    let .success erased ← tryCapture (captureSimpArguments ⟨(← `(simpArgs| [-missingSimproc])).raw⟩)
      | throwError "simproc erasure capture failed"
    let erased ← ofExcept ((← commitValue erased).getArr?)
    unless (← field erased[0]! "expression") == Json.null do
      throwError "non-expression erasure should retain its name with null expression"

    let .success config ← tryCapture (captureConfig
        ⟨(← `(optConfig| +contextual -zeta (maxSteps := 42) (label := "<safe>") (mode := .all))).raw⟩)
      | throwError "configuration capture failed"
    let entries ← ofExcept (config.toJson.getArr?)
    unless entries.size == 5 && (← field entries[0]! "value") == toJson true &&
        (← field entries[1]! "value") == toJson false &&
        (← field entries[2]! "value") == toJson (42 : Nat) &&
        (← field entries[3]! "value") == toJson "<safe>" &&
        (← field (← field entries[4]! "value") "kind") == toJson "syntax" do
      throwError "configuration scalar meaning lost"
    let .success empty ← tryCapture (captureConfig ⟨(← `(optConfig| )).raw⟩)
      | throwError "empty config capture failed"
    unless empty.toJson == Json.arr #[] do throwError "empty config is not an array"

    let .success number ← captureParam (.category `num) (← `(num| 42))
      | throwError "numeric capture failed"
    unless number.toJson == toJson (42 : Nat) do throwError "num is not a JSON number"
    let .success term ← tryCapture (expression (← `(term| (42 : Nat))).raw)
      | throwError "numeric term capture failed"
    unless (← commitValue term).getObjVal? "$ref" |>.isOk do
      throwError "numeric term was confused with a numeric parameter"

    let saved ← getExprJsonTable
    let .success nested ← tryCapture do
      return .object [("values", .array #[← expression (← `(term| Nat.zero)).raw,
        ← expression (← `(term| Nat.succ)).raw])]
      | throwError "object capture failed"
    unless (← getExprJsonTable) == saved do throwError "object capture leaked table"
    let values ← ofExcept ((← field (← commitValue nested) "values").getArr?)
    if values[0]! == values[1]! then throwError "nested snapshots collided"
    unless nested.references.contains ``Nat.succ do throwError "nested object lost references"
    for value in values do
      let id ← ofExcept (value.getObjValAs? String "$ref")
      unless (← getExprJsonTable).getObjVal? id |>.isOk do throwError "nested reference unresolved"
    let saved ← getExprJsonTable
    let .failed _ ← tryCapture do
      let _ ← expression (← `(term| Nat.succ)).raw
      throwError "failed nested capture"
      | throwError "capture failure lost"
    unless (← getExprJsonTable) == saved do throwError "failed object capture leaked table"
  exact h

-- Template errors are diagnosed against actual renamed/emitted fields.
/-- error: unknown recorded template field `labels` -/
#guard_msgs in
script_info Test.RecordingComplexRules.labels {
  template := [{ lang := "zh", tag := "Labels", content := "${labels}" }]
}

@theorem recordingComplexArrays : True := script
  record_labels []
  record_labels [alpha]
  record_labels [alpha, beta]
  record_number 42
  trivial

@theorem recordingComplexOptional : True := script
  record_optional
  record_optional gamma
  trivial

inductive RecordingPair : Prop where
  | mk (first second : True)

@theorem recordingComplexConstructor : RecordingPair := script
  constructor! RecordingPair.mk
  | first => trivial
  | second => trivial

@theorem recordingComplexConstructorAuto : RecordingPair := script
  constructor
  | first => trivial
  | second => trivial

@theorem recordingComplexCodeOnly : True := by trivial

theorem recordingComplexRewriteLemma (n : Nat) : n + 0 = n := Nat.add_zero n
theorem_info recordingComplexRewriteLemma { name := "Structured rewrite reference" }

@theorem recordingComplexRw (n : Nat) (h : n = 0) (hn : n + 0 = 0) : n = 0 := script
  rw [recordingComplexRewriteLemma] at hn
  rw [← h] at hn
  exact h

@theorem recordingComplexSimp (n : Nat) (h : n = 0) : n + 0 = 0 := script
  simp (maxSteps := 100) [recordingComplexRewriteLemma, h] at *

theorem recordingComplexLiterature : True := True.intro
theorem_info recordingComplexLiterature { name := "Complex reference" }

@theorem recordingComplexChange : True := script
  change True
  cite recordingComplexLiterature
  trivial

@theorem recordingComplexCalc : (1 : Nat) = 1 := script
  calc
    1 = 1 := by rfl

@theorem recordingComplexInfer (P Q : Prop) (hp : P) (hPQ : P → Q) : Q := script
  infer
    P => Q := hPQ hp

@references
page_end

open Lean Elab Command in
run_cmd do
  let .ok doc := Json.parse (← IO.FS.readFile (proofOutputPath `Test.RecordingComplexTest `recordingComplexArrays))
    | throwError "invalid proof JSON"
  unless (doc.getObjValAs? String "schemaVersion").toOption == some "0.1.0" do
    throwError "wrong proof version"
  let steps ← ofExcept (doc.getObjValAs? (Array Json) "proof")
  for (index, count) in [(1, 0), (3, 1), (5, 2)] do
    let items ← ofExcept (steps[index]!.getObjValAs? (Array Json) "items")
    unless items.size == count do throwError "automatic category array changed shape"
  unless (steps[7]!.getObjVal? "n").toOption == some (toJson (42 : Nat)) do
    throwError "automatic num lost numeric semantics"
  let some rule := (scriptTacticRegistrations (← getEnv)).find? (·.ruleId == `Test.RecordingComplexRules.labels)
    | throwError "registration missing"
  unless rule.recordedFields == some #[{name := "items", schema := .array .name, nullable := false}] do
    throwError "emitted field metadata differs from output"
