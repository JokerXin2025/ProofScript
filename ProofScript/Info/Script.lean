import ProofScript.Info.Derive
import ProofScript.Info.Target
import ProofScript.Script.Registry
import ProofScript.Core.Language
import ProofScript.Core.Color

open Lean Elab Command


namespace ProofScript

instance : InfoCodec Language where
  parse stx := do
    if stx.raw.isOfKind ``Lean.Parser.Term.app then
      let args := stx.raw[1].getArgs
      if stx.raw[0].isIdent && stx.raw[0].getId.eraseMacroScopes.toString == "Language.custom" &&
          args.size == 3 then
        return .custom (← InfoCodec.parse (⟨args[0]!⟩ : TSyntax `term))
          (← InfoCodec.parse (⟨args[1]!⟩ : TSyntax `term))
          (← InfoCodec.parse (⟨args[2]!⟩ : TSyntax `term))
      throwErrorAt stx "expected Language.custom with three string literals"
    match stx with
    | `(term| $name:ident) =>
      let identifier := name.getId.eraseMacroScopes
      let constructor := ``Language ++ Name.mkSimple identifier.getString!
      unless identifier == .str .anonymous identifier.getString! &&
          (← getEnv).contains constructor do
        throwErrorAt stx m!"unknown language constructor `{identifier}`"
      -- Configuration persists only the language code, not the constructor's names.
      let code := identifier.getString!.replace "_" "-"
      return .custom code code code
    | _ => throwErrorAt stx "expected a Language constructor"
  decode value := do
    let code ← decodeJson value
    if code.isEmpty then throw { message := "template language must not be empty" }
    return .custom code code code
  jsonSchema := InfoJson.nonemptyStringSchema

def visibleScriptRegistrations (env : Environment) (moduleName : Name) :
    Except Diagnostic (List ScriptTacticRegistration) := do
  let order ← (ModuleGraph.ofEnvironment env).modulesInDependencyOrder moduleName
    |>.mapError fun message => { message }
  return scriptRegistrationsInModules env order

def scriptRegistrationInView (env : Environment) (query : Query) (ruleId : Name) :
    Except Diagnostic ScriptTacticRegistration := do
  let some registration := (← visibleScriptRegistrations env query.moduleName).find? (·.ruleId == ruleId)
    | throw { message := "unknown script registration", kind := some "script", target := some ruleId.toString }
  return registration

def resolveScriptTarget (target : TSyntax `ident) : CommandElabM Name := do
  let env ← getEnv
  let ruleId := removeRoot target.getId.eraseMacroScopes
  match scriptRegistrationInView env { moduleName := env.mainModule } ruleId with
  | .ok registration =>
    addConstInfo target.raw registration.sourceKind
    return ruleId
  | .error _ => throwErrorAt target m!"unknown script_info registration ID `{ruleId}`"

private def colorByte (value : String) : Except String UInt8 := do
  let some high := value.toList[0]? | throw "expected a hexadecimal CSS color"
  let some low := value.toList[1]? | throw "expected a hexadecimal CSS color"
  let digit (c : Char) : Except String Nat :=
    if c >= '0' && c <= '9' then pure (c.toNat - '0'.toNat)
    else if c >= 'a' && c <= 'f' then pure (c.toNat - 'a'.toNat + 10)
    else if c >= 'A' && c <= 'F' then pure (c.toNat - 'A'.toNat + 10)
    else throw "expected a hexadecimal CSS color"
  return UInt8.ofNat ((← digit high) * 16 + (← digit low))

private def colorFromString (value : String) : Except String RGBA := do
  let chars := value.toList
  unless chars.head? == some '#' && (chars.length == 7 || chars.length == 9) do
    throw "expected a hexadecimal CSS color (#RRGGBB or #RRGGBBAA)"
  let digits := chars.drop 1
  let red ← colorByte (String.ofList (digits.take 2))
  let green ← colorByte (String.ofList (digits.drop 2 |>.take 2))
  let blue ← colorByte (String.ofList (digits.drop 4 |>.take 2))
  let alpha ← if chars.length == 9 then
    some <$> colorByte (String.ofList (digits.drop 6 |>.take 2)) else pure none
  return ⟨red, green, blue, alpha⟩

instance : InfoCodec RGBA where
  parse stx := do
    match stx with
    | `(term| ($red:term, $green:term, $blue:term)) =>
      return ((← InfoCodec.parse red : Nat), (← InfoCodec.parse green : Nat),
        (← InfoCodec.parse blue : Nat))
    | `(term| ($red:term, $green:term, $blue:term, $alpha:term)) =>
      return ((← InfoCodec.parse red : Nat), (← InfoCodec.parse green : Nat),
        (← InfoCodec.parse blue : Nat), (← InfoCodec.parse alpha : Nat))
    | `(term| $text:str) =>
      match colorFromString text.getString with
      | .ok color => return color
      | .error message => throwErrorAt stx message
    | _ => throwErrorAt stx "expected (red, green, blue) or (red, green, blue, alpha)"
  decode value := do
    let text ← decodeJson value
    (colorFromString text).mapError fun message => { message }
  jsonSchema := json% { type: "string", pattern: "^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$" }

structure ScriptColor where
  tag : Option RGBA := none
  border : Option RGBA := none
  background : Option RGBA := none
  deriving Inhabited, InfoSchema

instance (priority := high) : InfoCodec ScriptColor :=
  let ordinary := schemaCodec inferInstance
  { ordinary with parse := fun stx => do
      if let `(term| ($tag:term, $border:term, $background:term)) := stx then
        return ScriptColor.mk (← InfoCodec.parse tag) (← InfoCodec.parse border) (← InfoCodec.parse background)
      ordinary.parse stx }

/-- The renderers currently provided by the backend. Their implementation stays in Python. -/
inductive ScriptRenderer where
  | automatic | strategy | calc | infer | media | diagram | remark | admit | embed | unrecorded
  deriving Inhabited, Repr, BEq

instance : InfoCodec ScriptRenderer := enumCodec #[
  ("none", .automatic), ("strategy", .strategy), ("calc", .calc), ("infer", .infer),
  ("media", .media), ("diagram", .diagram), ("remark", .remark), ("admit", .admit), ("embed", .embed),
  ("unrecorded", .unrecorded)]

structure ScriptIntroducer where
  tag : String
  content : String
  deriving Inhabited, InfoSchema

instance (priority := high) : InfoCodec (Option ScriptIntroducer) := optionalInputCodec

structure ScriptCase where
  name : String
  tag : String
  title : String
  introducer : Option ScriptIntroducer := none
  deriving Inhabited, InfoSchema

instance : InfoSchema ScriptCase :=
  (inferInstance : InfoSchema ScriptCase).withOverrides! {
    fields := #[ScriptCase.infoFields.name.withValidation fun name =>
      if name.isEmpty then .error "case name must not be empty" else .ok ()] }

structure OrdinaryScriptTemplate where
  lang : Language
  tag : String
  content : String
  deriving Inhabited, InfoSchema

private def nonemptyLanguage (language : Language) : Except String Unit :=
  if language.code.isEmpty then .error "template language must not be empty" else .ok ()

instance : InfoSchema OrdinaryScriptTemplate :=
  (inferInstance : InfoSchema OrdinaryScriptTemplate).withOverrides! {
    fields := #[OrdinaryScriptTemplate.infoFields.lang.withValidation nonemptyLanguage] }

structure StrategyScriptTemplate where
  lang : Language
  tag : String
  inline : Bool := false
  introducer : Option ScriptIntroducer := none
  cases : Array ScriptCase
  deriving Inhabited, InfoSchema

instance : InfoSchema StrategyScriptTemplate :=
  (inferInstance : InfoSchema StrategyScriptTemplate).withOverrides! {
    fields := #[StrategyScriptTemplate.infoFields.lang.withValidation nonemptyLanguage,
      StrategyScriptTemplate.infoFields.cases.withValidation fun cases => do
        if cases.isEmpty then throw "cases must not be empty"
        if (cases.toList.map (·.name)).eraseDups.length != cases.size then throw "duplicate case name"]
    validateRecord := fun value => do
      if value.inline then
        if value.cases.size != 1 then
          let error : Diagnostic := {
            message := "inline requires exactly one case"
            path := #[.key StrategyScriptTemplate.infoFields.inline.name] }
          throw error
        if value.cases[0]!.tag != "" || value.cases[0]!.title != "" then
          throw { message := "inline case must have empty tag and title", path := #[.key StrategyScriptTemplate.infoFields.cases.name] } }

inductive ScriptTemplate where
  | ordinary (value : OrdinaryScriptTemplate)
  | strategy (value : StrategyScriptTemplate)
  deriving Inhabited

def ScriptTemplate.lang : ScriptTemplate → String
  | .ordinary value => value.lang.code
  | .strategy value => value.lang.code

def ScriptTemplate.isStrategy : ScriptTemplate → Bool
  | .ordinary _ => false
  | .strategy _ => true

instance : InfoCodec ScriptTemplate where
  parse stx := do
    let fields ← readObject stx
    if fields.any (·.key == StrategyScriptTemplate.infoFields.cases.name) then
      return .strategy (← InfoCodec.parse stx)
    return .ordinary (← InfoCodec.parse stx)
  toJson
  | .ordinary value => json% { kind: "ordinary", value: $value }
  | .strategy value => json% { kind: "strategy", value: $value }
  decode json := do
    let object ← json.getObj?.mapError fun message => { message }
    unless object.toList.all (fun (key, _) => #["kind", "value"].contains key) do
      throw { message := "unknown template envelope field" }
    let kind ← decodeField (Value := String) json "kind"
    match kind with
    | "ordinary" => .ordinary <$> decodeField json "value"
    | "strategy" => .strategy <$> decodeField json "value"
    | _ => throw { message := "unknown script template kind", path := #[.key "kind"] }
  jsonSchema :=
    let alternatives := #[
      ("ordinary", InfoCodec.jsonSchema OrdinaryScriptTemplate),
      ("strategy", InfoCodec.jsonSchema StrategyScriptTemplate)].map fun (kind, schema) => json% {
        type: "object",
        properties: {
          kind: { const: $kind },
          value: $schema
        },
        required: ["kind", "value"],
        additionalProperties: false
      }
    json% { oneOf: $alternatives }
  annotate stx := do
    if let some fields ← readInfoObject? stx then
      if fields.any (·.key == StrategyScriptTemplate.infoFields.cases.name) then
        annotateInfoFields (inferInstance : InfoSchema StrategyScriptTemplate) fields
      else
        annotateInfoFields (inferInstance : InfoSchema OrdinaryScriptTemplate) fields

structure ScriptInfo where
  renderer : ScriptRenderer := .automatic
  template : Array ScriptTemplate := #[]
  display : Bool := true
  color : ScriptColor := {}
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

instance : InfoSchema ScriptInfo :=
  { (inferInstance : InfoSchema ScriptInfo).withOverrides! {
    fields := #[ScriptInfo.infoFields.template.withMerge (keyedArray ScriptTemplate.lang)]
    validateRecord := fun value => do
      if value.renderer == .automatic && value.template.isEmpty then
        let error : Diagnostic := {
          message := "automatic script rendering requires a template"
          path := #[.key ScriptInfo.infoFields.template.name] }
        throw error } with version := "2.0.0" }

def scriptSpec : InfoSpec ScriptInfo := { kind := "script" }

def validateScriptContract (registration : ScriptTacticRegistration) (value : ScriptInfo) :
    Except Diagnostic Unit := do
  if value.renderer == .strategy && !registration.config.isStrategy then
    throw { message := "strategy renderer requires a strategy registration", path := #[.key ScriptInfo.infoFields.renderer.name] }
  for index in [:value.template.size] do
    let template := value.template[index]!
    if template.isStrategy != registration.config.isStrategy then
      throw { message := "template kind does not match the script registration", path := #[.key ScriptInfo.infoFields.template.name, .index index] }

/-- Callers with an actual invocation's selected registration can validate that exact contract.
The default registry query below reconstructs module-end registration metadata; Info boundaries clip Info events only.
-/
def resolveScriptInfoWithRegistration (env : Environment) (query : Query)
    (registration : ScriptTacticRegistration) : Except Diagnostic (ResolvedInfo ScriptInfo) :=
  (do
    let view ← resolvePartial scriptSpec env query registration.ruleId
    let result ← if view.created then consumeView scriptSpec view else do
      let fallback : ScriptInfo := if registration.ruleId == unrecordedRuleId then { renderer := .unrecorded }
        else if registration.config.isStrategy then { renderer := .strategy } else
        { template := #[.ordinary { lang := .zh, tag := registration.name, content := "" }] }
      pure { value := fallback, dependencies := scriptSpec.dependencies fallback }
    (validateScriptContract registration result.value).mapError view.attach
    return result : Except Diagnostic (ResolvedInfo ScriptInfo)).mapError fun error =>
      { error with kind := some scriptSpec.kind, target := some registration.ruleId.toString }

def resolveScriptInfo (env : Environment) (query : Query) (ruleId : Name) :
    Except Diagnostic (ResolvedInfo ScriptInfo) := do
  resolveScriptInfoWithRegistration env query (← scriptRegistrationInView env query ruleId)

end ProofScript
