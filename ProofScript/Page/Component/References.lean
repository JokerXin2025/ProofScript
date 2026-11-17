import ProofScript.Core.References
import ProofScript.Page.Component.Core

open Lean
open Lean.Elab.Command
open ProofScript


page_component "references" => do
  when_page_build
    let references : Array RefInfo := (← getTheoremRefs).toArray
    let component : Component := {
      kind := "references", value := toJson references, references }
    let requests : InfoRequests := { decls := references.map (·.name) }
    match addComponent (← getEnv) component requests with
    | .error message => throwError message
    | .ok env =>
      setEnv env
    clearTheoremRefs
