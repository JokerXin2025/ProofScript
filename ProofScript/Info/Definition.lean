import ProofScript.Info.Derive
import ProofScript.Info.Target
import ProofScript.Info.Template
import ProofScript.Utils.Ascii
import ProofScript.Info.Script

namespace ProofScript

open Lean

inductive DefinitionKind where
  | concept | wrapper | relation | operator | alias
  deriving Inhabited, Repr, BEq

instance : InfoCodec DefinitionKind := enumCodec #[
  ("concept", .concept), ("wrapper", .wrapper), ("relation", .relation), ("operator", .operator),
  ("alias", .alias)]

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

private def uniqueIndices (values : Array Nat) : Except String Unit :=
  if values.toList.eraseDups.length == values.size then .ok () else .error "duplicate argument index"

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

instance (priority := high) : InfoCodec (Option Language) := optionalInputCodec

structure DefinitionTemplate where
  label : String
  lang : Option Language := none
  mode : StyleMode := .formula
  content : String
  binders : Array BinderSelector := #[]
  isolated_arguments : Array Nat := #[]
  deriving Inhabited, InfoSchema

instance : InfoSchema DefinitionTemplate :=
  (inferInstance : InfoSchema DefinitionTemplate).withOverrides! {
    fields := #[
      DefinitionTemplate.infoFields.label.withValidation fun value =>
        if isNonemptyBasicAscii value then .ok () else .error "label must be a nonempty printable ASCII string",
      DefinitionTemplate.infoFields.lang.withValidation fun value =>
        if value.any (·.code.isEmpty) then .error "lang must not be empty" else .ok ()
    ]
    ++ #[
      DefinitionTemplate.infoFields.binders.withValidation fun values => do
        if values.any (·.count == 0) then throw "binder count must be positive"
        uniqueIndices (values.map (·.argument)),
      DefinitionTemplate.infoFields.isolated_arguments.withValidation uniqueIndices] }

structure ConceptInfo where
  auto_arity : Bool := true
  templates : Array DefinitionTemplate := #[]
  default : String := "formula"
  deriving Inhabited, InfoSchema

/-- Symbolic operator layout. -/
structure OperatorInfo where
  symbol : String := ""
  fixity : StyleFixity := .infix
  precedence : Nat := 100
  associativity : StyleAssociativity := .none
  deriving Inhabited, InfoSchema

instance : InfoSchema OperatorInfo :=
  (inferInstance : InfoSchema OperatorInfo).withOverrides! {
    fields := #[OperatorInfo.infoFields.precedence.withValidation fun value =>
      if value > 100 then .error "precedence exceeds 100" else .ok ()] }

structure RelationInfo where
  symbol : String := ""
  deriving Inhabited, InfoSchema

structure WrapperInfo where
  index : Option Nat := none
  deriving Inhabited, InfoSchema

structure AliasInfo where
  target : Option DeclarationRef := none
  deriving Inhabited, InfoSchema

structure DefinitionInfo where
  /-- Variable-name prefix for this type; an empty string requests automatic naming. -/
  var_name : String := ""
  kind : DefinitionKind := .concept
  concept_info : ConceptInfo := {}
  operator_info : OperatorInfo := {}
  relation_info : RelationInfo := {}
  wrapper_info : WrapperInfo := {}
  alias_info : AliasInfo := {}
  /-- Theorem parameter text template: #self, #type and explicit type arguments #N.
      Formula fragments use dollar delimiters. -/
  parameter_template : Option String := none
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

/-- Concept templates and argument selection. -/
structure DefinitionDisplay where
  kind : DefinitionKind
  auto_arity : Bool
  templates : Array DefinitionTemplate
  deriving Inhabited

