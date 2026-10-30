import ProofScript.Info.Declaration
import ProofScript.Info.TheoremProject
import ProofScript.Output.Theorem
import ProofScript.Output.Manifest

namespace ProofScript

open Lean

/-- A proof's project and dependency set resolved together in its owner's final module view. -/
structure FrozenTheoremFacts where
  query : Query
  snapshotId : String
  value : TheoremExport
  deriving Inhabited, Repr, BEq

def freezeTheoremFacts (env : Environment) (query : Query) (snapshotId : String) (declaration : Name) :
    Except Diagnostic FrozenTheoremFacts :=
  (do
    let some facts := declarationFacts? env declaration
      | throw { message := "missing declaration proof facts; rebuild the defining module" }
    unless facts.ownerModule == query.moduleName do
      throw { message := "declaration belongs to another module" }
    let project ← requireTheoremProject env query declaration
    let mut dependencies := #[]
    for ref in facts.proofRefs do
      unless ref.isDependency do continue
      let targetProject ← resolveTheoremProject env query ref.name
      if targetProject == some project then dependencies := dependencies.push ref.name
    let value ← (TheoremExport.create declaration facts.declarationKind project facts.proofRefs dependencies).mapError fun message => { message }
    return { query, snapshotId, value }
      : Except Diagnostic FrozenTheoremFacts).mapError fun error =>
        { error with kind := some theoremSpec.kind, target := some declaration.toString }

/-- Rendering and semantic facts must use the artifact owner's final module view. -/
def theoremFactsForArtifact (env : Environment) (artifact : Artifact)
    (snapshotId : String) : Except Diagnostic (Option FrozenTheoremFacts) := do
  if artifact.key.kind != .proof then return none
  let some declaration := artifact.declaration | return none
  return some (← freezeTheoremFacts env artifact.query snapshotId declaration)

end ProofScript
