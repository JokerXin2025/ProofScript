import ProofScript.Core.References
import ProofScript.Page.Component.Command

open Lean
open Lean.Elab.Command
open ProofScript


page_component "references" => do
  when_page_build
    let references : Array RefInfo := (← getTheoremRefs).toArray
    let component : Component := {
      source := ← liftCoreM <| sourceLocation (← getRef)
      kind := "references", value := toJson references, references }
    match addComponent (← getEnv) component with
    | .error message => throwError message
    | .ok (env, added) =>
      unless added do logWarning "page component appears after #page end and was ignored"
      setEnv env
    clearTheoremRefs
