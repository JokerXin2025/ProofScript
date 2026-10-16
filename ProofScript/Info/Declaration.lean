import ProofScript.Info.TheoremProject
import Lean.Meta.Tactic.AuxLemma

namespace ProofScript.Info

open Lean

inductive RecordedDeclarationKind where
  | theorem | lemma
  deriving Inhabited, Repr, BEq

def RecordedDeclarationKind.toString : RecordedDeclarationKind → String
  | .theorem => "theorem"
  | .lemma => "lemma"

/-- Semantic proof facts, independent of recording steps, citations and presentation metadata. -/
structure DeclarationFacts where
  declaration : Name
  ownerModule : Name
  sequence : Nat
  declarationKind : RecordedDeclarationKind
  defaultProject : Option String
  /-- Final proof constants with compiler helpers expanded, but user declarations left intact. -/
  proofConstants : Array Name
  deriving Inhabited, Repr, BEq

private inductive DeclarationEntry where
  | user (facts : DeclarationFacts)
  | auxiliary (declaration : Name) (constants : Array Name)
  | check (declaration target : Name)
  deriving Inhabited

private structure DeclarationState where
  declarations : NameMap DeclarationFacts := {}
  auxiliaries : NameMap (Array Name) := {}
  checks : NameMap Name := {}
  deriving Inhabited

private def DeclarationState.add (state : DeclarationState) : DeclarationEntry → DeclarationState
  | .user facts => { state with declarations := state.declarations.insert facts.declaration facts }
  | .auxiliary name constants => { state with auxiliaries := state.auxiliaries.insert name constants }
  | .check name target => { state with checks := state.checks.insert name target }

private initialize declarationExt : SimplePersistentEnvExtension DeclarationEntry DeclarationState ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.Info.declarationFacts
    addEntryFn := DeclarationState.add
    addImportedFn := fun modules => modules.foldl (fun state entries => entries.foldl DeclarationState.add state) {} }

def declarationFacts? (env : Environment) (name : Name) : Option DeclarationFacts :=
  (declarationExt.getState env).declarations.find? name

def internalTheoremTarget? (env : Environment) (name : Name) : Option Name :=
  (declarationExt.getState env).checks.find? name

def moduleDeclarationFacts (env : Environment) (owner : Name) : Array DeclarationFacts :=
  let entries := if owner == env.mainModule then (declarationExt.getEntries env).reverse.toArray
    else (env.getModuleIdx? owner).map (declarationExt.getModuleEntries env) |>.getD #[]
  entries.filterMap fun entry => match entry with | .user facts => some facts | _ => none

private def usedConstants (env : Environment) (name : Name) : Except Diagnostic (Array Name) := do
  let some info := env.find? name | throw { message := s!"missing proof declaration `{name}`" }
  let some value := info.value? (allowOpaque := true)
    | throw { message := s!"cannot read completed proof `{name}`" }
  return value.getUsedConstants

private structure CaptureState where
  active : NameSet := {}
  expanded : NameMap (Array Name) := {}
  deriving Inhabited

private def canonicalNames (names : Array Name) : Array Name :=
  (names.foldl (fun set name => set.insert name) ({} : NameSet)).toArray.qsort Name.lt

/-- Only compiler provenance permits expansion. Existing user definitions and theorems are boundaries. -/
private partial def expandConstant (before env : Environment) (registry : DeclarationState)
    (cached : NameSet) (root name : Name) : StateT CaptureState (Except Diagnostic) (Array Name) := do
  if name == root then return #[]
  if registry.declarations.contains name then return #[name]
  if let some target := registry.checks.find? name then return #[target]
  if let some constants := registry.auxiliaries.find? name then return constants
  if let some constants := (← get).expanded.find? name then return constants
  let some info := env.find? name | throw { message := s!"unknown proof constant `{name}`" }
  if !cached.contains name && before.contains name then return #[name]
  -- New constructors/recursors are not auxiliary proof bodies and cannot hide theorem references.
  let some value := info.value? (allowOpaque := true) | return #[name]
  if (← get).active.contains name then throw { message := s!"cyclic auxiliary proof at `{name}`" }
  modify fun state => { state with active := state.active.insert name }
  let mut constants := #[]
  for reference in value.getUsedConstants do
    constants := constants ++ (← expandConstant before env registry cached root reference)
  let normalized := canonicalNames constants
  modify fun state => { state with
    active := state.active.erase name
    expanded := state.expanded.insert name normalized }
  return normalized

/-- Construct a complete successful declaration transaction without installing a partial registry.
`before` is the environment before elaborating the opaque and its explicitly named check theorem. -/
def registerDeclarationFacts (before env : Environment) (declaration check : Name)
    (kind : RecordedDeclarationKind) (defaultProject : Option String)
    (source : Foundation.SourceLocation) : Except Diagnostic Environment :=
  (do
    let constants ← usedConstants env declaration
    unless (env.find? check).any (·.isTheorem) do
      throw { message := "missing internal theorem check" }
    let registry := declarationExt.getState env
    if registry.declarations.contains declaration || registry.checks.contains check then
      throw { message := "declaration facts are already registered" }
    let cached := (Meta.auxLemmasExt.getState env).lemmas.foldl
      (fun names _ entry => names.insert entry.1) ({} : NameSet)
    let action : StateT CaptureState (Except Diagnostic) (Array Name) := do
      let mut result := #[]
      for name in constants do
        result := result ++ (← expandConstant before env registry cached declaration name)
      return canonicalNames result
    let (proofConstants, capture) ← action.run {}
    let sequence := infoEventExt.getState env
    let facts : DeclarationFacts := {
      declaration, ownerModule := env.mainModule, sequence,
      declarationKind := kind, defaultProject, proofConstants }
    -- Initialize at declaration time, so a later title-only update cannot pick a new active project.
    let env ← commitInfo theoremSpec env declaration #[] source
      (some #[TheoremInfo.infoFields.project.assignment defaultProject source])
    let env := capture.expanded.foldl (fun env name constants =>
      declarationExt.addEntry env (.auxiliary name constants)) env
    let env := declarationExt.addEntry env (.check check declaration)
    return declarationExt.addEntry env (.user facts) : Except Diagnostic Environment).mapError fun error =>
      { error with kind := some theoremSpec.kind, target := some declaration.toString, source := some source }

end ProofScript.Info
