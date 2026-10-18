import ProofScript.Core.References
import ProofScript.Page.Component.Core

open Lean
open Lean.Elab.Command
open ProofScript


elab "@""references" : command => whenPageBuild do
  let references := (← getTheoremRefs).toArray
  let component : Component := {
    source := ← liftCoreM <| sourceLocation (← getRef)
    kind := "references", value := toJson references, references }
  match addComponent (← getEnv) component with
  | .error message => throwError message
  | .ok (env, added) =>
    unless added do logWarning "page component appears after page_end and was ignored"
    setEnv env
  clearTheoremRefs
