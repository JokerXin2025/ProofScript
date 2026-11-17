import ProofScript.Core.ModuleGraph
import ProofScript.Core.ModuleExtensionEntries
import ProofScript.Core.BuildMode
import ProofScript.Info.Decl.Model
import ProofScript.Info.Script.Model
import ProofScript.Info.ObjectCodec
import ProofScript.Info.Template
import ProofScript.Utils.Ascii

namespace ProofScript

open Lean Elab Command

inductive DeclField where
| names
| tags
| varName
| kind
| wrapperIndex
| aliasTarget
| templates
| defaultTemplate
| calcSymbol
| parameterTemplate
| extra (key : String)
deriving BEq

abbrev DeclField.Value : DeclField → Type
| .names              => List InternationalName
| .varName            => String
| .tags               => List InternationalName
| .kind               => DeclKind
| .wrapperIndex       => OptionalInput Nat
| .aliasTarget        => OptionalInput DeclarationRef
| .templates          => Array DefinitionTemplate
| .defaultTemplate    => OptionalInput String
| .calcSymbol         => OptionalInput String
| .parameterTemplate  => OptionalInput String
| .extra _            => Json

abbrev DeclEdit := (field : DeclField) × field.Value

inductive ScriptField where
| renderer
| templates
| display
| color
| board
| extra (key : String)
deriving BEq

abbrev ScriptField.Value : ScriptField → Type
| .renderer   => ScriptRenderer
| .templates  => Array ScriptTemplate
| .display    => Bool
| .color      => ScriptColor
| .board      => ScriptBoardInput
| .extra _    => Json

abbrev ScriptEdit := (field : ScriptField) × field.Value

/-- A field domain supplies typed codecs, source syntax and extension handling. -/
class InputField (Field : Type) where
  Value : Field → Type
  codec : (field : Field) → InfoCodec (Value field)
  /-- Explicit extension keys remain separate from builtin fields with the same name. -/
  extra : String → Field
  extensionKey : Field → Option String
  fieldOf : String → Field

