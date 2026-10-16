import ProofScript.Script.Recording.Codec

namespace ProofScript.Recording

open Lean Elab Tactic

inductive CaptureTiming where
| once
| before
| after
| both
deriving Inhabited, BEq, Repr

inductive FailurePolicy where
| required
| bestEffort
deriving Inhabited, BEq, Repr

/-- The role of a goal after strategy execution. Branch labels are resolved by the
    strategy adapter, not by guessing from the tactic's name. -/
inductive ContextSelector where
| main
| continuation
| branch (name : String)
deriving Inhabited, BEq, Repr

/-- Per-parameter choice of interpretation, independent of the parser category. -/
inductive ParamCodec where
| default
| expression
| typeOf
| name
| syntax
deriving Inhabited, BEq, Repr

/-- One capture, executed wherever its group is placed. -/
structure ParamCapture where
  name : String
  /-- Emitted name; automatic `both` captures keep the logical name for diagnostics. -/
  field : String := name
  onFailure : FailurePolicy := .bestEffort
  context : ContextSelector := .main
  collectReferences : Bool := true
  capture : TacticM RecordedValue

/-- Validate both logical names and emitted names against the recording envelope. -/
def validateOutputFields (parameters : List (String × CaptureTiming)) : Except String Unit := do
  let reserved := ["_ruleId", "branches"]
  let mut bases : List String := []
  let mut names : List String := []
  for (name, timing) in parameters do
    if name.isEmpty then throw "recorded parameter field must not be empty"
    if reserved.contains name then throw s!"reserved recorded parameter field `{name}`"
    if bases.contains name then throw s!"duplicate recorded parameter field `{name}`"
    bases := name :: bases
    let emitted := if timing == .both then
      [name ++ "_before", name ++ "_after"]
    else [name]
    for name in emitted do
      if reserved.contains name then throw s!"reserved recorded parameter field `{name}`"
      if names.contains name then
        throw s!"duplicate recorded parameter field `{name}`"
      names := name :: names

/-- Check a capture group's output fields and report invalid names or collisions. -/
def validateCaptures (parameters : Array ParamCapture) : TacticM Unit := do
  if let .error message := validateOutputFields
      (parameters.toList.map fun p => (p.field, .once)) then
    throwError "{message}"

/-- A goal snapshot uses the same capture and commit path as any other parameter. -/
def goalParam (name : String) (goal : Option MVarId := none) : ParamCapture :=
  { name, onFailure := .required, collectReferences := false, capture := goalSnapshot goal }

def param (shape : ParamShape) [RecordParam shape] (name : String)
    (value : ParamInput shape)
    (onFailure : FailurePolicy := .bestEffort) : ParamCapture :=
  { name, onFailure, capture := RecordParam.capture value }

/-- Explicit codecs apply to a single syntax node without requiring a category instance.
    Containers use `param` and the derived RecordParam instances. -/
def explicitParam (name : String) (codec : ParamCodec)
    (raw : Syntax) (context : ContextSelector := .main)
    (failure : FailurePolicy := .bestEffort) : ParamCapture :=
  { name, context, onFailure := failure, capture := match codec with
    | .expression => expression raw
    | .typeOf => expressionType raw
    | .name => do
      unless raw.isIdent do throwError "name codec requires an identifier: {repr raw}"
      return .scalar (Json.str raw.getId.eraseMacroScopes.toString)
    | .syntax => syntaxText raw
    | .default => throwError "default codec requires a RecordParam instance" }

end ProofScript.Recording
