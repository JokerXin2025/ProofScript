import ProofScript.Info.TheoremProject
import ProofScript.Output.Theorem

open Lean Elab Command ProofScript.Info ProofScript.Output
open scoped InfoJson

namespace TheoremDependencyContract

run_cmd do
  let root := `Demo.result
  let dependencies : Array Name := #[
    `A.base, `B.base, .str .anonymous "A.base", .num `A 1,
    .str `A "1", .str (.str .anonymous "中文") "引理'", `B.base, root]
  let value ← match TheoremExport.create root "项目.甲" dependencies with
    | .ok value => pure value
    | .error message => throwError message
  let reordered ← match TheoremExport.create root "项目.甲" dependencies.reverse with
    | .ok value => pure value
    | .error message => throwError message
  unless value == reordered && value.proofDependencies.size == 6 do
    throwError "proof facts must be deterministic, deduplicated and exclude self references"
  unless (fromJson? (toJson value) : Except String TheoremExport).toOption == some value &&
      ((toJson value).getObjValAs? String "projectId").toOption == some "项目.甲" do
    throwError "theorem facts did not preserve lossless names and literal project IDs"
  let empty ← match TheoremExport.create root "项目.甲" #[] with
    | .ok value => pure value
    | .error message => throwError message
  unless (fromJson? (toJson empty) : Except String TheoremExport).isOk do
    throwError "a successfully collected proof may have no project theorem dependencies"
  for invalid in #[
      json% { declaration: ["T"], projectId: "P" },
      json% { declaration: ["T"], projectId: "P", proofDependencies: null },
      json% { declaration: ["T"], projectId: "", proofDependencies: [] },
      json% { declaration: ["T"], projectId: ["P"], proofDependencies: [] },
      json% { declaration: ["T"], projectId: "P", proofDependencies: ["A.base"] },
      json% { declaration: ["T"], projectId: "P", proofDependencies: [[""]] },
      json% { declaration: ["T"], projectId: "P", proofDependencies: [[-1]] },
      json% { declaration: ["T"], projectId: "P", proofDependencies: [["T"]] },
      json% { declaration: ["T"], projectId: "P", proofDependencies: [["A"], ["A"]] },
      json% { declaration: [], projectId: "P", proofDependencies: [] },
      json% { declaration: "T", projectId: "P", proofDependencies: [] },
      json% { declaration: ["T"], projectId: "P", proofDependencies: [], extra: {} }] do
    if (fromJson? (α := TheoremExport) invalid).isOk then
      throwError m!"invalid or legacy proof facts were accepted: {invalid}"
  if (TheoremExport.create root "" #[]).isOk ||
      (TheoremExport.create .anonymous "P" #[]).isOk ||
      (TheoremExport.create root "P" #[.str .anonymous ""]).isOk then
    throwError "fact creation bypassed identity validation"

theorem sample : True := True.intro
theorem foreign : True := True.intro

run_cmd do
  -- The ownership contract is a pure API test, independent of page command mode.
  let source : ProofScript.Foundation.SourceLocation := ⟨"project-contract", 0, 0⟩
  let mut original ← getEnv
  for (project, title) in #[("项目.甲", "Local project"), ("External", "Other project")] do
    original ← match commitInfo projectSpec original project
        #[ProjectInfo.infoFields.title.assignment title source] source none
        #[{ key := activeProjectBinding, value := toJson project, source }] with
      | .ok env => pure env
      | .error error => throwError error.render
  original ← match commitInfo theoremSpec original `TheoremDependencyContract.foreign
      #[TheoremInfo.infoFields.project.assignment (some "External") source] source with
    | .ok env => pure env
    | .error error => throwError error.render
  let query : Query := { moduleName := original.mainModule }
  let root := `TheoremDependencyContract.sample
  let check := fun env query defaultProject expected => do
    match resolveTheoremProject env query root defaultProject with
    | .ok actual => unless actual == expected do
        throwError m!"wrong project ownership: {actual}, expected {expected}"
    | .error error => throwError error.render
  -- Current active project is External; only the declaration-time default is relevant here.
  check original query (some "项目.甲") (some "项目.甲")
  check original query none none
  match requireTheoremProject original query root with
  | .error error => unless error.path == #[.key "project"] do
      throwError "missing source ownership must have a project diagnostic"
  | .ok _ => throwError "missing ownership must not look like an empty dependency list"
  let titled ← match commitInfo theoremSpec original root
      #[TheoremInfo.infoFields.name.assignment "A title only" source] source with
    | .ok env => pure env
    | .error error => throwError error.render
  check titled query (some "项目.甲") (some "项目.甲")
  let frozenQuery := { query with boundary := currentBoundary titled }
  let assigned ← match commitInfo theoremSpec titled root
      #[TheoremInfo.infoFields.project.assignment (some "External") source] source with
    | .ok env => pure env
    | .error error => throwError error.render
  check assigned query (some "项目.甲") (some "External")
  check assigned frozenQuery (some "项目.甲") (some "项目.甲")
  let cleared ← match commitInfo theoremSpec assigned root
      #[TheoremInfo.infoFields.project.assignment none source] source with
    | .ok env => pure env
    | .error error => throwError error.render
  check cleared query (some "项目.甲") none
  let resetEnv ← match commitInfo theoremSpec assigned root
      #[{ key := .builtin "project", operation := .reset, source := source }] source with
    | .ok env => pure env
    | .error error => throwError error.render
  check resetEnv query (some "项目.甲") none
  unless (resolveTheoremProject assigned query `TheoremDependencyContract.foreign).toOption ==
      some (some "External") do
    throwError "ordinary theorem ownership must use its own metadata"
  for missing in #["Missing", ""] do
    match resolveTheoremProject original query root (some missing) with
    | .error error => unless error.path == #[.key "project"] do
        throwError "unknown source project must retain its diagnostic field"
    | .ok _ => throwError "unconfigured project was accepted"
  if (resolveTheoremProject original query `UnknownDeclaration (some "项目.甲")).isOk then
    throwError "unknown declarations cannot acquire ownership"

end TheoremDependencyContract
