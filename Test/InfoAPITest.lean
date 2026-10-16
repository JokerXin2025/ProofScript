import ProofScript

open Lean Elab Command ProofScript.Info

namespace InfoAPI

namespace ProjectNames
project_info "代数学 · 上册" { title := "Unicode project", edition := 1 }
project_info "A.B" { title := "Dotted project" }
project_info "A.B" { description := "One literal name" }
end ProjectNames

project_info "Paper" { title := "Initial project", authors := ["API author"], keywords := ["temporary"] }
project_info "Paper" { title := "Public project", keywords := reset, edition := 2 }

def Wrap (n : Nat) := n
def Equal (a b : Nat) := a = b
structure LiteralType where
  value : Nat
def_info Wrap { unwrap := some 0, reviewed := true }
def_info Equal { «alias» := some Eq }
var_info "Nat" { default := "n", names := ["n", "m"], reviewed := true }
var_info "Nat" { default := "k" }
var_info "InfoAPI.LiteralType" { default := "x", names := ["x"] }
phrase_info "forall" { template := [{ lang := "en", content := "${binder}" }] }
phrase_info "forall" { template := [{ lang := "zh", content := "${type}" }] }

script_macro apiExact "api_exact" proof:term => `(tactic| exact $proof:term)
script_info apiExact { display := false, temporary := "remove" }
script_info apiExact {
  display := reset, temporary := reset, reviewed := true,
  template := [{ lang := "en", tag := "Public rule", content := "${goal_before}" }]
}

/-- error: expected a string literal -/
#guard_msgs in
project_info "Paper" { title := 2026 }

/-- error: duplicate field `display` -/
#guard_msgs in
script_info apiExact { display := true, display := false }

theorem literature : True := True.intro
theorem_info literature { name := "Public reference", project := "代数学 · 上册" }
theorem_info literature { project := some "代数学 · 上册" }

/-- error: unknown project `Missing`; configure it with `project_info` first -/
#guard_msgs in
theorem_info literature { project := "Missing" }

/-- error: expected a string literal -/
#guard_msgs in
theorem_info literature { project := Paper }

/-- error: expected a string literal -/
#guard_msgs in
theorem_info literature { project := «代数学 · 上册» }

/-- error: project names must not be empty -/
#guard_msgs in
project_info "" {}

/-- error: project names must not be empty -/
#guard_msgs in
theorem_info literature { project := "" }

/-- error: expected a string literal -/
#guard_msgs in
project_info "Paper" { title := Paper }

@text "= Public Info API\n\nMetadata, recorded proofs and references use the same snapshot."

@theorem equality (n : Nat) : Equal (Wrap n) n := script
  api_exact rfl
theorem_info equality { name := "Initial theorem", tags := ["temporary"] }
theorem_info equality { name := "Public theorem", tags := [], reviewed := true }

@theorem universal : ∀ _ : Nat, True := script
  api_exact (fun _ => True.intro)

@theorem literal_type : ∀ _ : LiteralType, True := script
  api_exact (fun _ => True.intro)

@theorem citation : True := script
  cite literature
  exact literature

@references

run_cmd do
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  let projects ← match knownProjects env query with
    | .ok projects => pure projects
    | .error error => throwError error.render
  unless projects.contains "Paper" && projects.contains "代数学 · 上册" && projects.contains "A.B" &&
      !projects.contains "InfoAPI.Paper" &&
      (moduleEvents env env.mainModule).any (fun event =>
        event.identity.kind == "project" && event.identity.target == "Paper") do
    throwError "project names must remain literal strings without namespace prefixes"
  let literal ← match resolveVariableInfo env query (Name.mkSimple "InfoAPI.LiteralType") with
    | .ok info => pure info.value
    | .error error => throwError error.render
  let qualified ← match resolvePartial variableSpec env query `InfoAPI.LiteralType with
    | .ok view => pure view
    | .error error => throwError error.render
  unless literal.default == "x" && !qualified.created do
    throwError "literal keys must remain single-component Lean names"
  let project ← match resolveProjectInfo env query "Paper" with
    | .ok value => pure value.value
    | .error error => throwError error.render
  let theoremInfo ← match resolveTheoremInfo env query `InfoAPI.equality with
    | .ok value => pure value.value
    | .error error => throwError error.render
  let rule ← match resolveScriptInfo env query ⟨`Test.InfoAPITest.apiExact⟩ with
    | .ok value => pure value.value
    | .error error => throwError error.render
  unless project.title == "Public project" && project.keywords.isEmpty &&
      project.extra.find? "edition" == some (json% 2) &&
      theoremInfo.name == "Public theorem" && theoremInfo.tags.isEmpty &&
      theoremInfo.project == some "Paper" && rule.display &&
      rule.extra.find? "temporary" == none && rule.extra.find? "reviewed" == some (json% true) do
    throwError "public metadata update, reset, ownership or extra API failed"
  let unicode ← match resolveTheoremInfo env query `InfoAPI.literature with
    | .ok info => pure info.value
    | .error error => throwError error.render
  let dotted ← match resolveProjectInfo env query "A.B" with
    | .ok info => pure info.value
    | .error error => throwError error.render
  unless unicode.project == some "代数学 · 上册" && dotted.title == "Dotted project" &&
      dotted.description == "One literal name" do
    throwError "Unicode and dotted project strings were not preserved"

page_end

theorem_info equality { name := "Later theorem" }
project_info "Paper" { title := "Later project" }

end InfoAPI
