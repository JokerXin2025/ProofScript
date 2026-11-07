/-
    ProofScript.Core.ModuleGraph
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean

open Lean


namespace ProofScript

/-- A module import graph. Each entry records one module and the modules it imports
directly. The graph includes both imported modules and the current module. -/
structure ModuleGraph where
  /-- Maps a module name to its direct imports. -/
  private imports : NameMap (Array Name)

namespace ModuleGraph

/-- Build a module import graph, including the current module and all modules
loaded into the environment. -/
def ofEnvironment (env : Environment) : ModuleGraph := Id.run do
  let mut graph : NameMap (Array Name) := {}
  for i in [:env.header.moduleNames.size] do
    graph := graph.insert env.header.moduleNames[i]! <|
      env.header.moduleData[i]!.imports.map (·.module)
  graph := graph.insert env.mainModule <| env.header.imports.map (·.module)
  return ⟨graph⟩

/-- Check whether `mod` is `mod'` or imports it, directly or indirectly. -/
def dependsOn (graph : ModuleGraph) (mod mod' : Name) : Bool
    := Id.run do
  let mut pending := [mod]
  let mut visited : NameSet := {}
  while !pending.isEmpty do
    let current := pending.head!
    pending := pending.tail!
    if current == mod' then return true
    if visited.contains current then continue
    visited := visited.insert current
    -- every imported module should have an entry
    pending := (graph.imports.find? current |>.getD #[]).toList ++ pending
  return false

/-- Lists the given root module and all its direct and indirect imports, with each
module appearing once.

An imported module always appears before any module that imports it. For example,
if `App` imports `Base`, the result for `App` contains `Base` before `App`. Direct
imports are visited in module-name order, so their original array order does
not affect the result. -/
def modulesInDependencyOrder (graph : ModuleGraph) (root : Name)
    : Except String (Array Name) := do
  unless graph.imports.contains root do throw s!"Unknown module `{root}`"
  /- The Boolean in `pending` is `false` when the module's imports still need to be
  visited, and `true` when they have all been visited and the module can be added
  to the result. -/
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
      -- module import graph should be acyclic
      if active.contains current then continue
      -- every imported module should have an entry
      let imports := graph.imports.find? current |>.getD #[]
      active := active.insert current
      let imports := imports.qsort (·.toString < ·.toString)
      pending := imports.toList.map (·, false) ++ (current, true) :: pending
  return result

end ModuleGraph

end ProofScript
