import ProofScript.Script.Recording.Expression
import ProofScript.Utils.Json

open Lean Elab Tactic


namespace ProofScript

/-- Elaborate and read an expression in the current recording context. -/
def expression (raw : Syntax) : TacticM RecordedValue := do
  let action : TacticM RecordedValue := do
    recordExpression (← elabTerm raw none) (← trustedSyntaxSource? raw)
  if (← getUnsolvedGoals).isEmpty then
    action
  else
    withMainContext action

/-- Explicit source-syntax interpretation for categories with no semantic reader. -/
def syntaxText (value : Syntax) : TacticM RecordedValue :=
  return .plain <| toJson (value.reprint.getD (reprStr value))

/-- Read the type of an expression-capable input. -/
def expressionType (raw : Syntax) : TacticM RecordedValue := do
  let action : TacticM RecordedValue :=
    recordExpression (← Meta.inferType (← elabTerm raw none))
  if (← getUnsolvedGoals).isEmpty then
    action
  else
    withMainContext action

section
variable {α : Type}

namespace ParamRecorder

scoped instance : RecordValue (TSyntax `term) where
  record value _ := expression value.raw

scoped instance : RecordValue (TSyntax `ident) where
  record value _ := expression value.raw

scoped instance : RecordValue (TSyntax `str) where
  record value _ := return .plain <| Json.str value.getString

scoped instance : RecordValue (TSyntax `num) where
  record value _ := return .plain <| toJson value.getNat

/- A separated parser produces Lean's typed separator array.  Its elements are
   ordinary syntax nodes, so the existing Array instance performs the actual
    record while this instance only removes the separator representation. -/
scoped instance {k sep} [RecordValue (TSyntax k)] : RecordValue (Syntax.TSepArray k sep) where
  record value context := RecordValue.record value.getElems context

end ParamRecorder

end

end ProofScript
