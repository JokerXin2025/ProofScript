import ProofScript.Core.Codec

open Lean

namespace ProofScript

inductive DisplayMode where
| text
| formula
deriving BEq, ToJson, InfoCodec, Inhabited

/-- Typed template fragments; body selection never depends on counting @ signs. -/
inductive TemplateAtom where
| literal (content : String)
| argument (index : Nat) (max_precedence : Bool := false)
| binder (index layer : Nat) (max_precedence : Bool := false)
| body (index depth : Nat) (max_precedence : Bool := false)
deriving BEq, ToJson

inductive TemplatePart where
| atom (value : TemplateAtom)
| modeSwitch (parts : Array TemplateAtom)
deriving BEq, ToJson

structure TemplateContent where
  mode : DisplayMode := .formula
  precedence : Option Nat := none
  auto_arity : Bool := true
  parts : Array TemplatePart := #[]
deriving BEq, ToJson, Inhabited

declare_syntax_cat templateAtom
syntax str : templateAtom
syntax "arg(" num ")" : templateAtom
syntax "arg!(" num ")" : templateAtom
syntax "binder(" num "," num ")" : templateAtom
syntax "binder!(" num "," num ")" : templateAtom
syntax "body(" num "," num ")" : templateAtom
syntax "body!(" num "," num ")" : templateAtom
declare_syntax_cat templateTextPart
syntax templateAtom : templateTextPart
syntax (name := templateInlineMath) &"$" templateAtom+ &"$" : templateTextPart
syntax templatePriority := ":" num
syntax templateRaw := &"raw"
syntax (name := templateText) "template%" (templatePriority)? (templateRaw)? "{" templateTextPart* "}" : term
syntax (name := templateFormula) "template%" (templatePriority)? (templateRaw)? "${" templateTextPart* "}$" : term

private def decodeTemplateAtom : TSyntax `templateAtom → CoreM TemplateAtom
| `(templateAtom| $text:str) => do
    if text.getString.contains '$' then
      throwErrorAt text "use $ ... $ outside strings for inline math; literal dollar signs are not supported"
    return .literal text.getString
| `(templateAtom| arg($index:num)) =>
    return .argument index.getNat
| `(templateAtom| arg!($index:num)) =>
    return .argument index.getNat true
| `(templateAtom| binder($index:num, $layer:num)) => do
    if layer.getNat == 0 then
      throwErrorAt layer "binder layers start at 1"
    return .binder index.getNat layer.getNat
| `(templateAtom| binder!($index:num, $layer:num)) => do
    if layer.getNat == 0 then
      throwErrorAt layer "binder layers start at 1"
    return .binder index.getNat layer.getNat true
| `(templateAtom| body($index:num, $depth:num)) =>
    return .body index.getNat depth.getNat
| `(templateAtom| body!($index:num, $depth:num)) =>
    return .body index.getNat depth.getNat true
| stx =>
    throwErrorAt stx "expected a template fragment"

instance : InfoCodec TemplateContent where
  decode stx := do
    unless stx.raw.isOfKind ``templateText || stx.raw.isOfKind ``templateFormula do
      throwErrorAt stx "expected a template% literal"
    let mode := if stx.raw.isOfKind ``templateText then DisplayMode.text else .formula
    let precedence ← match stx.raw[1].getArgs[0]? with
      | none => pure none
      | some priority =>
        match priority[1].isNatLit? with
        | some value => pure (some value)
        | none => throwErrorAt priority "expected a numeric template precedence"
    if precedence.any (· > 100) then throwErrorAt stx.raw[1] "precedence exceeds 100"
    let mut result := #[]
    for raw in stx.raw[4].getArgs do
      let part : TSyntax `templateTextPart := ⟨raw⟩
      match part with
      | `(templateTextPart| $atom:templateAtom) =>
        result := result.push (.atom (← decodeTemplateAtom atom))
      | _ =>
        unless part.raw.isOfKind ``templateInlineMath do
          throwErrorAt part "expected a template fragment or mode switch"
        let atoms ← part.raw[1].getArgs.mapM fun atom => decodeTemplateAtom ⟨atom⟩
        result := result.push (.modeSwitch atoms)
    return { mode, precedence, auto_arity := stx.raw[2].getArgs.isEmpty, parts := result }

