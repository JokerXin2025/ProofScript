import Lean
import ProofScript.Page.Path

namespace ProofScript

open Lean

/-- A single explicit update; interpretation belongs to the Python renderer. -/
structure Lean2TeXEvent where
  owner : Name
  sequence : Nat
  category : String
  target : String
  fields : Json
  source : Option Json := none
  deriving Inhabited

initialize lean2texEventExt : SimplePersistentEnvExtension Lean2TeXEvent (Array Lean2TeXEvent) ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.lean2texEvents
    addEntryFn := fun state entry => state.push entry
    addImportedFn := fun entries => entries.foldl (· ++ ·) #[]
  }

def localLean2TeXEvents (env : Environment) : Array Lean2TeXEvent :=
  (lean2texEventExt.getEntries env).reverse.toArray

def addLean2TeXEvent (env : Environment) (event : Lean2TeXEvent) : Environment :=
  lean2texEventExt.addEntry env event

private def modulePath (owner : Name) : String :=
  String.intercalate "/" (owner.components.map fun part =>
    String.intercalate "" (part.toString.toList.map fun c =>
      if c == '/' || c == '%' || c == '\\' || c == ':' || c == '.' then
        s!"%{c.toNat}X"
      else String.singleton c))

def Lean2TeXEvent.toJson (event : Lean2TeXEvent) : Json := Json.mkObj <| [
  ("sequence", Lean.toJson event.sequence), ("category", Lean.toJson event.category),
  ("target", Lean.toJson event.target), ("fields", event.fields)] ++
  event.source.toList.map (fun source => ("source", source))

/-- Re-emit imported .olean entries under their original owner, including empty local output. -/
def exportLean2TeXEvents (env : Environment) : IO Unit := do
  let mut owners : Array (Name × Array Lean2TeXEvent) := #[]
  for i in [:env.header.moduleNames.size] do
    let owner := env.header.moduleNames[i]!
    let entries := lean2texEventExt.getModuleEntries env i
    owners := owners.push (owner, entries)
  owners := owners.push (env.mainModule, localLean2TeXEvents env)
  for (owner, entries) in owners do
    let file ← activeOutputPath <| outputRoot / "lean2tex" / "events" /
      s!"{modulePath owner}.json"
    ensureParentDir file
    IO.FS.writeFile file <| (Json.mkObj [
      ("schema_version", "0.0.0"), ("module", toJson owner.toString),
      ("events", toJson (entries.map Lean2TeXEvent.toJson))]).pretty

end ProofScript
