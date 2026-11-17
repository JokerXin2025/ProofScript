import ProofScript.Output.DeclarationFacts
import ProofScript.Output.ProjectRegistry
import ProofScript.Output.Theorem

namespace ProofScript

open Lean

/-- A proof's project and dependency set resolved together in its owner's final module view. -/
def freezeTheoremFacts (env : Environment) (registry : ProjectRegistry) (moduleName : Name)
    (declaration : Name) :
    Except String TheoremExport :=
  (do
    let some facts := declarationFacts? env declaration
      | throw "missing declaration proof facts; rebuild the defining module"
    unless facts.ownerModule == moduleName do
      throw "declaration belongs to another module"
    let some project := registry.declarationProject? env declaration
      | throw "declaration is not in the Lake project registry"
    let mut dependencies := #[]
    for ref in facts.proofRefs do
      unless ref.isDependency do continue
      let targetProject := registry.declarationProject? env ref.name
      if targetProject == some project then dependencies := dependencies.push ref.name
    let value ← TheoremExport.create declaration facts.declarationKind project.projectId facts.proofRefs dependencies
    return value
       : Except String TheoremExport).mapError (infoTargetError "decl" declaration.toString)

end ProofScript
