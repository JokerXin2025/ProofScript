import ProofScript.Info.Derive
import ProofScript.Info.Target
import ProofScript.Info.Template

namespace ProofScript.Info

open Lean

inductive DefinitionKind where
  | const | operator | relation | logic | projection | constructor | type
  deriving Inhabited, Repr, BEq

instance : InfoCodec DefinitionKind := enumCodec #[
  ("const", .const), ("operator", .operator), ("relation", .relation), ("logic", .logic),
  ("projection", .projection), ("constructor", .constructor), ("type", .type)]

inductive StyleMode where
| formula
| text
deriving Inhabited, Repr, BEq

instance : InfoCodec StyleMode := enumCodec #[("formula", .formula), ("text", .text)]

inductive StyleFixity where
  | atom | prefix | postfix | infix | binder | application | custom
  deriving Inhabited, Repr, BEq

instance : InfoCodec StyleFixity := enumCodec #[
  ("atom", .atom), ("prefix", .prefix), ("postfix", .postfix), ("infix", .infix),
  ("binder", .binder), ("application", .application), ("custom", .custom)]

inductive StyleAssociativity where
| left
| right
| none
deriving Inhabited, Repr, BEq

instance : InfoCodec StyleAssociativity := enumCodec #[("left", .left), ("right", .right), ("none", .none)]

inductive DefinitionArguments where
| explicit
| indices (values : Array Nat)
deriving Inhabited, Repr, BEq

private def uniqueIndices (values : Array Nat) : Except String Unit :=
  if values.toList.eraseDups.length == values.size then .ok () else .error "duplicate argument index"

instance : InfoCodec DefinitionArguments where
  parse stx := do
    match stx with
    | `(term| explicit) => return .explicit
    | _ =>
        let values ← InfoCodec.parse stx
        if let .error message := uniqueIndices values then throwErrorAt stx message
        return .indices values
  toJson
  | .explicit => json% "explicit"
  | .indices values => toJson values
  decode value := do
    if value == (json% "explicit") then return .explicit
    let values ← InfoCodec.decode value
    (uniqueIndices values).mapError fun message => { message }
    return .indices values
  jsonSchema := json% {
    anyOf: [
      { const: "explicit" },
      $((InfoCodec.jsonSchema (Array Nat)).setObjVal! "uniqueItems" (json% true))
    ]
  }

structure BinderSelector where
  argument : Nat
  count : Nat
  deriving Inhabited, Repr, BEq

instance : InfoCodec BinderSelector where
  parse stx := do
    let `(term| ($index:term, $count:term)) := stx
      | throwErrorAt stx "expected (argument index, binder count)"
    let count ← InfoCodec.parse count
    if count == 0 then throwErrorAt stx "binder count must be positive"
    return { argument := ← InfoCodec.parse index, count }
  toJson value := toJson #[value.argument, value.count]
  decode value := do
    let values ← InfoCodec.decode (α := Array Nat) value
    unless values.size == 2 do throw { message := "expected an argument/count pair" }
    if values[1]! == 0 then throw { message := "binder count must be positive" }
    return { argument := values[0]!, count := values[1]! }
  jsonSchema := json% {
    type: "array",
    minItems: 2,
    maxItems: 2,
    prefixItems: [
      $(InfoCodec.jsonSchema Nat),
      $((InfoCodec.jsonSchema Nat).setObjVal! "minimum" (json% 1))
    ]
  }

structure DefinitionStyle where
  name : String := "formula"
  mode : StyleMode := .formula
  template : String
  fixity : StyleFixity := .custom
  precedence : Nat := 100
  associativity : StyleAssociativity := .none
  separator : String := ", "
  binders : Array BinderSelector := #[]
  isolated_arguments : Array Nat := #[]
  deriving Inhabited, InfoSchema

instance : InfoSchema DefinitionStyle :=
  (inferInstance : InfoSchema DefinitionStyle).withOverrides! {
    fields := #[
      DefinitionStyle.infoFields.precedence.withValidation fun value =>
        if value > 100 then .error "precedence exceeds 100" else .ok (),
      DefinitionStyle.infoFields.binders.withValidation fun values => do
        if values.any (·.count == 0) then throw "binder count must be positive"
        uniqueIndices (values.map (·.argument)),
      DefinitionStyle.infoFields.isolated_arguments.withValidation uniqueIndices] }