private def definitionConstraint (name message : String) : Diagnostic :=
  { message, path := #[.key name] }

private def templateConstraint (index : Nat) (field message : String) : Diagnostic :=
  { message, path := #[.key "concept_info", .key "templates", .index index, .key field] }

def DefinitionInfo.display (value : DefinitionInfo) : Except Diagnostic DefinitionDisplay := do
  let info := value.concept_info
  return ⟨value.kind, info.auto_arity, info.templates⟩

private def validateTemplate (display : DefinitionDisplay) (template : DefinitionTemplate) : Except Diagnostic Unit := do
  let references := argumentReferences template.content
  let args := references.arguments ++ references.binders.map (·.1)
  if references.wildcard then
    throw { message := "dynamic placeholder #* is no longer supported", path := #[.key DefinitionTemplate.infoFields.content.name] }
  let sorted := args.toList.eraseDups.toArray.qsort (· < ·)
  if display.auto_arity && (sorted.mapIdx fun index value => index == value).any (!·) then
    throw { message := "non-contiguous argument placeholders", path := #[.key DefinitionTemplate.infoFields.content.name] }
  for (index, depth) in references.binders do
    let binder := template.binders.find? (·.argument == index)
    if binder.isNone || depth > (binder.map (·.count) |>.getD 0) + 1 then
      throw { message := "@ selector needs a matching binder count", path := #[.key DefinitionTemplate.infoFields.binders.name] }
  if display.auto_arity && template.isolated_arguments.any (!args.contains ·) then
    throw { message := "isolated_arguments must reference a template argument", path := #[.key DefinitionTemplate.infoFields.isolated_arguments.name] }

def validateDefinitionInfo (value : DefinitionInfo) : Except Diagnostic Unit := do
  let display ← value.display
  let templates := display.templates
  if value.kind == .relation && value.relation_info.symbol.isEmpty then
    throw <| definitionConstraint "relation_info" "relation symbol must not be empty"
  if value.kind == .operator then
    if value.operator_info.symbol.isEmpty then
      throw <| definitionConstraint "operator_info" "operator symbol must not be empty"
    unless #[StyleFixity.prefix, .postfix, .infix].contains value.operator_info.fixity do
      throw <| definitionConstraint "operator_info" "symbolic operators require prefix, postfix or infix fixity"
  if let some template := value.parameter_template then
    if template.isEmpty then
      throw <| definitionConstraint "parameter_template" "parameter template must not be empty"
    let refs := argumentReferences template
    if refs.wildcard || !refs.binders.isEmpty then
      throw <| definitionConstraint "parameter_template" "parameter templates support #self, #type and #N only"
  if value.kind != .concept then return
  let formulae := templates.filter (·.label == "formula")
  if formulae.size > 1 then
    throw <| definitionConstraint "concept_info" "formula label may occur at most once"
  for index in [:templates.size] do
    let template := templates[index]!
    if !isNonemptyBasicAscii template.label then
      throw <| templateConstraint index DefinitionTemplate.infoFields.label.name
        "label must be a nonempty printable ASCII string"
    if template.label == "formula" && template.lang.isSome then
      throw <| templateConstraint index DefinitionTemplate.infoFields.lang.name
        "formula label must not specify lang"
    if template.label != "formula" && template.lang.isNone then
      throw <| templateConstraint index DefinitionTemplate.infoFields.lang.name
        "non-formula labels must specify lang"
    if let some lang := template.lang then
      if lang.code.isEmpty then
        throw <| templateConstraint index DefinitionTemplate.infoFields.lang.name
          "lang must not be empty"
  if value.concept_info.default.isEmpty then
    throw <| definitionConstraint "concept_info" "default must not be empty"
  if templates.isEmpty then return
  if formulae.isEmpty && !templates.any (·.lang.map (·.code) == some "en") then
    throw <| definitionConstraint "concept_info" "at least one formula or en template is required"
  let defaultTemplates := templates.filter (·.label == value.concept_info.default)
  if defaultTemplates.isEmpty then
    throw <| definitionConstraint "concept_info" "default must name an existing template label"
  if value.concept_info.default != "formula" && !templates.any (fun template =>
       template.label == value.concept_info.default && template.lang.map (·.code) == some "en") then
    throw <| definitionConstraint "concept_info" "default label must have an en template"
  let mut keys : Array (String × Option String) := #[]
  for index in [:templates.size] do
    let template := templates[index]!
    let key := (template.label, template.lang.map (·.code))
    if keys.contains key then
      throw <| definitionConstraint "concept_info"
        "duplicate label and lang combination"
    keys := keys.push key
  let references := display.templates.map fun template => argumentReferences template.content
  if !references.isEmpty && references.all (!·.binders.isEmpty) then
    throw <| definitionConstraint "concept_info" "a template without @ selectors is required"
  for index in [:display.templates.size] do
    (validateTemplate display display.templates[index]!).mapError fun error =>
      { error with
        path := #[.key "concept_info", .key "templates", .index index] ++ error.path }

instance : InfoSchema DefinitionInfo :=
  { (inferInstance : InfoSchema DefinitionInfo).withOverrides! {
    validateRecord := validateDefinitionInfo } with version := "8.0.0" }

def definitionSpec : InfoSpec DefinitionInfo := {
  kind := "definition"
  dependencies := fun value =>
    if value.kind == .alias then
      value.alias_info.target.toList.toArray.map fun reference => ("definition", reference.name)
    else #[] }

/-- Validate the static alias closure in the same module view.
    Snapshots resolve explicit argument selection from declaration
    binders; the backend checks application arity and selected lambda shapes. -/
def resolveDefinitionChain (env : Environment) (query : Query) (declaration : Name) :
    Except Diagnostic (Array (Name × ResolvedInfo DefinitionInfo)) := do
  let events ← queryEvents env query
  let mut current := declaration
  let mut chain : Array (Name × ResolvedInfo DefinitionInfo) := #[]
  -- Every distinct alias node requires a configuration event, so this is a finite bound.
  for _ in [:events.size + 1] do
    let fail := fun (error : Diagnostic) => { error with
      kind := some definitionSpec.kind, target := some current.toString }
    if chain.any (·.1 == current) then
      let names := (chain.map (·.1.toString)).push current.toString
      let error : Diagnostic := {
        message := "alias cycle: " ++ String.intercalate " → " names.toList
        path := #[.key DefinitionInfo.infoFields.alias_info.name, .key AliasInfo.infoFields.target.name] }
      throw (fail error)
    unless env.contains current do throw <| fail { message := "unknown declaration in alias closure" }
    let info ← (resolveConfiguredInfo definitionSpec env query current).mapError fail
    chain := chain.push (current, info)
    if info.value.kind == .alias then
      match info.value.alias_info.target with
      | none => return chain
      | some reference =>
        current := reference.name
    else return chain
  throw { message := "alias closure exceeded its event bound", kind := some definitionSpec.kind, target := some declaration.toString }

def resolveDefinitionInfo (env : Environment) (query : Query) (declaration : Name) :
    Except Diagnostic (ResolvedInfo DefinitionInfo) := do
  let chain ← resolveDefinitionChain env query declaration
  let some (_, info) := chain[0]? | throw { message := "empty definition closure" }
  return info

end ProofScript