def TemplateContent.atoms (content : TemplateContent) : Array TemplateAtom :=
  content.parts.flatMap fun part =>
    match part with
    | .atom value => #[value]
    | .modeSwitch values => values

def DisplayMode.flip : DisplayMode → DisplayMode
| .text => .formula
| .formula => .text

private def TemplateAtom.display : TemplateAtom → String
| .literal text => text
| .argument index max => s!"arg{if max then "!" else ""}({index})"
| .binder index layer max => s!"binder{if max then "!" else ""}({index}, {layer})"
| .body index depth max => s!"body{if max then "!" else ""}({index}, {depth})"

/-- Inspection-only spelling, never parsed by a renderer. -/
def TemplateContent.display (content : TemplateContent) : String :=
  String.join <| content.parts.toList.map fun part =>
    match part with
    | .atom value => value.display
    | .modeSwitch values => "$" ++ String.join (values.toList.map TemplateAtom.display) ++ "$"

inductive DefinitionTemplateInstruction where
| literal (content : String)
| argument (index : Nat) (mode : DisplayMode) (max_precedence : Bool := false)
| binder (index depth : Nat) (mode : DisplayMode) (max_precedence : Bool := false)
| body (index depth : Nat) (mode : DisplayMode) (max_precedence : Bool := false)
| modeSwitch (mode : DisplayMode) (instructions : Array DefinitionTemplateInstruction)
deriving BEq

private partial def instructionJson : DefinitionTemplateInstruction → Json
| .literal content => json% { kind: "literal", content: $content }
| .argument index mode max => json% { kind: "argument", index: $index, mode: $mode, max_precedence: $max }
| .binder index depth mode max => json% { kind: "binder", index: $index, depth: $depth, mode: $mode, max_precedence: $max }
| .body index depth mode max => json% { kind: "body", index: $index, depth: $depth, mode: $mode, max_precedence: $max }
| .modeSwitch mode instructions => json% { kind: "mode_switch", mode: $mode,
    instructions: $(instructions.map instructionJson) }

instance : ToJson DefinitionTemplateInstruction := ⟨instructionJson⟩

def DefinitionTemplateInstruction.flatten (instructions : Array DefinitionTemplateInstruction) :
    Array DefinitionTemplateInstruction :=
  instructions.flatMap fun instruction =>
    match instruction with
    | .modeSwitch _ children => children
    | other => #[other]

/-- The separate parameter-description protocol still uses #self/#type/#N.
     This scanner is not used by declaration display templates. -/
structure ParameterTemplateReferences where
  arguments : Array Nat := #[]
  unsupported : Bool := false

/-- Scan the legacy parameter-description protocol only. -/
def parameterTemplateReferences (template : String) : ParameterTemplateReferences := Id.run do
  let chars := template.toList.toArray
  let mut result : ParameterTemplateReferences := {}
  let mut index := 0
  while index < chars.size do
    if chars[index]! == '#' && index + 1 < chars.size then
      if chars[index + 1]! == '*' then result := { result with unsupported := true }
      index := index + 1
      let start := index
      let mut value := 0
      while index < chars.size && chars[index]!.isDigit do
        value := value * 10 + chars[index]!.toNat - '0'.toNat
        index := index + 1
      if index > start then
        result := { result with arguments := result.arguments.push value }
    else if chars[index]! == '@' then
      while index < chars.size && chars[index]! == '@' do index := index + 1
      if index < chars.size && chars[index]!.isDigit then
        result := { result with unsupported := true }
    else index := index + 1
  return result

end ProofScript
