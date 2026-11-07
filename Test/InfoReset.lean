import ProofScript

open Lean Elab Command ProofScript

set_option pageBuild true

namespace InfoReset

def sample : Nat := 1

project_info { title := "before", edition := 2, extra := { note := "old" } }
theorem_info sample { name := "before", extra := { note := "old" } }
decl_info sample { note := "old" }

reset project_info
reset theorem_info sample
reset decl_info sample
reset script_info «simp»

run_cmd do
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  let project ← match resolveInfo projectSpec env query env.mainModule.toString with
    | .ok value => pure value.value
    | .error error => throwError error.render
  unless project.title == "" && project.extra.find? "note" == none &&
      project.extra.find? "edition" == none do
    throwError "project reset did not clear defaults and extension keys"
  let theoremValue ← match resolveInfo theoremSpec env query `InfoReset.sample with
    | .ok value => pure value.value
    | .error error => throwError error.render
  unless theoremValue.name == "" && theoremValue.extra.find? "note" == none do
    throwError "theorem reset did not clear fields"
  let definition ← match resolveInfo definitionSpec env query `InfoReset.sample with
    | .ok value => pure value.value
    | .error error => throwError error.render
  unless definition.kind == .concept && definition.concept_info.templates.isEmpty &&
      definition.extra.find? "note" == none do
    throwError "declaration reset did not clear fields"

theorem_info sample { name := "after", extra := { note := "new" } }
decl_info sample { concept_info := { templates := [{ label := "formula", content := "1" }] } }

run_cmd do
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  let theoremValue ← match resolveInfo theoremSpec env query `InfoReset.sample with
    | .ok value => pure value.value
    | .error error => throwError error.render
  unless theoremValue.name == "after" && theoremValue.extra.find? "note" == some (.str "new") do
    throwError "values after reset were not applied"

end InfoReset
