import ProofScript.Builtin.Script
import ProofScript.Page.Component.Declaration

open Lean ProofScript

set_option pageBuild true

namespace CalcRecorderTest

-- The execution macro works independently of the recorder.
example (a b : Nat) (h : a = b) : a = b := by
  script_calc
    a = b := h

#page theorem chain (a b c : Nat) (hab : a = b) (hbc : b = c) : a = c := script
  calc
    a = b := hab
    _ = c := hbc

#page theorem mixedRelations (a b c : Nat) (hab : a ≤ b) (hbc : b < c) : a < c := script
  calc
    a ≤ b := hab
    _ < c := hbc

#page theorem implicitFirst (a b : Nat) (h : a = b) : a = b := script
  calc
    a
    _ = b := h

#page theorem hole (a b : Nat) (h : a = b) : a = b := script
  calc
    a = b := ?_; exact h

-- Native calc can extend a partial chain with a remaining goal.
#page theorem extended (a b c : Nat) (hab : a = b) (hbc : b = c) : a = c := script
  calc
    a = b := hab; exact hbc

-- An ordinary nested script_calc must not contribute steps to its caller.
#page theorem nestedUnrecorded (a b c d : Nat)
    (had : a = d) (hdb : d = b) (hbc : b = c) : a = c := script
  calc
    a = b := by
      script_calc
        a = d := had
        _ = b := hdb
    _ = c := hbc

-- Replaying a nested recorder must not leak temporary recording steps.
#page theorem nestedRecorded (a b c d : Nat)
    (had : a = d) (hdb : d = b) (hbc : b = c) : a = c := script
  calc
    a = b := script
      calc
        a = d := had
        _ = b := hdb
    _ = c := hbc

-- The target resolves the element type after the chain has been elaborated.
#page theorem polymorphic : ([] : List Nat) = [] := script
  calc
    [] = [] := rfl

-- The preceding right side supplies Int as the type of the leading hole.
#page theorem numericChain (a : Int) (h : a = 0) : a ≤ 1 := script
  calc
    a = 0 := h
    _ ≤ 1 := by decide

def AliasEq (a b : Nat) := a = b

-- Record the relation written in the step, including definitionally equal aliases.
#page theorem aliasRelation (a b : Nat) (h : a = b) : AliasEq a b := script
  calc
    AliasEq a b := h

end CalcRecorderTest

script_recorder renderCalc => do
  execute
  record_value "extended_recorder" true

namespace CalcRecorderTest

#page theorem versioned (a b c : Nat) (hab : a = b) (hbc : b = c) : a = c := script
  calc
    a = b := hab
    _ = c := hbc

-- Inspect exported values so a proof that elaborates with incorrect capture
-- destinations or incomplete recorder fields still fails the regression test.
run_cmd do
  let moduleName ← getMainModule
  for (name, expectedBefore, expectedInit, expectedRhs, expectedRelations, expectedAfter) in [
      (`chain, "a = c", "a", #["b", "c"], #["Eq", "Eq"], none),
      (`mixedRelations, "a < c", "a", #["b", "c"], #["LE.le", "LT.lt"], none),
      (`implicitFirst, "a = b", "a", #["a", "b"], #["Eq", "Eq"], none),
      (`hole, "a = b", "a", #["b"], #["Eq"], some "a = b"),
      (`extended, "a = c", "a", #["b"], #["Eq"], some "b = c"),
      (`nestedUnrecorded, "a = c", "a", #["b", "c"], #["Eq", "Eq"], none),
      (`nestedRecorded, "a = c", "a", #["b", "c"], #["Eq", "Eq"], none),
      (`polymorphic, "[] = []", "[]", #["[]"], #["Eq"], none),
      (`numericChain, "a ≤ 1", "a", #["0", "1"], #["Eq", "LE.le"], none),
      (`aliasRelation, "AliasEq a b", "a", #["b"], #["AliasEq"], none),
      (`versioned, "a = c", "a", #["b", "c"], #["Eq", "Eq"], none)] do
    let path ← Elab.Command.liftIO <| activeOutputPath
      (proofOutputPath moduleName (`CalcRecorderTest ++ name))
    let .ok document := Json.parse (← Elab.Command.liftIO <| IO.FS.readFile path)
      | throwError "{name}: invalid recorded proof"
    let .ok steps := document.getObjValAs? (Array Json) "proof"
      | throwError "{name}: missing recorded steps"
    unless steps.size == (if expectedAfter.isSome then 2 else 1) do
      throwError "{name}: unexpected number of recorded steps"
    let .ok expressions := document.getObjVal? "expressions"
      | throwError "{name}: missing expression table"
    let expressionDetail (value : Json) (field : String) : Elab.Command.CommandElabM String := do
      let .ok ref := value.getObjValAs? String "$ref"
        | throwError "{name}: expected an expression reference"
      let .ok text := expressions.getObjVal? ref >>= (·.getObjVal? "data") >>=
          (·.getObjValAs? String field)
        | throwError "{name}: missing expression detail {field}"
      return text
    let expressionText (value : Json) := expressionDetail value "ProofScript.exprText"
    let step := steps[0]!
    unless step.getObjValAs? String "$ruleId" == .ok "renderCalc" do
      throwError "{name}: incorrect recorder rule"
    let .ok before := step.getObjVal? "$goal_before" | throwError "{name}: missing goal before"
    unless (← expressionText before) == expectedBefore do
      throwError "{name}: incorrect initial goal"
    let .ok init := step.getObjVal? "init" | throwError "{name}: missing initial term"
    unless (← expressionText init) == expectedInit do
      throwError "{name}: incorrect initial term"
    if name == `polymorphic then
      unless (← expressionDetail init "ProofScript.exprType") == "List ℕ" do
        throwError "the recording replay did not resolve the target's element type"
    let .ok chain := step.getObjValAs? (Array Json) "chain"
      | throwError "{name}: missing calculation chain"
    unless chain.size == expectedRhs.size do
      throwError "{name}: incorrect chain length"
    for entry in chain, rhs in expectedRhs, expectedRelation in expectedRelations do
      let .ok relation := entry.getObjVal? "relation" | throwError "{name}: missing relation"
      unless (← expressionText relation) == expectedRelation do
        throwError "{name}: incorrect relation"
      let .ok actual := entry.getObjVal? "rhs" | throwError "{name}: missing right side"
      unless (← expressionText actual) == rhs do
        throwError "{name}: incorrect right side"
      let .ok proof := entry.getObjVal? "proof" | throwError "{name}: missing proof"
      if name == `hole then
        unless proof.getObjValAs? String "kind" == .ok "hole" do
          throwError "{name}: synthetic proof hole was not preserved"
      else
        let _ ← expressionText proof
    let .ok after := step.getObjVal? "$goal_after" | throwError "{name}: missing goal after"
    match expectedAfter with
    | none => unless after == .null do throwError "{name}: expected a closed goal"
    | some expected =>
      unless (← expressionText after) == expected do
        throwError "{name}: incorrect remaining goal"
    if name == `versioned then
      unless step.getObjValAs? Bool "extended_recorder" == .ok true do
        throwError "execute did not extend the existing calc recorder"

end CalcRecorderTest
