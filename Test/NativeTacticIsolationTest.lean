import ProofScript
import Test.SpacedRegistrationDecl

open ProofScript

theorem nativeLeftRight (P Q : Prop) (hP : P) (_hQ : Q) : P ∨ Q := by
  left
  exact hP

theorem nativeRight (P Q : Prop) (_hP : P) (hQ : Q) : P ∨ Q := by
  right
  exact hQ

theorem nativeFunext (f g : Nat → Nat) (h : ∀ x, f x = g x) : f = g := by
  funext x
  exact h x

@theorem proofScriptByLeft (P Q : Prop) (hP : P) : P ∨ Q := by
  left
  exact hP

@theorem proofScriptByRight (P Q : Prop) (hQ : Q) : P ∨ Q := by
  right
  exact hQ

@theorem scriptLeft (P Q : Prop) (hP : P) : P ∨ Q := script
  left
  exact hP

@theorem scriptRight (P Q : Prop) (hQ : Q) : P ∨ Q := script
  right
  exact hQ

-- Check parser rejection, not an elaborator's script-mode diagnostic.
run_cmd do
  let env ← Lean.getEnv
  for call in ["unpack_and ⟨hp, hq⟩ := h",
      "unpack_iff ⟨hp, hq⟩ := h", "obtain_exist ⟨n, hn⟩ := h",
      "provide 0", "witness", "split_and", "split_and!", "split_iff",
      "cases_by h", "cases_by! h", "cases_on P", "contra h", "claim h : True",
      "complete_induction n", "constructor! True.intro", "quot_induction q with a",
      "remark \"text\"", "svg \"text\"", "latex \"text\"", "cite thm",
      "simp_only [h]", "admit \"reason\"", "embed thm as h",
      "infer True => True := True.intro"] do
    if (Lean.Parser.runParserCategory env `term ("by " ++ call)).isOk then
      throwError "bare script tactic parsed in by: {call}"
    if (Lean.Parser.runParserCategory env `tactic call).isOk then
      throwError "bare script tactic registered in tactic: {call}"
  for code in ["script exact True.intro <;> trivial",
      "script split_and\n  | left => skip\n  | right => trivial",
       "script script_trivial"] do
    if (Lean.Parser.runParserCategory env `term code).isOk then
      throwError "native/prefixed grammar leaked into script: {code}"
  for code in ["by intro h; exact h", "by have h : True := by trivial; exact h",
      "by induction n with | zero => rfl | succ n ih => rfl",
      "by constructor <;> trivial", "by calc 0 = 0 := rfl",
      "by script_remark \"text\"; script_trivial",
       "script intro h; exact h",
      "script have h := (by trivial : True); exact h",
      "script calc 0 = 0 := script rfl",
      "script infer True => True := True.intro"] do
    if let .error error := Lean.Parser.runParserCategory env `term code then
      throwError "expected successful parse: {code}\n{error}"

-- New registrations, including native-name collisions, need no allowlist.
script_macro isolationFinish "isolation_finish" => `(tactic| trivial)
script_info isolationFinish { template := [{lang := "en", tag := "Isolation finish", content := ""}] }
script_elab isolationElab "isolation_elab" => do
  Lean.Elab.Tactic.evalTactic (← `(tactic| trivial))
script_info isolationElab { template := [{lang := "en", tag := "Isolation elaborator", content := ""}] }
script_macro isolationSkip "skip" => `(tactic| trivial)
script_info isolationSkip { template := [{lang := "en", tag := "Isolation skip", content := ""}] }
script_macro isolationOverloadZero "isolation_overload" => `(tactic| trivial)
script_info isolationOverloadZero { template := [{lang := "en", tag := "Isolation overload", content := ""}] }
script_macro isolationOverloadProof "isolation_overload" proof:term => `(tactic| exact $proof)
script_info isolationOverloadProof { template := [{lang := "en", tag := "Isolation proof", content := "${proof_before}"}] }

run_cmd do
  let env ← Lean.getEnv
  for name in ["isolation_finish", "isolation_elab"] do
    if (Lean.Parser.runParserCategory env `term ("by " ++ name)).isOk then
      throwError "extension leaked into native grammar: {name}"
  let .ok native := Lean.Parser.runParserCategory env `tactic "skip"
    | throwError "native skip no longer parses"
  let .ok custom := Lean.Parser.runParserCategory env `scriptTactic "skip"
    | throwError "script skip does not parse"
  if native.getKind == custom.getKind then
    throwError "native and script skip share a parser kind"

example : True := by
  script_remark "explicit macro entry"
  script_isolation_finish

example : True := by script_isolation_elab
example : True := script isolation_finish
@theorem isolationRecordedExtension : True := script isolation_elab
example : True := by skip; trivial
example : True := script skip
@theorem isolationRecordedOverload : True := script isolation_overload
@theorem isolationRecordedOverloadArg : True := script isolation_overload True.intro

-- Script keywords remain usable as identifiers outside the script grammar.
example (remark svg provide : Nat) : remark + svg = provide → remark + svg = provide := by
  intro h
  exact h

example : True := by
  have h : True := script
    isolation_finish
  exact h

