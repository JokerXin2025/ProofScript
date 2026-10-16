import Lean

namespace ProofScript.Foundation

open Lean

/-- The graph includes the current module as well as imported modules. -/
structure ModuleGraph where
  imports : NameMap (Array Name) := {}

def ModuleGraph.ofImports (modules : Array (Name × Array Name)) : ModuleGraph :=
  ⟨modules.foldl (fun graph (name, imports) => graph.insert name imports) {}⟩

def ModuleGraph.ofEnvironment (env : Environment) : ModuleGraph := Id.run do
  let mut graph : NameMap (Array Name) := {}
  for i in [:env.header.moduleNames.size] do
    graph := graph.insert env.header.moduleNames[i]!
      (env.header.moduleData[i]!.imports.map (·.module))
  graph := graph.insert env.mainModule (env.header.imports.map (·.module))
  return ⟨graph⟩

def ModuleGraph.contains (graph : ModuleGraph) (name : Name) : Bool :=
  graph.imports.contains name

/-- Reflexive reachability, independent of the environment's mainModule. -/
def ModuleGraph.dependsOn (graph : ModuleGraph) (descendant ancestor : Name) : Bool := Id.run do
  let mut pending := [descendant]
  let mut visited : NameSet := {}
  while !pending.isEmpty do
    let current := pending.head!
    pending := pending.tail!
    if current == ancestor then return true
    if visited.contains current then continue
    visited := visited.insert current
    pending := (graph.imports.find? current |>.getD #[]).toList ++ pending
  return false

/-- Stable dependency-first traversal. Direct import order never breaks a tie. -/
def ModuleGraph.order (graph : ModuleGraph) (root : Name) : Except String (Array Name) := do
  unless graph.contains root do throw s!"unknown query module `{root}`"
  let mut pending := [(root, false)]
  let mut active : NameSet := {}
  let mut visited : NameSet := {}
  let mut result := #[]
  while !pending.isEmpty do
    let (current, exiting) := pending.head!
    pending := pending.tail!
    if visited.contains current then continue
    if exiting then
      active := active.erase current
      visited := visited.insert current
      result := result.push current
    else
      if active.contains current then throw s!"cyclic module imports at `{current}`"
      let some imports := graph.imports.find? current
        | throw s!"missing import graph entry for `{current}`"
      active := active.insert current
      let imports := imports.qsort (fun a b => a.toString < b.toString)
      pending := (imports.toList.map (·, false)) ++ ((current, true) :: pending)
  return result

end ProofScript.Foundation
