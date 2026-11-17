import ProofScript.Info.Decl.Core
import ProofScript.Info.Script.Core
import ProofScript.Core.BuildMode
import ProofScript.Utils.Json

namespace ProofScript

open Lean
open Lean.Elab.Command
open scoped InfoJson

/-- Separate declaration and script requirements, persisted without freezing values. -/
structure InfoRequests where
  decls : Array Name := #[]
  scripts : Array Name := #[]
deriving Inhabited

initialize infoRequestExt : SimplePersistentEnvExtension InfoRequests Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.infoRequests
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

/-- The public entry point for page components. Only local requests are persisted. -/
def requestInfo (env : Environment) (requests : InfoRequests) : Except String Environment :=
  .ok <| infoRequestExt.addEntry env requests

/-- Check all component requirements before publishing any of the updates. -/
def requestComponentInfos (env : Environment) (requests : InfoRequests) :
    Except String Environment :=
  requestInfo env requests

/-- Component elaborators use this gated entry point; requests are never frozen here. -/
def requestInfoCommand (requests : InfoRequests) : CommandElabM Unit := do
  if ← pageBuild? then
    match requestInfo (← getEnv) requests with
    | .ok env => setEnv env
    | .error diagnostic => throwError diagnostic

def moduleInfoRequests (env : Environment) (owner : Name) : InfoRequests :=
  (moduleExtensionEntries infoRequestExt env owner).foldl (fun acc request =>
    { decls := acc.decls ++ request.decls, scripts := acc.scripts ++ request.scripts }) {}

structure FrozenInfos where
  decls : Array (Name × Json) := #[]
  scripts : Array (Name × ScriptInfo) := #[]

/-- Export frozen records without a mixed internal identity type. -/
def FrozenInfos.toRecords (infos : FrozenInfos) : Array Json :=
  infos.decls.map (fun (target, value) => json% {
    identity: { kind: "decl", target: $target }, schemaId: $( ``DeclInfo),
    value: $value }) ++
  infos.scripts.map (fun (target, value) => json% {
    identity: { kind: "script", target: $target }, schemaId: $( ``ScriptInfo),
    value: $value })

/-- Check whether an already discovered dependency path reaches a target. -/
private partial def dependencyReaches (edges : Array (Name × Name))
    (source target : Name) (seen : Array Name := #[]) : Bool :=
  if source == target then true
  else if seen.contains source then false
  else edges.any (fun (parent, child) =>
    parent == source && dependencyReaches edges child target (seen.push source))

/-- Freeze exactly the requested set and its declared Info dependencies. -/
def freezeRequestedInfo (env : Environment) (moduleName : Name)
    (requests : InfoRequests) : Except String FrozenInfos := do
  let mut pending := requests.decls.toList
  let mut frozen : FrozenInfos := {}
  let mut processed : Array Name := #[]
  let mut graphEdges : Array (Name × Name) := #[]
  while !pending.isEmpty do
    let target := pending.head!
    pending := pending.tail!
    if processed.contains target then continue
    processed := processed.push target
    let (value, dependencies) ← freezeDeclInfo env moduleName target
    frozen := { frozen with decls := frozen.decls.push (target, value) }
    for child in dependencies do
      if dependencyReaches graphEdges child target then
        throw <| infoTargetError "decl" (toString child)
          s!"cyclic Info dependency through decl {toString target}"
      graphEdges := graphEdges.push (target, child)
      pending := pending ++ [child]
  for target in requests.scripts do
    unless frozen.scripts.any (·.1 == target) do
      let value ← freezeScriptInfo env moduleName target
      frozen := { frozen with scripts := frozen.scripts.push (target, value) }
  return frozen

end ProofScript
