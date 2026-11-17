import ProofScript.Info.ExtraFields
import ProofScript.Core.Codec
import ProofScript.Core.Language
import ProofScript.Info.Template
import ProofScript.Info.ObjectCodec

open Lean


namespace ProofScript

inductive DeclKind where
| «concept»
| «theorem»
| «operator»
| «relation»
| «alias»
| «wrapper»
deriving BEq, ToJson, InfoCodec

structure DefinitionTemplate where
  label : String
  lang : OptionalInput Language := {}
  content : TemplateContent
deriving Inhabited, BEq, ToJson, InfoCodec

/-- Language constructor metadata is not part of a template's identity. -/
def DefinitionTemplate.key (template : DefinitionTemplate) : String × Option String :=
  (template.label, template.lang.value.map (·.code))

def DefinitionTemplate.mode (template : DefinitionTemplate) : DisplayMode := template.content.mode

structure InternationalName where
  lang : OptionalInput Language := {}
  value : String
deriving Inhabited, BEq, ToJson, InfoCodec

def InternationalName.key (entry : InternationalName) : Option String :=
  entry.lang.value.map (·.code)

structure DeclInfo where
  /-- At most one display name per language; an empty list uses the Lean name. -/
  names : List InternationalName := []
  /-- Ordered declaration tags; multiple tags may share a language. -/
  tags : List InternationalName := []
  /-- Variable-name prefix for this type; an empty string requests automatic naming. -/
  var_name : String := ""
  kind : DeclKind := .concept
  /-- Zero-based raw application index, including implicit parameters. -/
  wrapper_index : Option Nat := none
  alias_target : Option DeclarationRef := none
  templates : Array DefinitionTemplate := #[]
  /-- none selects the final list's first label when frozen; stale labels may fall back. -/
  default_template : Option String := none
  /-- Plain calc text; aliases consume the final target's value/name instead. -/
  calc_symbol : Option String := none
  /-- Theorem parameter text template: #self, #type and explicit type arguments #N.
      Formula fragments use dollar delimiters. -/
  parameter_template : Option String := none
  extra : ExtraFields := {}

end ProofScript
