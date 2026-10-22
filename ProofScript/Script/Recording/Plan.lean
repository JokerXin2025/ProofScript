import ProofScript.Script.Recording.Display

namespace ProofScript.Recording

open Lean Elab Tactic

inductive FailurePolicy where
| required
| bestEffort
deriving Inhabited, BEq, Repr

/-- A capture's goal context. Strategy selectors are resolved by the recorder scope
    against the goals present when the capture runs. -/
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
  /-- Explicit companion opt-in; ordinary captures keep their original value contract. -/
  display : Bool := false
  displaySource : Option Syntax := none
  capture : CaptureM RecordedData

/-- Check one output name against the recording envelope. -/
def validateFieldName (name : String) : Except String Unit := do
  if name.isEmpty then throw "recorded parameter field must not be empty"
  if ["_ruleId", "branches"].contains name then
    throw s!"reserved recorded parameter field `{name}`"

/-- A goal snapshot uses the same capture and commit path as any other parameter. -/
def goalParam (name : String) (goal : Option MVarId := none) : ParamCapture :=
  { name, onFailure := .required, collectReferences := false, capture := goalSnapshot goal }

/-- A goal and its explicit display companion captured at the same point. -/
def goalParamWithDisplay (name : String) (goal : Option MVarId := none) : ParamCapture :=
  { goalParam name goal with display := true }

def param (shape : ParamShape) [RecordParam shape] (name : String)
    (value : ParamInput shape)
    (onFailure : FailurePolicy := .bestEffort) : ParamCapture :=
  { name, onFailure, capture := RecordParam.capture value }

/-- Opt into a companion only when the codec's declared schema contains expressions. -/
def paramWithDisplay (shape : ParamShape) [RecordParam shape] (name : String)
    (value : ParamInput shape) (onFailure : FailurePolicy := .bestEffort) : ParamCapture :=
  { param shape name value onFailure with display := (RecordParam.schema shape).hasExpressions }

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
      return .plain (Json.str raw.getId.eraseMacroScopes.toString)
    | .syntax => syntaxText raw
    | .default => throwError "default codec requires a RecordParam instance" }

def explicitParamWithDisplay (name : String) (codec : ParamCodec)
    (raw : Syntax) (context : ContextSelector := .main)
    (failure : FailurePolicy := .bestEffort) : ParamCapture :=
  { explicitParam name codec raw context failure with
    display := codec == .expression || codec == .typeOf, displaySource := some raw }

end ProofScript.Recording
