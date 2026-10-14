import ProofScript.Core.References
import ProofScript.Page.Component.Core

open Lean
open ProofScript


private def referencesJson (env : Environment) (refs : List Name) : Json :=
  Json.arr <| refs.toArray.filterMap fun name =>
    (findTheoremInfo env name).map fun info =>
      Json.mkObj [("name", toJson name), ("info", toJson info)]

elab "@""references" : command => do
  let refsJson := referencesJson (← getEnv) (← getTheoremRefs)
  addPageComponent (← getRef) "references" refsJson
  clearTheoremRefs
