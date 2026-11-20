import ProofScript.Info.Decl.Core
import ProofScript.Info.TypedElab
import ProofScript.Core.BuildMode
import ProofScript.Utils.Linter

/-! Declaration and theorem configuration commands. -/

namespace ProofScript

open Lean Elab Command

private def commandValue (ref : Syntax) (result : Except String α) : CommandElabM α := do
  match result with
  | .ok value => return value
  | .error error => throwErrorAt ref error

/-- List edits consume only templates, even if another root field is incomplete or ambiguous. -/
private def currentDefinitionTemplates (target : Name) (ref : Syntax) :
    CommandElabM (Array DefinitionTemplate) := do
  let env ← getEnv
  let view ← commandValue ref <| resolveTypedDecl env env.mainModule target
  commandValue ref view.readTemplates

private def currentNames (target : Name) (ref : Syntax) : CommandElabM (List InternationalName) := do
  let env ← getEnv
  let view ← commandValue ref <| resolveTypedDecl env env.mainModule target
  commandValue ref view.readNames

private def currentTags (target : Name) (ref : Syntax) : CommandElabM (List InternationalName) := do
  let env ← getEnv
  let view ← commandValue ref <| resolveTypedDecl env env.mainModule target
  commandValue ref view.readTags

private def parseInternationalNames (stx : TSyntax `term) : CommandElabM (List InternationalName) := do
  liftCoreM <| InfoCodec.annotate (α := List InternationalName) stx
  liftCoreM <| InfoCodec.decode (α := List InternationalName) stx

private def checkInternationalEntries (field : DeclField) (entries : List InternationalName)
    (ref : Syntax) : CommandElabM Unit := do
  let edit : DeclEdit := match field with
    | .names => ⟨.names, entries⟩
    | _ => ⟨.tags, entries⟩
  match TypedInfoChange.validate (.decl `_internationalInput #[edit]) with
  | .ok _ => pure ()
  | .error error => throwErrorAt ref error

private def parseNameLanguages (stx : TSyntax `term) : CommandElabM (List (Option String)) := do
  let `(term| [$[$items:term],*]) := stx
    | throwErrorAt stx "expected a list of languages"
  items.toList.mapM fun item => do
    let lang ← liftCoreM <| InfoCodec.decode (α := OptionalInput Language) item
    let key := lang.value.map (·.code)
    if key.any (·.isEmpty) then throwErrorAt item "lang must not be empty"
    return key

private def requireOrdinaryLabel (ref : Syntax) (label : String) : CommandElabM Unit := do
  if label.startsWith "$" then
    throwErrorAt ref "decl_info templates cannot operate on reserved labels"
  unless isNonemptyBasicAscii label do
    throwErrorAt ref "label must be a nonempty printable ASCII string"

private def parseTemplateAdditions (stx : TSyntax `term) : CommandElabM (Array DefinitionTemplate) := do
  liftCoreM <| InfoCodec.annotate (α := Array DefinitionTemplate) stx
  let templates ← liftCoreM <| InfoCodec.decode (α := Array DefinitionTemplate) stx
  for template in templates do requireOrdinaryLabel stx template.label
  return templates

private def parseTemplateRemovals (stx : TSyntax `term) :
    CommandElabM (Array (String × Option String)) := do
  let `(term| [$[$pairs:term],*]) := stx
  | throwErrorAt stx "expected a list of (label, lang) pairs"
  let mut keys := #[]
  for pair in pairs do
    let `(term| ($label:term, $lang:term)) := pair
    | throwErrorAt pair "expected a (label, lang) pair"
    let labelValue ← liftCoreM <| InfoCodec.decode (α := String) label
    requireOrdinaryLabel label labelValue
    let language := (← liftCoreM <| InfoCodec.decode (α := OptionalInput Language) lang).value
    if language.any (·.code.isEmpty) then
      throwErrorAt lang "lang must not be empty"
    let key := (labelValue, language.map (·.code))
    if keys.contains key then
      throwErrorAt pair "duplicate label and lang combination"
    keys := keys.push key
  return keys

elab "decl_info" target:ident fields:infoFields : command => do
  for input in ← InputField.readFields (Field := DeclField) fields do
    if fieldKeyName input.ref == "name" then
      throwErrorAt input.ref "`name` has been replaced by `names`; provide a list of language/value objects"
  InputField.annotateFields (Field := DeclField) ``DeclInfo fields
  let declaration ← liftCoreM <| resolveDeclaration target
  let edits ← InputField.parseEdits <| ← InputField.readFields fields
  if ← pageBuild? then
    TypedInfoChange.commit (.decl declaration edits) fields
  else
    TypedInfoChange.check (.decl declaration edits) fields

elab "decl_info" &"names" target:ident "+" entries:term : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  let additions ← parseInternationalNames entries
  checkInternationalEntries .names additions entries
  if ← pageBuild? then
    let previous ← currentNames declaration entries
    TypedInfoChange.commit (.decl declaration #[⟨.names, previous ++ additions⟩]) entries
  else
    TypedInfoChange.check (.decl declaration #[⟨.names, additions⟩]) entries

elab "decl_info" &"names" target:ident "-" entries:term : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  let removals ← parseNameLanguages entries
  if removals.eraseDups.length != removals.length then
    throwErrorAt entries "duplicate name language"
  if ← pageBuild? then
    let previous ← currentNames declaration entries
    for key in removals do
      unless previous.any (·.key == key) do
        throwErrorAt entries "name with this lang does not exist"
    TypedInfoChange.commit (.decl declaration #[⟨.names,
      previous.filter fun entry => !removals.contains entry.key⟩]) entries

elab "decl_info" &"tags" target:ident "+" entries:term : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  let additions ← parseInternationalNames entries
  checkInternationalEntries .tags additions entries
  if ← pageBuild? then
    let previous ← currentTags declaration entries
    TypedInfoChange.commit (.decl declaration #[⟨.tags, previous ++ additions⟩]) entries
  else
    TypedInfoChange.check (.decl declaration #[⟨.tags, additions⟩]) entries

elab "decl_info" &"tags" target:ident "-" entries:term : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  let removals ← parseInternationalNames entries
  checkInternationalEntries .tags removals entries
  if ← pageBuild? then
    let previous ← currentTags declaration entries
    let mut remaining := previous
    for entry in removals do
      let some index := remaining.findIdx? (fun item => item.key == entry.key && item.value == entry.value)
        | throwErrorAt entries "tag with this lang and value does not exist"
      remaining := (remaining.take index) ++ (remaining.drop (index + 1))
    TypedInfoChange.commit (.decl declaration #[⟨.tags, remaining⟩]) entries

elab "decl_info" &"wrapper" target:ident index:num : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  if ← pageBuild? then
    TypedInfoChange.commit (.decl declaration #[⟨.kind, .wrapper⟩,
      ⟨.wrapperIndex, ⟨some index.getNat⟩⟩]) index

elab "decl_info" &"alias" target:ident ("→" <|> "->") aliasTarget:ident : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  let destination ← liftCoreM <| resolveDeclaration aliasTarget
  if ← pageBuild? then
    TypedInfoChange.commit (.decl declaration #[⟨.kind, .alias⟩,
       ⟨.aliasTarget, ⟨some ⟨destination⟩⟩⟩]) aliasTarget

-- Non-reserved keywords keep `templates` available as an ordinary field name.
elab "decl_info" &"templates" target:ident "+" entries:term : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  let additions ← parseTemplateAdditions entries
  if ← pageBuild? then
    let previous ← currentDefinitionTemplates declaration target
    for template in additions do
      if previous.any (·.key == template.key) then
        throwErrorAt entries m!"template `{template.label}` with this lang already exists"
    TypedInfoChange.commit (.decl declaration #[⟨.templates, previous ++ additions⟩]) entries
  else
    TypedInfoChange.check (.decl declaration #[⟨.templates, additions⟩]) entries

elab "decl_info" &"templates" target:ident "-" entries:term : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  let removals ← parseTemplateRemovals entries
  if ← pageBuild? then
    let previous ← currentDefinitionTemplates declaration target
    for key in removals do
      unless previous.any (·.key == key) do
        throwErrorAt entries m!"template `{key.1}` with this lang does not exist"
    let templates := previous.filter fun template => !removals.contains template.key
    TypedInfoChange.commit (.decl declaration #[⟨.templates, templates⟩]) entries

private syntax options := "(" sepBy(infoField, ", ") ")"

/-- A supplied option is decoded as α; omission is represented by the field default. -/
private structure SymbolOption (α : Type) where
  value : Option α := none

private instance [InfoCodec α] : InfoCodec (SymbolOption α) where
  decode stx := return ⟨some (← InfoCodec.decode stx)⟩
  annotate := InfoCodec.annotate (α := α)

private structure SymbolOptions where
  mode : SymbolOption DisplayMode := {}
  precedence : SymbolOption (OptionalInput Nat) := {}
deriving InfoCodec

private def applySymbolOptions (template : DefinitionTemplate)
    (options : Option (TSyntax ``options)) (relation : Bool) :
    CommandElabM DefinitionTemplate := do
  let some options := options | return template
  let `(options| ($[$entries:infoField],*)) := options
    | throwErrorAt options "expected symbol options"
  let fields := entries.map (·.raw)
  let input ← `(term| { $[$entries:infoField],* })
  liftCoreM <| InfoCodec.annotate (α := SymbolOptions) input
  for field in fields do
    let name := objectFieldName field
    unless name == "mode" || (!relation && name == "precedence") do
      throwErrorAt (objectFieldRef field) m!"unknown symbol option `{name}`"
  let decoded ← liftCoreM <| InfoCodec.decode (α := SymbolOptions) input
  return { template with
    content := { template.content with
      mode := decoded.mode.value.getD template.mode
      precedence := (decoded.precedence.value.map (·.value)).getD template.content.precedence } }

private def checkSymbolArity (target : TSyntax `ident) (declaration : Name) (expected : Nat) :
    CommandElabM Unit := do
  let facts ← commandValue target <| definitionArgumentFacts (← getEnv) declaration
  let actual := facts.explicit_indices.size
  unless actual == expected do
    throwErrorAt target m!"symbol shorthand requires exactly {expected} explicit parameters; `{declaration}` has {actual}"

private inductive SymbolLayout where
  | prefix | postfix | infix | infixl | infixr | relation

private def elaborateDefinitionSymbol (layout : SymbolLayout) (target : TSyntax `ident)
    (symbol : TSyntax `str) (options : Option (TSyntax ``options)) :
    CommandElabM Unit := do
  let declaration ← liftCoreM <| resolveDeclaration target
  let text := symbol.getString
  if text.isEmpty && (match layout with
      | .infix | .infixl | .infixr => false
      | _ => true) then
    throwErrorAt symbol "symbol must not be empty"
  let (label, parts, arity) ←
    match layout with
    | .prefix => pure ("$prefix", #[TemplateAtom.literal (text ++ " "), .argument 0], 1)
    | .postfix => pure ("$postfix", #[TemplateAtom.argument 0, .literal (" " ++ text)], 1)
    | .infix => pure ("$infix", #[TemplateAtom.argument 0, .literal (" " ++ text ++ " "), .argument 1], 2)
    | .infixl => pure ("$infixl", #[TemplateAtom.argument 0, .literal (" " ++ text ++ " "), .argument 1], 2)
    | .infixr => pure ("$infixr", #[TemplateAtom.argument 0, .literal (" " ++ text ++ " "), .argument 1], 2)
    | .relation => pure ("$relation", #[TemplateAtom.argument 0, .literal (" " ++ text ++ " "), .argument 1], 2)
  let relation := match layout with | .relation => true | _ => false
  let kind := if relation then DeclKind.relation else DeclKind.operator
  let content : TemplateContent := {
    mode := .formula
    parts := parts.map TemplatePart.atom
    precedence := if relation then some 50 else none }
  let template : DefinitionTemplate := { label, content }
  let template ← applySymbolOptions template options relation
  checkSymbolArity target declaration arity
  let ref := options.map (·.raw) |>.getD symbol.raw
  if ← pageBuild? then
    let previous ← currentDefinitionTemplates declaration target
    let templates := #[template] ++ previous.filter (·.key != template.key)
    let mut edits : Array DeclEdit := #[⟨.kind, kind⟩, ⟨.templates, templates⟩]
    if relation then
        edits := edits.push ⟨.calcSymbol, ⟨some text⟩⟩
    TypedInfoChange.commit (.decl declaration edits) ref
  else
    TypedInfoChange.check (.decl declaration #[⟨.kind, kind⟩, ⟨.templates, #[template]⟩]) ref

elab "decl_info" &"prefix" target:ident symbol:str options:(options)? : command =>
  elaborateDefinitionSymbol .prefix target symbol options

elab "decl_info" &"postfix" target:ident symbol:str options:(options)? : command =>
  elaborateDefinitionSymbol .postfix target symbol options

elab "decl_info" &"infix" target:ident symbol:str options:(options)? : command =>
  elaborateDefinitionSymbol .infix target symbol options

elab "decl_info" &"infixl" target:ident symbol:str options:(options)? : command =>
  elaborateDefinitionSymbol .infixl target symbol options

elab "decl_info" &"infixr" target:ident symbol:str options:(options)? : command =>
  elaborateDefinitionSymbol .infixr target symbol options

elab "decl_info" &"relation" target:ident symbol:str options:(options)? : command =>
  elaborateDefinitionSymbol .relation target symbol options

elab "reset" "decl_info" target:ident : command => do
  let declaration ← liftCoreM <| resolveDeclaration target
  whenPageBuild <|
    (TypedInfoChange.resetDecl declaration).commit target

macro "theorem_info" id:ident fields:infoFields : command => do
  let `(infoFields| { $[$entries:infoField],* }) := fields
  | Macro.throwUnsupported
  let kind ← `(infoField| kind := «theorem»)
  let fields := #[kind] ++ entries
  let fields ← `(infoFields| { $[$fields:infoField],* })
  `(command| decl_info $id $fields:infoFields)

elab "#preview" "decl_info" target:ident : command => allowHashCommandLint do
  let declaration ← liftCoreM <| resolveDeclaration target
  let env ← getEnv
  let (value, _) ← commandValue target <| freezeDeclInfo env env.mainModule declaration
  logInfo m!"decl {declaration}: {value.pretty}"

end ProofScript
