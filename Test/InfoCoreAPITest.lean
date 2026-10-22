import ProofScript.Info

open Lean Elab Command ProofScript.Info

namespace InfoCoreAPI

/-- A consumer-defined model uses the same public schema API as builtin metadata. -/
structure Document where
  title : String
  revision : Nat := 1
  extra : ExtraFields := {}
  deriving InfoSchema

run_cmd do
  let schema : InfoSchema Document := inferInstance
  let original : Document := { title := "Public schema", extra := ({} : ExtraFields).set "reviewed" (json% true) }
  let restored ← match fromJson? (α := Document) (toJson original) with
    | .ok value => pure value
    | .error message => throwError message
  unless toJson original == schema.encode original &&
      restored.title == original.title && restored.revision == 1 &&
      restored.extra.find? "reviewed" == some (json% true) &&
      (Document.infoFields.revision.set restored 2).revision == 2 do
    throwError "public schema derivation, typed handles or JSON roundtrip failed"
  let env ← getEnv
  for name in #[`ProofScript.Script.Recording, `ProofScript.Script.Recording.Recorder,
      `ProofScript.Script.Command,
      `ProofScript.Script.Recording.Engine, `ProofScript.Page.Model, `ProofScript.Output.Export] do
    if (env.getModuleIdx? name).isSome then throwError m!"metadata entry imported runtime module {name}"

run_cmd do
  let binder : BinderSelector := { argument := 2, count := 1 }
  let color : HexColor := ⟨"#abc"⟩
  let template : ScriptTemplate := .ordinary { lang := "en", tag := "Step", content := "${goal_before}" }
  unless toJson ScriptRenderer.automatic == (json% "none")
    && toJson DefinitionArguments.explicit == (json% "explicit")
    && toJson binder == (json% [2, 1]) && toJson color == (json% "#abc")
    && toJson template == (json% { kind: "ordinary", value: { lang: "en", tag: "Step", content: "${goal_before}" } }) do
    throwError "standard ToJson changed a custom wire representation"
  let restored ← match fromJson? (α := ScriptTemplate) (toJson template) with
    | .ok value => pure value
    | .error message => throwError message
  unless toJson restored == toJson template do
    throwError "standard FromJson failed to decode a nested template"
  if (fromJson? (α := HexColor) (json% "red")).isOk ||
      (fromJson? (α := DefinitionArguments) (json% [1, 1])).isOk ||
      (fromJson? (α := ScriptRenderer) (json% "unknown")).isOk ||
      (fromJson? (α := Document) (json% { title: "Test", unknown: true })).isOk then
    throwError "standard FromJson bypassed domain or schema validation"
  let invalid : DefinitionStyle := { template := "#0", precedence := 101 }
  match fromJson? (α := DefinitionStyle) (toJson invalid) with
  | .error message =>
    unless message.startsWith "precedence:" do throwError "FromJson lost the field path"
  | .ok _ => throwError "standard FromJson bypassed the nested schema override"
  let invalid : StrategyScriptTemplate := {
    lang := "en", tag := "Cases", inline := true,
    cases := #[{ name := "a", tag := "", title := "" }, { name := "b", tag := "", title := "" }] }
  match InfoCodec.decode (α := Array StrategyScriptTemplate) (toJson #[invalid]) with
  | .error error =>
    unless error.path == #[.index 0, .key "inline"] &&
        error.relatedPaths == #[#[.key "cases"]] do
      throwError "structured decoding lost the array index or related fields"
  | .ok _ => throwError "structured decoding bypassed the nested schema override"

open scoped InfoJson in
run_cmd do
  let spec : InfoSpec Document := { kind := "document" }
  let source : ProofScript.Foundation.SourceLocation := ⟨"target-test", 0, 0⟩
  -- Printed spellings, JSON-looking text, numeric components and quoted dots never define identity.
  let targets : Array Name := #[
    `A.B,
    .str .anonymous "A.B",
    .num `A 1,
    .str `A "1",
    .str .anonymous "A».B",
    .str (.str .anonymous "A»") "B",
    .str .anonymous "[\"A\",\"B\"]"]
  let mut env ← getEnv
  for index in [:targets.size] do
    let patch := #[Document.infoFields.title.assignment s!"document {index}" source]
    env ← match commitInfo spec env targets[index]! patch source with
      | .ok updated => pure updated
      | .error error => throwError error.render
  let query : Query := { moduleName := env.mainModule }
  for index in [:targets.size] do
    let target := targets[index]!
    let info ← match resolveInfo spec env query target with
      | .ok info => pure info
      | .error error => throwError error.render
    unless info.value.title == s!"document {index}" do
      throwError "structured target identities collided during event resolution"
    let identity : InfoTarget := { kind := spec.kind, target }
    unless (fromJson? (toJson target) : Except String Name).toOption == some target &&
        ((toJson identity).getObjVal? "target").toOption == some (toJson target) do
      throwError "scoped Name instances disagree with the derived target instances"
    unless (fromJson? (toJson identity) : Except String InfoTarget).toOption == some identity do
      throwError "structured target JSON roundtrip failed"
  let named : InfoTarget := { kind := "theorem", target := `Nat.add_comm }
  let phrase : InfoTarget := { kind := "phrase", target := `forall }
  unless toJson named == (json% { kind: "theorem", target: ["Nat", "add_comm"] }) &&
      toJson phrase == (json% { kind: "phrase", target: ["forall"] }) do
    throwError "all targets must retain Name values and export as arrays"
  for invalid in #[json% [], json% [""], json% [-1], json% [true], json% "Nat.add_comm"] do
    if (fromJson? (α := Name) invalid).isOk then
      throwError "scoped Name decoding must validate the array format"

run_cmd do
  unless toJson `Nat.add_comm == (json% "Nat.add_comm") &&
      (fromJson? (α := Name) (json% "Nat.add_comm")).toOption == some `Nat.add_comm do
    throwError "scoped Name instances changed Lean's default JSON format outside their scope"
  let project : InfoTarget := { kind := "project", target := "A.B" }
  unless toJson project == (json% { kind: "project", target: "A.B" }) &&
      (fromJson? (toJson project) : Except String InfoTarget).toOption == some project do
    throwError "project identities must preserve plain strings"
  for invalid in #[json% { kind: "project", target: ["A", "B"] },
      json% { kind: "project", target: "" }, json% { kind: "theorem", target: "A.B" }] do
    if (fromJson? (α := InfoTarget) invalid).isOk then
      throwError "target decoding accepted the wrong identifier type"
  if (fromJson? (α := TheoremInfo) (json% { project: "" })).isOk then
    throwError "theorem project decoding accepted an empty project name"

end InfoCoreAPI
