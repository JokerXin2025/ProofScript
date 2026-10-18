import ProofScript

open Lean Elab Command ProofScript ProofScript.Info

namespace MetadataScope

project_info "MetadataScope.P" { title := "Early project" }
project_info "MetadataScope.Q" { title := "Other project" }
project_info "MetadataScope.P" {}

script_macro scopeExact "scope_exact" proof:term => `(tactic| exact $proof:term)
script_info scopeExact { template := [{ lang := "en", tag := "Early rule", content := "${goal_before}" }] }
var_info "Nat" { default := "n", names := ["n"] }
phrase_info "forall" { template := [{ lang := "en", content := "early ${binder}" }] }

theorem referenceTarget : True := True.intro
theorem_info referenceTarget { name := "Early reference", project := "MetadataScope.P" }

/-- error: expected a string literal -/
#guard_msgs in
@theorem invalidInlineInfo (info := { name := 123 }) : True := script
  scope_exact referenceTarget

/--
error: unsolved goals
⊢ False
-/
#guard_msgs in
@theorem invalidInlineProof (info := { name := "Must not survive" }) : False := by
  skip

run_cmd do
  let env ← getEnv
  for name in #[`MetadataScope.invalidInlineInfo, `MetadataScope.invalidInlineProof] do
    let check := name.getPrefix ++ Name.mkSimple ("scriptcheck_" ++ name.getString!)
    unless !env.contains name && !env.contains check && (declarationFacts? env name).isNone &&
        !(Output.moduleArtifacts env env.mainModule).any (·.declaration == some name) &&
        !(getPageState env).components.any (·.declaration == some name) &&
        !(moduleEvents env env.mainModule).any (·.identity.target == .inl name) do
      throwError "failed inline declaration leaked a declaration, check, facts, artifact, component or metadata"
    let path ← liftIO <| activeOutputPath (proofOutputPath env.mainModule name)
    if ← liftIO path.pathExists then
      throwError "failed inline declaration wrote a proof file"
  unless (← getTheoremRefs).isEmpty do
    throwError "failed inline declaration leaked collected references"

-- Inline metadata works for both proof forms with binders and for lemma identity.
@lemma inlineScriptLemma (info := { name := "Script lemma" }) (n : Nat) : n = n := script
  rfl
@lemma inlineByLemma (info := { name := "By lemma" }) (n : Nat) : n = n := by
  rfl

@theorem early (info := { name := "Early theorem" }) : ∀ _ : Nat, True := script
  scope_exact (fun _ => True.intro)

@theorem earlyDependency : True := script
  cite referenceTarget
  exact referenceTarget
@references

script_info scopeExact { template := [{ lang := "en", tag := "Later rule", content := "${goal_before}" }] }
var_info "Nat" { default := "k", names := ["k"] }
phrase_info "forall" { template := [{ lang := "en", content := "later ${binder}" }] }
project_info "MetadataScope.P" { title := "Later project" }
theorem_info early { name := "Later theorem" }
theorem_info referenceTarget { name := "Later reference", project := "MetadataScope.Q" }
project_info "MetadataScope.P" {}

@theorem later (info := { name := "Later component" }) : ∀ _ : Nat, True := script
  scope_exact (fun _ => True.intro)
@theorem laterDependency : True := script
  cite referenceTarget
  exact referenceTarget
@references

run_cmd do
  let env ← getEnv
  let snapshots ← match freezeModuleArtifacts env env.mainModule with
    | .ok snapshots => pure snapshots
    | .error error => throwError error.render
  let artifacts := Output.moduleArtifacts env env.mainModule
  for name in #[`MetadataScope.inlineScriptLemma, `MetadataScope.inlineByLemma] do
    unless (declarationFacts? env name).any (·.declarationKind == .lemma) do
      throwError "inline metadata changed lemma declaration identity"
  let proofSnapshot := fun name => do
    let some artifact := artifacts.find? (·.declaration == some name)
      | throwError m!"missing proof artifact {name}"
    let some (_, snapshot) := snapshots.find? (·.1 == artifact.key.id)
      | throwError m!"missing proof snapshot {name}"
    unless snapshot.query == artifact.query && snapshot.query.boundary != .endOfModule do
      throwError "proof snapshot lost the captured local boundary"
    pure snapshot
  let early ← proofSnapshot `MetadataScope.early
  let later ← proofSnapshot `MetadataScope.later
  let read := fun (snapshot : Snapshot) (kind : String) (target : Name ⊕ String) => do
    let some record := snapshot.find? kind target
      | throwError m!"missing {kind} record"
    pure record.value
  let check := fun snapshot expectedTag expectedVariable expectedPhrase expectedProject => do
    let ruleInfo : ScriptInfo ← ofExcept <| fromJson? (← read snapshot "script" (.inl `Test.MetadataScopeTest.scopeExact))
    let variableInfo : VariableInfo ← ofExcept <| fromJson? (← read snapshot "variable" (.inl (Name.mkSimple "Nat")))
    let phrase : PhraseInfo ← ofExcept <| fromJson? (← read snapshot "phrase" (.inl (Name.mkSimple "forall")))
    let project : ProjectInfo ← ofExcept <| fromJson? (← read snapshot "project" (.inr "MetadataScope.P"))
    unless ruleInfo.template.any (fun template => match template with
          | .ordinary value => value.lang == "en" && value.tag == expectedTag
          | .strategy _ => false) &&
        variableInfo.default == expectedVariable &&
        phrase.template.any (fun template => template.lang == "en" && template.content == expectedPhrase) &&
        project.title == expectedProject do
      throwError "a later local update changed an earlier rendering configuration"
  check early "Early rule" "n" "early ${binder}" "Early project"
  check later "Later rule" "k" "later ${binder}" "Later project"
  let theoremInfo : TheoremInfo ← ofExcept <| fromJson? (← read early "theorem" (.inl `MetadataScope.early))
  unless theoremInfo.name == "Early theorem" && early.id != later.id do
    throwError "inline metadata or separate content snapshots were lost"
  let facts ← match freezeModuleTheorems env env.mainModule with
    | .ok facts => pure facts
    | .error error => throwError error.render
  for (name, expected) in #[
      (`MetadataScope.earlyDependency, #[`MetadataScope.referenceTarget]),
      (`MetadataScope.laterDependency, #[])] do
    let some (_, fact) := facts.find? (·.2.value.declaration == name)
      | throwError "missing dependency fixture"
    unless fact.value.proofDependencies == expected do
      throwError "dependency project filtering ignored the proof's local boundary"
  let (_, page, _) ← match freezePage env "metadata-scope-test" with
    | .ok frozen => pure frozen
    | .error error => throwError error.render
  let referenceComponents := page.components.filter (·.kind == "references")
  unless referenceComponents.size == 2 do throwError "missing references components"
  for (component, expected) in referenceComponents.zip #["Early reference", "Later reference"] do
    let entries ← ofExcept <| component.value.getArr?
    unless entries.size == 1 do throwError "unexpected references contents"
    let info ← ofExcept <| entries[0]!.getObjVal? "info"
    let name ← ofExcept <| info.getObjValAs? String "name"
    unless name == expected && component.snapshotId.isSome do
      throwError "references component did not retain its own configuration boundary"

page_end

-- Closing the page does not end the module's exported configuration stream.
script_info scopeExact { template := [{ lang := "en", tag := "Imported rule", content := "${goal_before}" }] }
var_info "Nat" { default := "z", names := ["z"] }
phrase_info "forall" { template := [{ lang := "en", content := "imported ${binder}" }] }
project_info "MetadataScope.P" { title := "Imported project" }
theorem_info referenceTarget { name := "Imported reference", project := "MetadataScope.P" }
theorem_info early { name := "Imported theorem", project := "MetadataScope.Q" }

end MetadataScope
