import Lean.EnvExtension

namespace ProofScript

open Lean

section
variable {α σ : Type} [Inhabited σ]

/-- Read the entries of `ext` belonging to `owner`, in their original insertion
order. The current module keeps its entries locally; imported modules keep theirs
in module tables. -/
def moduleExtensionEntries (ext : SimplePersistentEnvExtension α σ)
    (env : Environment) (owner : Name) : Array α :=
  if owner == env.mainModule then (ext.getEntries env).reverse.toArray
  else (env.getModuleIdx? owner).map (ext.getModuleEntries env) |>.getD #[]

end

end ProofScript
