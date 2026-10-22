import Test.RecordingComplexRules

project_info "Test.RecordingComplexTest" { title := "RecordingComplexTest" }

open Lean Elab Tactic Meta ProofScript ProofScript.Recording
open Lean.Parser.Tactic

set_option linter.unusedVariables false

-- Template errors are diagnosed against actual renamed/emitted fields.
/-- error: unknown recorded template field `labels` -/
#guard_msgs in
open Lean Elab Command ProofScript.Info in
run_cmd do
  let env ← getEnv
  try
    elabCommand (← `(command| script_info Test.RecordingComplexRules.labels {
      template := [{ lang := "zh", tag := "Labels", content := "${labels}" }] }))
    match resolveScriptInfo (← getEnv) { moduleName := env.mainModule } `Test.RecordingComplexRules.labels with
    | .error error => (throwError error.message : CommandElabM Unit)
    | .ok _ => (throwError "invalid template was consumed" : CommandElabM Unit)
  finally setEnv env

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
  for (index, count) in [(0, 0), (1, 1), (2, 2)] do
    let items ← ofExcept (steps[index]!.getObjValAs? (Array Json) "items")
    unless items.size == count do throwError "automatic category array changed shape"
  unless (steps[3]!.getObjVal? "n").toOption == some (json% 42) do
    throwError "automatic num lost numeric semantics"
