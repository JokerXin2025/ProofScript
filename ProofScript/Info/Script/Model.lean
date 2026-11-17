import ProofScript.Info.ObjectCodec
import ProofScript.Info.ExtraFields
import ProofScript.Core.Language
import ProofScript.Core.Color

namespace ProofScript

open Lean

inductive ScriptRenderer where
| «default»
| «remark»
| «admit»
| «svg»
| «calc»
| «infer»
deriving BEq, ToJson, InfoCodec

structure ScriptColor where
  tag : Option RGBA := none
  border : Option RGBA := none
  background : Option RGBA := none
deriving ToJson

instance : InfoCodec ScriptColor where
  decode := fun stx => do
    if let `(term| ($tag:term, $border:term, $background:term)) := stx then
      return ScriptColor.mk (← InfoCodec.decode tag) (← InfoCodec.decode border) (← InfoCodec.decode background)
    (decodeObjectFields% ScriptColor) stx
  annotate := annotateObjectFields% ScriptColor

structure ScriptIntroducer where
  tag : String
  content : String
deriving BEq, ToJson, InfoCodec

structure ScriptCase where
  name : String
  tag : String
  title : String
  introducer : OptionalInput ScriptIntroducer := {}
deriving Inhabited, BEq, ToJson, InfoCodec

structure OrdinaryScriptTemplate where
  lang : Language
  tag : String
  content : String
deriving Inhabited, BEq, ToJson, InfoCodec

structure StrategyScriptTemplate where
  lang : Language
  tag : String
  inline : Bool := false
  introducer : OptionalInput ScriptIntroducer := {}
  cases : Array ScriptCase
deriving BEq, ToJson, InfoCodec

structure DynamicScriptCase where
  tag : String
  title : String
  introducer : OptionalInput ScriptIntroducer := {}
deriving BEq, ToJson, InfoCodec

structure DynamicStrategyScriptTemplate where
  lang : Language
  tag : String
  introducer : OptionalInput ScriptIntroducer := {}
  case : DynamicScriptCase
deriving BEq, ToJson, InfoCodec

inductive ScriptTemplate where
| ordinary (value : OrdinaryScriptTemplate)
| strategy (value : StrategyScriptTemplate)
| dynamicStrategy (value : DynamicStrategyScriptTemplate)
deriving Inhabited, BEq

instance : ToJson ScriptTemplate where
  toJson
  | .ordinary value => json% { kind: "ordinary", value: $value }
  | .strategy value => json% { kind: "strategy", value: $value }
  | .dynamicStrategy value => json% { kind: "dynamicStrategy", value: $value }

instance : InfoCodec ScriptTemplate where
  decode stx := do
    let fields ← readObject stx
    if fields.any (objectFieldName · == "cases") then return .strategy (← InfoCodec.decode stx)
    if fields.any (objectFieldName · == "case") then return .dynamicStrategy (← InfoCodec.decode stx)
    return .ordinary (← InfoCodec.decode stx)
  annotate stx := do
    if let some fields ← readObjectForAnnotations? stx then
      if fields.any (objectFieldName · == "cases") then
        InfoCodec.annotate (α := StrategyScriptTemplate) stx
      else if fields.any (objectFieldName · == "case") then
        InfoCodec.annotate (α := DynamicStrategyScriptTemplate) stx
      else InfoCodec.annotate (α := OrdinaryScriptTemplate) stx

def ScriptTemplate.lang : ScriptTemplate → String
| .ordinary value => value.lang.code
| .strategy value => value.lang.code
| .dynamicStrategy value => value.lang.code

def ScriptTemplate.isStrategy : ScriptTemplate → Bool
| .ordinary _ => false
| .strategy _ => true
| .dynamicStrategy _ => true

/-- The ordered script board's input grammar, distinct from an ordinary list codec. -/
structure ScriptBoardInput where
  value : List (String × String) := []
deriving BEq

/-- Encode board entries in order, retaining duplicate display names. -/
instance : ToJson ScriptBoardInput where
  toJson board := toJson <| board.value.map fun (name, value) =>
    json% { name: $name, value: $value }

/-- Parse an ordered list of board entries, preserving duplicate display names. -/
instance : InfoCodec ScriptBoardInput where
  decode
  | `(term| [$[$items:term],*]) =>
      return {
        value := Array.toList <|
          ← items.mapM fun item => do
            let `(term| ($name:term, $value:term)) := item
            | throwErrorAt item "expected (name, value)"
            return (← InfoCodec.decode name, ← InfoCodec.decode value)
      }
  | stx => throwErrorAt stx "expected a list of (name, value) pairs"
  annotate
  | `(term| [$[$items:term],*]) => items.forM fun item => do
      if let `(term| ($name:term, $value:term)) := item then
        InfoCodec.annotate (α := String) name
        InfoCodec.annotate (α := String) value
  | _ => pure ()

structure ScriptInfo where
  renderer : ScriptRenderer := .default
  templates : Array ScriptTemplate := #[]
  display : Bool := true
  color : ScriptColor := {}
  board : ScriptBoardInput := {}
  extra : ExtraFields := {}
deriving ToJson

end ProofScript