instance (priority := high) : InfoCodec (Option DefinitionKind) := optionalInputCodec
instance (priority := high) : InfoCodec (Option DefinitionArguments) := optionalInputCodec
instance (priority := high) : InfoCodec (Option (Array DefinitionStyle)) := optionalInputCodec

/-- Conditional defaults remain absent until consumption; explicit [] differs from omitted styles. -/
structure DefinitionInfo where
  kind : Option DefinitionKind := none
  arguments : Option DefinitionArguments := none
  dynamic_arity : Bool := false
  styles : Option (Array DefinitionStyle) := none
  calc_symbol : Option String := none
  unwrap : Option Nat := none
  alias : Option DeclarationRef := none
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

/-- The ordinary rendering mode after calc shorthand and conditional defaults are resolved. -/
structure DefinitionDisplay where
  kind : DefinitionKind
  arguments : DefinitionArguments
  dynamic_arity : Bool
  styles : Array DefinitionStyle
  deriving Inhabited

private def definitionConstraint (name message : String) (related : Array String := #[]) : Diagnostic :=
  { message, path := #[.key name], relatedPaths := related.map fun name => #[.key name] }

private def calcStyle (symbol : String) : DefinitionStyle :=
  let suffix := symbol.toList.reverse.takeWhile Char.isAlpha
  let control := !suffix.isEmpty && (symbol.toList.reverse.drop suffix.length).head? == some '\\'
  { template := s!"#0{symbol}{if control then " " else ""}#1", fixity := .infix, precedence := 50 }

def DefinitionInfo.display (value : DefinitionInfo) : Except Diagnostic DefinitionDisplay := do
  let kind := value.kind.getD (if value.calc_symbol.isSome then .relation else .const)
  let arguments := value.arguments.getD (if value.calc_symbol.isSome then .explicit else .indices #[])
  let styles ← match value.styles, value.calc_symbol with
    | some styles, _ => pure styles
    | none, some symbol =>
      let related := #[DefinitionInfo.infoFields.calc_symbol.name, DefinitionInfo.infoFields.styles.name]
      if kind != .relation then
        throw <| definitionConstraint DefinitionInfo.infoFields.kind.name "generated calc style requires relation kind" related
      if value.dynamic_arity || (match arguments with | .indices values => values.size != 2 | .explicit => false) then
        throw <| definitionConstraint DefinitionInfo.infoFields.arguments.name
          "generated calc style requires two selected arguments and fixed arity"
          (related.push DefinitionInfo.infoFields.dynamic_arity.name)
      pure #[calcStyle symbol]
    | none, none =>
      throw <| definitionConstraint DefinitionInfo.infoFields.styles.name
        "missing styles or calc_symbol" #[DefinitionInfo.infoFields.calc_symbol.name]
  if styles.isEmpty then throw <| definitionConstraint DefinitionInfo.infoFields.styles.name "at least one style is required"
  return { kind, arguments, styles, dynamic_arity := value.dynamic_arity }

private def validateStyle (display : DefinitionDisplay) (style : DefinitionStyle) : Except Diagnostic Unit := do
  let references := argumentReferences style.template
  let args := references.arguments ++ references.binders.map (·.1)
  let related := #[#[.key DefinitionStyle.infoFields.template.name]]
  if references.dynamic != display.dynamic_arity then
    throw { message := "dynamic placeholder #* must agree with dynamic_arity", path := #[.key DefinitionStyle.infoFields.template.name] }
  let sorted := args.toList.eraseDups.toArray.qsort (· < ·)
  if !display.dynamic_arity && (sorted.mapIdx fun index value => index == value).any (!·) then
    throw { message := "non-contiguous argument placeholders", path := #[.key DefinitionStyle.infoFields.template.name] }
  for (index, depth) in references.binders do
    let binder := style.binders.find? (·.argument == index)
    if binder.isNone || depth > (binder.map (·.count) |>.getD 0) + 1 then
      throw { message := "@ selector needs a matching binder count", path := #[.key DefinitionStyle.infoFields.binders.name], relatedPaths := related }
  if let .indices selected := display.arguments then
    if args.any (· >= selected.size) then
      throw { message := "template references a missing selected argument", path := #[.key DefinitionStyle.infoFields.template.name] }
    if style.binders.any (·.argument >= selected.size) then
      throw { message := "binder selector references a missing selected argument", path := #[.key DefinitionStyle.infoFields.binders.name], relatedPaths := related }
    if style.isolated_arguments.any (· >= selected.size) then
      throw { message := "isolated_arguments references a missing selected argument", path := #[.key DefinitionStyle.infoFields.isolated_arguments.name], relatedPaths := related }
  if !display.dynamic_arity && style.isolated_arguments.any (!args.contains ·) then
    throw { message := "isolated_arguments must reference a template argument", path := #[.key DefinitionStyle.infoFields.isolated_arguments.name], relatedPaths := related }

def validateDefinitionInfo (value : DefinitionInfo) : Except Diagnostic Unit := do
  if value.alias.isSome && value.unwrap.isSome then
    throw <| definitionConstraint DefinitionInfo.infoFields.alias.name "alias and unwrap are mutually exclusive"
      #[DefinitionInfo.infoFields.unwrap.name]
  -- Alias and unwrap modes preserve stored display fields for a later explicit mode switch.
  if value.alias.isSome || value.unwrap.isSome then return
  let display ← value.display
  let references := display.styles.map fun style => argumentReferences style.template
  if references.all (!·.binders.isEmpty) then
    throw <| definitionConstraint DefinitionInfo.infoFields.styles.name "a style without @ selectors is required"
  for index in [:display.styles.size] do
    (validateStyle display display.styles[index]!).mapError fun error =>
      { error with
        path := #[.key DefinitionInfo.infoFields.styles.name, .index index] ++ error.path
        relatedPaths := #[#[.key DefinitionInfo.infoFields.arguments.name],
          #[.key DefinitionInfo.infoFields.dynamic_arity.name], #[.key DefinitionInfo.infoFields.styles.name]] }

instance : InfoSchema DefinitionInfo :=
  (inferInstance : InfoSchema DefinitionInfo).withOverrides! {
    fields := #[DefinitionInfo.infoFields.calc_symbol.withValidation fun value =>
      if value.any String.isEmpty then .error "calc_symbol must not be empty" else .ok ()]
    validateRecord := validateDefinitionInfo }

def definitionSpec : InfoSpec DefinitionInfo := {
  kind := "definition"
  dependencies := fun value => value.alias.toList.toArray.map fun reference => ("definition", reference.name) }

private def aliasSources (info : ResolvedInfo DefinitionInfo) : Array RelatedSource :=
  info.provenance.filter (·.1 == .field DefinitionInfo.infoFields.alias.name)
    |>.flatMap fun (_, origins) => origins.map (·.related)

/-- Validate the entire static alias closure in the same module/boundary, retaining every edge's source.
Actual applications, explicit argument descriptors and selected lambda shapes are checked by the backend.
-/
def resolveDefinitionChain (env : Environment) (query : Query) (declaration : Name) :
    Except Diagnostic (Array (Name × ResolvedInfo DefinitionInfo)) := do
  let events ← queryEvents env query
  let mut current := declaration
  let mut chain : Array (Name × ResolvedInfo DefinitionInfo) := #[]
  let mut related : Array RelatedSource := #[]
  -- Every distinct alias node requires a configuration event, so this is a finite bound.
  for _ in [:events.size + 1] do
    let fail := fun (error : Diagnostic) => { error with
      kind := some definitionSpec.kind, target := some current.toString,
      related := (error.related ++ related).toList.eraseDups.toArray }
    if chain.any (·.1 == current) then
      let names := (chain.map (·.1.toString)).push current.toString
      let error : Diagnostic := {
        message := "alias cycle: " ++ String.intercalate " → " names.toList
        path := #[.key DefinitionInfo.infoFields.alias.name] }
      throw (fail error)
    unless env.contains current do throw <| fail { message := "unknown declaration in alias closure" }
    let info ← (resolveConfiguredInfo definitionSpec env query current).mapError fail
    chain := chain.push (current, info)
    match info.value.alias with
    | none => return chain
    | some reference =>
      related := related ++ aliasSources info
      current := reference.name
  throw { message := "alias closure exceeded its event bound", kind := some definitionSpec.kind, target := some declaration.toString }

def resolveDefinitionInfo (env : Environment) (query : Query) (declaration : Name) :
    Except Diagnostic (ResolvedInfo DefinitionInfo) := do
  let chain ← resolveDefinitionChain env query declaration
  let some (_, info) := chain[0]? | throw { message := "empty definition closure" }
  return info

end ProofScript.Info
