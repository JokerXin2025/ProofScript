import ProofScript.Info.Declaration
import ProofScript.Output.Theorem
import ProofScript.Output.Manifest

namespace ProofScript.Info

open Lean

/-- A proof's project and dependency set resolved together at exactly one configuration boundary. -/
structure FrozenTheoremFacts where
  ownerModule : Name
  query : Query
  snapshotId : String
  value : Output.TheoremExport
  deriving Inhabited, Repr, BEq

def freezeTheoremFacts (env : Environment) (query : Query) (snapshotId : String) (declaration : Name) :
    Except Diagnostic FrozenTheoremFacts :=
  (do
    let some facts := declarationFacts? env declaration
      | throw { message := "missing declaration proof facts; rebuild the defining module" }
    unless facts.ownerModule == query.moduleName && query.includes facts.ownerModule facts.sequence do
      throw { message := "declaration is outside its proof freeze boundary" }
    let project ← requireTheoremProject env query declaration facts.defaultProject
    let mut dependencies := #[]
    for name in facts.proofConstants do
      let target := internalTheoremTarget? env name |>.getD name
      if target == declaration then continue
      let recorded := declarationFacts? env target
      unless recorded.isSome || (env.find? target).any (·.isTheorem) do continue
      let targetProject ← resolveTheoremProject env query target (recorded.bind (·.defaultProject))
      if targetProject == some project then dependencies := dependencies.push target
    let value ← (Output.TheoremExport.create declaration project dependencies).mapError fun message => { message }
    return { ownerModule := facts.ownerModule, query, snapshotId, value }
      : Except Diagnostic FrozenTheoremFacts).mapError fun error =>
        { error with kind := some theoremSpec.kind, target := some declaration.toString }

/-- Rendering and semantic facts must use the artifact's recorded content boundary. -/
def theoremFactsForArtifact (env : Environment) (artifact : Output.Artifact)
    (query : Query) (snapshotId : String) : Except Diagnostic (Option FrozenTheoremFacts) := do
  if artifact.key.kind != .proof then return none
  let some declaration := artifact.declaration | return none
  unless artifact.query == query && artifact.boundary != .endOfModule do
    throw { message := "theorem facts disagree with their content boundary", target := some declaration.toString }
  return some (← freezeTheoremFacts env query snapshotId declaration)

end ProofScript.Info
