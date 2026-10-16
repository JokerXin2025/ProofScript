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

private initialize frozenTheoremExt : SimplePersistentEnvExtension FrozenTheoremFacts (NameMap FrozenTheoremFacts) ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.Info.frozenTheorems
    addEntryFn := fun state facts => state.insert facts.value.declaration facts
    addImportedFn := fun modules => modules.foldl (fun state entries =>
      entries.foldl (fun state facts => state.insert facts.value.declaration facts) state) {} }

def frozenTheoremFacts? (env : Environment) (name : Name) : Option FrozenTheoremFacts :=
  (frozenTheoremExt.getState env).find? name

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

/-- Frozen pages must use their persisted facts; pending proofs resolve only in their owner's view. -/
def theoremFactsForArtifact (env : Environment) (artifact : Output.Artifact)
    (query : Query) (snapshotId : String) : Except Diagnostic (Option FrozenTheoremFacts) := do
  if artifact.key.kind != .proof then return none
  let some declaration := artifact.declaration | return none
  match artifact.scope with
  | .frozen expected =>
    let some facts := frozenTheoremFacts? env declaration
      | throw { message := "missing frozen theorem facts; rebuild the defining module", target := some declaration.toString }
    unless expected == snapshotId && facts.snapshotId == expected && facts.query == query &&
        facts.ownerModule == artifact.key.owner do
      throw { message := "theorem facts disagree with their artifact freeze boundary", target := some declaration.toString }
    return some facts
  | _ => return some (← freezeTheoremFacts env query snapshotId declaration)

/-- Validate every pending proof before page state, snapshots or files are committed. -/
def freezePageTheorems (env : Environment) (query : Query) (snapshotId : String)
    (artifacts : Array Output.Artifact) : Except Diagnostic Environment := do
  let facts ← artifacts.filterMapM fun artifact => theoremFactsForArtifact env artifact query snapshotId
  let mut next := env
  for fact in facts do
    unless fact.ownerModule == env.mainModule do throw { message := "cannot freeze another module's proof" }
    if (frozenTheoremFacts? next fact.value.declaration).isSome then
      throw { message := "theorem facts were already frozen", target := some fact.value.declaration.toString }
    next := frozenTheoremExt.addEntry next fact
  return next

end ProofScript.Info
