import ProofScript.Info.Theorem

namespace ProofScript

open Lean

/-- Resolve ownership in the requested module view without consuming unrelated display fields. -/
def resolveTheoremProject (env : Environment) (query : Query) (declaration : Name) :
    Except Diagnostic (Option String) :=
  (do
    unless env.contains declaration do throw { message := "unknown declaration" }
    let view ← resolvePartial theoremSpec env query declaration
    theoremProjectInView env query declaration view
      : Except Diagnostic (Option String)).mapError fun error =>
      { error with kind := some theoremSpec.kind, target := some declaration.toString }

/-- A source theorem without project ownership is an error, never a successful empty dependency list. -/
def requireTheoremProject (env : Environment) (query : Query) (declaration : Name) :
    Except Diagnostic String := do
  let some project ← resolveTheoremProject env query declaration
    | throw ({
        message := "cannot export proof dependencies without a project; configure theorem_info.project"
        kind := some theoremSpec.kind
        target := some declaration.toString
        path := #[.key "project"] } : Diagnostic)
  return project

end ProofScript
