import ProofScript.Builtin.Scripts.Cite
import ProofScript.Builtin.Scripts.Trivial
import ProofScript.Script.Script

open Lean ProofScript

namespace CiteTest

theorem named (P : Prop) (h : P) : P := h
set_option linter.defProp false in
def proofDefinition : True := True.intro
def proposition : Prop := True

run_cmd clearTheoremRefs

-- Synchronous proof helpers retain citations for later commands, as page theorems do.
-- Cite only the named declarations, without theorem_info or automatic collection.
set_option dependencyCollection false in
abbrev citations : True := script
  cite named
  cite Nat.add_comm
  cite proofDefinition
  cite named
  trivial

run_cmd do
  let expected : List RefInfo := [
    ⟨``named, false⟩, ⟨``Nat.add_comm, false⟩, ⟨``proofDefinition, false⟩]
  unless (← getTheoremRefs) == expected do
    throwError "cite must record exactly the named declarations, without duplicates"

/-- error: `Nat` should be a theorem -/
#guard_msgs in
example : True := by
  script_cite Nat
  exact True.intro

/-- error: `proposition` should be a theorem -/
#guard_msgs in
example : True := by
  script_cite proposition
  exact True.intro

run_cmd do
  let expected : List RefInfo := [
    ⟨``named, false⟩, ⟨``Nat.add_comm, false⟩, ⟨``proofDefinition, false⟩]
  unless (← getTheoremRefs) == expected do
    throwError "rejected citations must preserve the existing references"

run_cmd clearTheoremRefs

-- Global name resolution does not depend on local variables or an open goal.
abbrev shadowed (named : Nat) : True := by
  script_cite named
  have _ := named
  exact True.intro
  script_cite named

run_cmd do
  unless (← getTheoremRefs) == [⟨``named, false⟩] do
    throwError "cite must resolve a global theorem even without a main goal"
  stageTheoremRef ⟨``named, true⟩

abbrev dependency : True := by
  script_cite named
  exact True.intro

run_cmd do
  unless (← getTheoremRefs) == [⟨``named, true⟩] do
    throwError "a citation must preserve an existing automatic dependency"
  clearTheoremRefs

end CiteTest
