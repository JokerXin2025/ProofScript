import Test.TheoremDependencyImportTest
import ProofScript.Output.Protocol

open Lean Elab Command ProofScript.Info ProofScript.Output
open scoped InfoJson

namespace TheoremDependencyExport

-- ImportTest changes imported projects and introduces a conflict. Publishing the defining
-- owners must still use their own views; its unrelated proof is deliberately not exported.
project_info "项目.甲" { title := "Lossless export identities" }

@theorem «基础.一» : True := by trivial
@lemma «中文.引理'» : True := script
  exact «基础.一»

page_end

run_cmd do
  let env ← getEnv
  let artifacts := moduleArtifacts env env.mainModule
  let views ← match freezeModuleArtifacts env env.mainModule with
    | .ok views => pure views
    | .error error => throwError error.render
  let theorems ← match freezeModuleTheorems env env.mainModule with
    | .ok views => pure views
    | .error error => throwError error.render
  for artifact in artifacts do
    let some (_, snapshot) := views.find? (·.1 == artifact.key.id)
      | throwError "export test is missing an artifact snapshot"
    let facts := (theorems.find? (·.1 == artifact.key.id)).map (·.2)
    let published ← match artifact.exportJson snapshot facts (some "wrong active project") with
      | .ok value => pure value
      | .error error => throwError error
    if let some facts := facts then
      let fields := Json.mkObj <| ["declaration", "projectId", "proofDependencies"].map fun key =>
        (key, (published.getObjVal? key).toOption.getD .null)
      unless (fromJson? fields : Except String TheoremExport).toOption == some facts.value &&
          (published.getObjValAs? String "proofFactsDigest").toOption ==
            some (artifact.proofFactsDigest snapshot.id facts.value) do
        throwError "artifact did not publish its frozen theorem facts"
      if (artifact.exportJson snapshot none).isOk ||
          (artifact.exportJson snapshot (some { facts with snapshotId := "wrong boundary" })).isOk ||
          (artifact.exportJson snapshot (some { facts with value.projectId := "Facts.other" })).isOk ||
          (artifact.exportJson snapshot (some { facts with value.declaration := `wrongDeclaration })).isOk then
        throwError "artifact publication accepted missing or inconsistent theorem facts"
    else
      unless !(published.getObjVal? "proofDependencies").isOk &&
          !(published.getObjVal? "proofFactsDigest").isOk do
        throwError "a page must not pretend to be a zero-dependency theorem"

end TheoremDependencyExport
