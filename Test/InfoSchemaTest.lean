import ProofScript.Info

open Lean Elab Command ProofScript.Info

namespace InfoSchemaTest

/-- Configuration consumers and standard JSON decoding must apply the same final rules. -/
private def checkRejected [InfoSchema Record] [FromJson Record]
    (spec : InfoSpec Record) (value : Json) (path : JsonPath) : CommandElabM Unit := do
  let schema : InfoSchema Record := inferInstance
  let object ← match value.getObj? with
    | .ok object => pure object
    | .error message => throwError message
  let source : ProofScript.Foundation.SourceLocation := ⟨"schema-test", 0, 0⟩
  let target : Name ⊕ String := .inl `schemaTest
  let patch : Patch := object.toList.toArray.map fun (name, value) =>
    { key := .builtin name, operation := .set value, source }
  let env ← getEnv
  let configured := do
    let env ← commitInfo spec env target patch source
    resolveInfo spec env { moduleName := env.mainModule } target
  match schema.decode value, configured, fromJson? (α := Record) value with
  | .error canonical, .error configured, .error message =>
    unless canonical.path == path && configured.path == path &&
        canonical.message == configured.message && message == canonical.render do
      throwError "canonical schema, configuration and FromJson diagnostics disagree"
  | _, _, _ => throwError "canonical schema, configuration or FromJson bypassed validation"

run_cmd do
  checkRejected phraseSpec (json% { template: [] }) #[.key "template"]
  checkRejected phraseSpec (json% {
    template: [{ lang: "en", content: "${body}" }, { lang: "en", content: "${type}" }]
  }) #[.key "template"]
  checkRejected phraseSpec (json% { template: [{ lang: "", content: "${body}" }] })
    #[.key "template", .index 0, .key "lang"]
  checkRejected scriptSpec (json% {}) #[.key "template"]
  checkRejected definitionSpec (json% { calc_symbol: "" }) #[.key "calc_symbol"]
  checkRejected definitionSpec (json% {}) #[.key "styles"]

run_cmd do
  let phrase ← match fromJson? (α := PhraseInfo) (json% {
      template: [{ lang: "en", content: "${body}" }] }) with
    | .ok value => pure value
    | .error message => throwError message
  unless phrase.template.size == 1 && toJson phrase.extra == (json% {}) do
    throwError "canonical phrase decoding lost its template or extension-field default"
  let script ← match fromJson? (α := ScriptInfo) (json% { renderer: "remark" }) with
    | .ok value => pure value
    | .error message => throwError message
  unless script.renderer == .remark && script.display && script.template.isEmpty &&
      script.color.tag.isNone && script.color.border.isNone && script.color.background.isNone do
    throwError "canonical script decoding lost derived defaults or nested schema decoding"
  let definition ← match fromJson? (α := DefinitionInfo) (json% { calc_symbol: "=" }) with
    | .ok value => pure value
    | .error message => throwError message
  let display ← match definition.display with
    | .ok value => pure value
    | .error error => throwError error.render
  unless definition.calc_symbol == some "=" && definition.styles.isNone &&
      display.styles.size == 1 && !display.dynamic_arity do
    throwError "canonical definition validation rejected or changed conditional defaults"

end InfoSchemaTest
