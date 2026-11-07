import ProofScript.Info.Theorem
import ProofScript.Output.ProjectRegistry

namespace ProofScript

open Lean

/-- Lake's defining-module ownership, independent of where theorem_info was written. -/
def resolveTheoremProject (env : Environment) (registry : ProjectRegistry) (declaration : Name) :
    Option ProjectKey := registry.declarationProject? env declaration

end ProofScript