@theorem isolationRecordedNestedTerms : True := script
  exact (by
    have h' : True := script isolation_finish
    exact h')

@theorem isolationRecordedChains : (0 = 0) ∧ True := script
  split_and
  | left =>
    calc
      0 = 0 := script rfl
  | right =>
    infer
      True => True := (by trivial)

example : 0 = 0 := by
  script_calc
    0 = 0 := by rfl

example : True := by
  script_infer
    True => True := True.intro

-- Imported initialization must use the same normalized names as local execution.
example : True := script spaced_finish True.intro
example : True := script spaced_elab True.intro
@theorem importedSpacedRecorder : True := script spaced_exclusive True.intro
@theorem nestedSpacedScript : True := script
  exact (by
    have h : True := script spaced_finish True.intro
    exact h)

-- Literal keywords are not restricted to Lean identifier characters or namespace paths.
-- Non-identifier literals need lexer tokens, just as native non-reserved tactics do.
-- This category supplies tokens only, not native tactic productions.
declare_syntax_cat isolationLiteralToken
syntax "✓" "isolation↗" "isolation.finish" "isolation..finish"
  "script_✓" "script_isolation↗" "script_isolation.finish"
  "script_isolation..finish" : isolationLiteralToken

script_macro isolationIntroProper "intro_proper'" => `(tactic| trivial)
script_info isolationIntroProper { template := [{lang := "en", tag := "Isolation intro", content := ""}] }
script_elab isolationFinishQuestion "isolation_finish?" => do
  Lean.Elab.Tactic.evalTactic (← `(tactic| trivial))
script_info isolationFinishQuestion { template := [{lang := "en", tag := "Isolation question", content := ""}] }
script_macro isolationFinishBang "isolation_finish!" => `(tactic| trivial)
script_info isolationFinishBang { template := [{lang := "en", tag := "Isolation bang", content := ""}] }
script_elab isolationAlpha "isolation_α₂" => do
  Lean.Elab.Tactic.evalTactic (← `(tactic| trivial))
script_info isolationAlpha { template := [{lang := "en", tag := "Isolation alpha", content := ""}] }
script_macro isolationCheck "✓" => `(tactic| trivial)
script_info isolationCheck { template := [{lang := "en", tag := "Isolation check", content := ""}] }
script_elab isolationArrow "isolation↗" => do
  Lean.Elab.Tactic.evalTactic (← `(tactic| trivial))
script_info isolationArrow { template := [{lang := "en", tag := "Isolation arrow", content := ""}] }
script_macro isolationDot "isolation.finish" => `(tactic| trivial)
script_info isolationDot { template := [{lang := "en", tag := "Isolation dot", content := ""}] }
script_elab isolationDoubleDot "isolation..finish" => do
  Lean.Elab.Tactic.evalTactic (← `(tactic| trivial))
script_info isolationDoubleDot { template := [{lang := "en", tag := "Isolation double dot", content := ""}] }

example : True := by script_intro_proper'
example : True := by script_isolation_finish?
example : True := by script_isolation_finish!
example : True := by script_isolation_α₂
example : True := by script_✓
example : True := by script_isolation↗
example : True := by script_isolation.finish
example : True := by script_isolation..finish

example : True := script intro_proper'
example : True := script isolation_finish?
example : True := script isolation_finish!
example : True := script isolation_α₂
example : True := script ✓
example : True := script isolation↗
example : True := script isolation.finish
example : True := script isolation..finish

@theorem recordedApostrophe : True := script intro_proper'
@theorem recordedQuestion : True := script isolation_finish?
@theorem recordedBang : True := script isolation_finish!
@theorem recordedSubscript : True := script isolation_α₂
@theorem recordedSymbol : True := script ✓
@theorem recordedSymbolSuffix : True := script isolation↗
@theorem recordedDotted : True := script isolation.finish
@theorem recordedRepeatedDot : True := script isolation..finish

example : True := by script_spaced_finish' True.intro
example : True := by script_spaced_elab? True.intro
example : True := script spaced_finish' True.intro
example : True := script spaced_elab? True.intro
@theorem importedSpacedApostrophe : True := script spaced_finish' True.intro
@theorem importedSpacedQuestion : True := script spaced_elab? True.intro

example : True ∧ True := script
  split_and
  | left => intro_proper'
  | right => isolation_finish?

example : True ∧ True := script
  split_and
  · ✓
  · isolation..finish

@theorem recordedPunctuationBranches : True ∧ True := script
  split_and
  | left => ✓
  | right => isolation..finish

run_cmd do
  let env ← Lean.getEnv
  let registrations := ProofScript.scriptTacticRegistrations env
  for name in ["intro_proper'", "isolation_finish?", "isolation_finish!", "isolation_α₂",
      "✓", "isolation↗", "isolation.finish", "isolation..finish",
      "spaced_finish'", "spaced_elab?"] do
    let call := name ++ (if name.startsWith "spaced_" then " True.intro" else "")
    for category in [`term, `tactic] do
      let code := (if category == `term then "by " else "") ++ call
      if (Lean.Parser.runParserCategory env category code).isOk then
        throwError "literal keyword leaked into native grammar: {code}"
    let .ok source := Lean.Parser.runParserCategory env `scriptTactic call
      | throwError "registered keyword did not parse: {call}"
    let some id := ProofScript.tacticNameIdent source
      | throwError "registered keyword has no dispatcher identifier: {name}"
    unless id.getId == Lean.Name.mkSimple name && id.getId.toString false == name do
      throwError "dispatcher changed literal keyword: {name}"
    unless (ProofScript.registeredTacticCall registrations source).isSome do
      throwError "registered keyword did not match: {name}"
  -- A matching keyword alone must not admit native or structural syntax nodes.
  for kind in [`Lean.Parser.Tactic.case, `Lean.cdot, `Lean.Parser.Tactic.trivial] do
    let fake := Lean.Syntax.node .none kind #[Lean.mkAtom "intro_proper'"]
    if (ProofScript.registeredTacticCall registrations fake).isSome then
      throwError "unregistered source kind accepted: {kind}"

syntax "unregistered?" : scriptTactic

/-- error: unknown script tactic -/
#guard_msgs in
example : True := script unregistered?

/--
error: 未知script策略
---
error: Unknown identifier `unregisteredRecordedPunctuation`
-/
#guard_msgs in
@theorem unregisteredRecordedPunctuation : True := script unregistered?
