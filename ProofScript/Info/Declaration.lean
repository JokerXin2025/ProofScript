import ProofScript.Info.Theorem
import ProofScript.Core.References
import Lean.Meta.Tactic.AuxLemma

namespace ProofScript

open Lean

inductive RecordedDeclarationKind where
| «theorem»
| «lemma»
deriving Inhabited, Repr, BEq, ToJson, FromJson

instance : ToString RecordedDeclarationKind where toString
| .theorem => "theorem"
| .lemma => "lemma"

/-- Semantic proof facts and collected references, independent of recording steps and presentation. -/
structure DeclarationFacts where
  declaration : Name
  ownerModule : Name
  declarationKind : RecordedDeclarationKind
  /-- Committed automatic dependencies and manual citations; page consumption cannot clear them. -/
  proofRefs : Array RefInfo
  deriving Inhabited, Repr, BEq

private inductive DeclarationEntry where
  | user (facts : DeclarationFacts)
  | auxiliary (declaration : Name) (constants : Array Name)
  deriving Inhabited

private structure DeclarationState where
  declarations : NameMap DeclarationFacts := {}
  auxiliaries : NameMap (Array Name) := {}
  deriving Inhabited

private def DeclarationState.add (state : DeclarationState) : DeclarationEntry → DeclarationState
  | .user facts => { state with declarations := state.declarations.insert facts.declaration facts }
  | .auxiliary name constants => { state with auxiliaries := state.auxiliaries.insert name constants }

private initialize declarationExt : SimplePersistentEnvExtension DeclarationEntry DeclarationState ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.declarationFacts
    addEntryFn := DeclarationState.add
    addImportedFn := fun modules => modules.foldl (fun state entries => entries.foldl DeclarationState.add state) {} }

def declarationFacts? (env : Environment) (name : Name) : Option DeclarationFacts :=
  (declarationExt.getState env).declarations.find? name

private def usedConstants (env : Environment) (name : Name) : Except Diagnostic (Array Name) := do
  let some info := env.find? name | throw { message := s!"missing proof declaration `{name}`" }
  let some value := info.value? (allowOpaque := true)
    | throw { message := s!"cannot read completed proof `{name}`" }
  return value.getUsedConstants

private structure DeclarationCaptureState where
  active : NameSet := {}
  expanded : NameMap (Array Name) := {}
  deriving Inhabited

private def canonicalNames (names : Array Name) : Array Name :=
  (names.foldl (fun set name => set.insert name) ({} : NameSet)).toArray.qsort Name.lt

/-- Only compiler provenance permits expansion. Existing user definitions and theorems are boundaries. -/
private partial def expandConstant (before env : Environment) (registry : DeclarationState)
    (cached : NameSet) (root name : Name) : StateT DeclarationCaptureState (Except Diagnostic) (Array Name) := do
  if name == root then return #[]
  if registry.declarations.contains name then return #[name]
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

/-- Collect and register a completed proof's references in one transaction.
`before` is the environment before elaborating the proof source. `declaration` is
the public theorem; an explicit `proofSource` may be its already checked helper `def`,
registered immediately before the native theorem command. Return automatic references
for the page staging area; manual citations are supplied from the proof's staged refs. -/
def registerDeclarationFacts (before : Environment) (declaration : Name)
    (kind : RecordedDeclarationKind) (source : SourceLocation)
    (citations : List RefInfo := []) (proofSource : Option Name := none) : MetaM (Array RefInfo) := do
  let env ← getEnv
  let captured : Except Diagnostic (Array Name × DeclarationCaptureState) := (do
    unless (env.find? (proofSource.getD declaration)).any (fun info => match info with
        | .thmInfo _ => true
        | .defnInfo _ => proofSource.isSome
        | _ => false) do
      throw { message := "proof source is not a completed theorem or helper definition" }
    let constants ← usedConstants env (proofSource.getD declaration)
    let registry := declarationExt.getState env
    if registry.declarations.contains declaration then
      throw { message := "declaration facts are already registered" }
    let cached := (Meta.auxLemmasExt.getState env).lemmas.foldl
      (fun names _ entry => names.insert entry.1) ({} : NameSet)
    let action : StateT DeclarationCaptureState (Except Diagnostic) (Array Name) := do
      let mut result := #[]
      for name in constants do
        result := result ++ (← expandConstant before env registry cached declaration name)
      return canonicalNames result
    action.run {} : Except Diagnostic (Array Name × DeclarationCaptureState)).mapError fun error =>
      { error with kind := some theoremSpec.kind, target := some declaration.toString, source := some source }
  let (constants, capture) ← match captured with
    | .ok result => pure result
    | .error error => throwError error.render
  let dependencies ← if dependencyCollection.get (← getOptions) then
      RefInfo.collectConstantRefs constants true
    else pure #[]
  let facts : DeclarationFacts := {
    declaration, ownerModule := env.mainModule, declarationKind := kind,
    proofRefs := (dependencies.foldl RefInfo.mergeRef citations).toArray }
  -- Register the declaration's owner without freezing presentation configuration.
  let env ← match commitInfo theoremSpec env declaration #[] source with
    | .ok env => pure env
    | .error error => throwError error.render
  let env := capture.expanded.foldl (fun env name constants =>
    declarationExt.addEntry env (.auxiliary name constants)) env
  setEnv <| declarationExt.addEntry env (.user facts)
  return dependencies

end ProofScript