structure InputFieldSyntax (Field : Type) [InputField Field] where
  key : Field
  ref : Syntax
  value : TSyntax `term

instance : InputField DeclField where
  Value := DeclField.Value
  codec := fun field => by cases field <;> infer_instance
  extra := .extra
  extensionKey
  | .extra key => some key
  | _ => none
  fieldOf
  | "names" => .names
  | "tags" => .tags
  | "var_name" => .varName
  | "kind" => .kind
  | "wrapper_index" => .wrapperIndex
  | "alias_target" => .aliasTarget
  | "templates" => .templates
  | "default_template" => .defaultTemplate
  | "calc_symbol" => .calcSymbol
  | "parameter_template" => .parameterTemplate
  | key => .extra key

instance : InputField ScriptField where
  Value := ScriptField.Value
  codec := fun field => by cases field <;> infer_instance
  extra := .extra
  extensionKey
  | .extra key => some key
  | _ => none
  fieldOf
  | "renderer" => .renderer
  | "templates" => .templates
  | "display" => .display
  | "color" => .color
  | "board" => .board
  | key => .extra key

private def builtinDefinitionLabels := #[
  "$relation", "$prefix", "$infix", "$infixl", "$infixr", "$postfix"
]

/-- The variant binds the target kind to its edit type; resets clear the whole target. -/
inductive TypedInfoChange where
| decl (target : Name) (edits : Array DeclEdit)
| script (target : Name) (edits : Array ScriptEdit)
| resetDecl (target : Name)
| resetScript (target : Name)

/-- Store configuration transactions in source order within each module. -/
initialize typedInfoChangeExt : SimplePersistentEnvExtension TypedInfoChange Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.typedInfoChanges
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

namespace TypedInfoChange

/-- Validate assigned fields without demanding a complete record. -/
def validate : TypedInfoChange → Except String Unit
| .decl _ edits => edits.forM fun edit => match edit with
  | ⟨.names, value⟩ => do
    let mut languages : Array (Option String) := #[]
    for index in [:value.length] do
      let entry := value[index]!
      let atEntry := fun error => infoFieldError "names" (infoIndexError index error)
      if entry.value.trimAscii.toString.isEmpty then
        throw <| atEntry (infoFieldError "value" "must not be empty")
      if entry.key.any (·.isEmpty) then
        throw <| atEntry (infoFieldError "lang" "lang must not be empty")
      if languages.contains entry.key then
        throw <| atEntry (infoFieldError "lang" "duplicate name language")
      languages := languages.push entry.key
  | ⟨.tags, value⟩ => do
    for index in [:value.length] do
      let entry := value[index]!
      let atEntry := fun error => infoFieldError "tags" (infoIndexError index error)
      if entry.value.trimAscii.toString.isEmpty then
        throw <| atEntry (infoFieldError "value" "must not be empty")
      if entry.key.any (·.isEmpty) then
        throw <| atEntry (infoFieldError "lang" "lang must not be empty")
  | ⟨.templates, value⟩ => do
    let mut keys : Array (String × Option String) := #[]
    for index in [:value.size] do
      let template := value[index]!
      let atTemplate := fun error => infoFieldError "templates" (infoIndexError index error)
      unless isNonemptyBasicAscii template.label do
        throw <| atTemplate (infoFieldError "label" "label must be a nonempty printable ASCII string")
      if template.label.startsWith "$" && !builtinDefinitionLabels.contains template.label then
        throw <| atTemplate (infoFieldError "label" "unknown reserved template label")
      if template.lang.value.any (·.code.isEmpty) then
        throw <| atTemplate (infoFieldError "lang" "lang must not be empty")
      if template.label.startsWith "$" && template.lang.value.isSome then
        throw <| atTemplate (infoFieldError "lang" "reserved templates must not specify lang")
      if template.content.display.isEmpty then
        throw <| atTemplate (infoFieldError "content" "must not be empty")
      if template.content.precedence.any (· > 100) then
        throw <| atTemplate (infoFieldError "precedence" "precedence exceeds 100")
      for part in template.content.atoms do
        match part with
        | .literal _ => pure ()
        | .argument .. => pure ()
        | .binder _ layer _ =>
          if layer == 0 then
            throw <| atTemplate (infoFieldError "content" "binder layers start at 1")
        | .body .. => pure ()
      let key := template.key
      if keys.contains key then
        throw <| infoFieldError "templates"
          (infoIndexError index "duplicate label and lang combination")
      keys := keys.push key
  | ⟨.calcSymbol, ⟨some ""⟩⟩ => throw (infoFieldError "calc_symbol" "must not be empty")
  | ⟨.parameterTemplate, ⟨some template⟩⟩ => do
    if template.isEmpty then
      throw <| infoFieldError "parameter_template" "parameter template must not be empty"
    let refs := parameterTemplateReferences template
    if refs.unsupported then
      throw <| infoFieldError "parameter_template"
        "parameter templates support #self, #type and #N only"
  | _ => pure ()
| .script _ edits => edits.forM fun edit => match edit with
  | ⟨.templates, value⟩ => do
    for index in [:value.size] do
      let template := value[index]!
      let atTemplate := fun error => infoFieldError "templates" (infoIndexError index error)
      if template.lang.isEmpty then
        throw <| atTemplate (infoFieldError "lang" "template language must not be empty")
      if let .strategy strategy := template then
        for caseIndex in [:strategy.cases.size] do
          if strategy.cases[caseIndex]!.name.isEmpty then
            throw <| atTemplate (infoFieldError "cases"
              (infoIndexError caseIndex (infoFieldError "name" "case name must not be empty")))
        if strategy.cases.isEmpty then
          throw <| atTemplate (infoFieldError "cases" "cases must not be empty")
        if (strategy.cases.toList.map (·.name)).eraseDups.length != strategy.cases.size then
          throw <| atTemplate (infoFieldError "cases" "duplicate case name")
        if strategy.inline then
          if strategy.cases.size != 1 then
            throw <| atTemplate (infoFieldError "inline" "inline requires exactly one case")
          if strategy.cases[0]!.tag != "" || strategy.cases[0]!.title != "" then
            throw <| atTemplate (infoFieldError "cases" "inline case must have empty tag and title")
    let mut languages := #[]
    for template in value do
      let lang := template.lang
      if languages.contains lang then
        throw <| infoFieldError "templates" s!"duplicate template language `{lang}`"
      languages := languages.push lang
  | _ => pure ()
| .resetDecl _ | .resetScript _ => pure ()

/-- Check non-persisted command input at the same boundary as committed input. -/
def check (change : TypedInfoChange) (ref : Syntax) : CommandElabM Unit := do
  let env ← getEnv
  let checkNative ← pageBuild?
  let validation : Except String Unit := do
    change.validate
    if checkNative then
      if let .decl target edits := change then
        if edits.any (fun edit => match edit with | ⟨.kind, .theorem⟩ => true | _ => false) then
          unless (env.find? target).any (fun info => match info with
              | .thmInfo _ => true
              | _ => false) do
            throw "kind theorem requires a native theorem declaration"
  match validation with
  | .ok _ => pure ()
  | .error error => throwErrorAt ref error

/-- Validate and persist a typed configuration transaction. -/
def commit (change : TypedInfoChange) (ref : Syntax) : CommandElabM Unit := do
  change.check ref
  setEnv <| typedInfoChangeExt.addEntry (← getEnv) change

end TypedInfoChange

namespace InputField
variable {Field : Type} [InputField Field]

def readFields (stx : TSyntax ``infoFields) : CommandElabM (Array (InputFieldSyntax Field)) := do
  let `(infoFields| { $[$fields:infoField],* }) := stx
    | throwErrorAt stx "expected a field object"
  fields.mapM fun field => do
    match field with
    | `(infoField| $key:ident := $value:term) =>
      return ⟨fieldOf (fieldKeyName key.raw), key.raw, value⟩
    | _ => throwErrorAt field "expected field := value"

def annotateFields (record : Name) (fields : TSyntax ``infoFields) : CommandElabM Unit := do
  unless (← getInfoState).enabled do return
  for input in ← readFields (Field := Field) fields do
    let name := fieldKeyName input.ref
    liftCoreM <| annotateField record name input.ref input.value fun value =>
      if name == "extra" then InfoCodec.annotate (α := ExtraFields) value
      else (codec input.key).annotate value

/-- Expand extension containers and parse each typed field in source order. -/
def parseEdits [BEq Field] (fields : Array (InputFieldSyntax Field))
    : CommandElabM (Array ((field : Field) × Value field)) := do
  let mut assigned : Array Field := #[]
  let mut extraContainer := false
  let mut result := #[]
  for input in fields do
    let ref := input.ref
    let name := fieldKeyName ref
    if extensionKey input.key == some "extra" then
      if extraContainer then throwErrorAt ref "duplicate field `extra`"
      extraContainer := true
      for entry in (← liftCoreM <| readObject input.value) do
        let name := objectFieldName entry
        let entryRef := objectFieldRef entry
        let value ← liftCoreM <| objectFieldValue entry
        let key := extra name
        if assigned.contains key then throwErrorAt entryRef m!"duplicate extension key `{name}`"
        assigned := assigned.push key
        result := result.push ⟨key, ← liftCoreM <| (InputField.codec key).decode value⟩
    else
      let field := input.key
      let extension := extensionKey field
      if assigned.contains field then
        throwErrorAt ref m!"duplicate {if extension.isSome then "extension key" else "field"} `{name}`"
      assigned := assigned.push field
      result := result.push ⟨field, ← liftCoreM <| (InputField.codec field).decode input.value⟩
  return result

end InputField

end ProofScript
