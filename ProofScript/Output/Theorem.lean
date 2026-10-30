import ProofScript.Utils.Json
import ProofScript.Info.Declaration

namespace ProofScript

open Lean
open scoped InfoJson

/-- Read-only proof facts projected into named proof artifacts, independent of editable `TheoremInfo`. -/
structure TheoremExport where
  declaration : Name
  declarationKind : RecordedDeclarationKind
  projectId : String
  /-- Complete proof references, including citations and targets outside the source project. -/
  proofRefs : Array RefInfo
  /-- Automatic references restricted to the frozen source project, for theorem navigation. -/
  proofDependencies : Array Name
  deriving Inhabited, Repr, BEq, ToJson

private def validateName (name : Name) : Except String Unit := do
  -- Use the same component validation as the wire codec, including quoted dots and numeric parts.
  discard <| (fromJson? (toJson name) : Except String Name)

def TheoremExport.validate (value : TheoremExport) : Except String Unit := do
  validateName value.declaration |>.mapError ("declaration: " ++ ·)
  if value.projectId.isEmpty then throw "projectId: expected a nonempty project ID"
  let mut references : NameSet := {}
  for (ref, index) in value.proofRefs.zipIdx do
    validateName ref.name |>.mapError (s!"proofRefs[{index}].name: " ++ ·)
    if ref.name == value.declaration then throw s!"proofRefs[{index}]: self reference"
    if references.contains ref.name then throw s!"proofRefs[{index}]: duplicate reference name"
    references := references.insert ref.name
  let mut seen : NameSet := {}
  for index in [:value.proofDependencies.size] do
    let name := value.proofDependencies[index]!
    validateName name |>.mapError (s!"proofDependencies[{index}]: " ++ ·)
    if name == value.declaration then throw s!"proofDependencies[{index}]: self dependency"
    if seen.contains name then throw s!"proofDependencies[{index}]: duplicate dependency"
    unless value.proofRefs.any (fun ref => ref.name == name && ref.isDependency) do
      throw s!"proofDependencies[{index}]: missing automatic reference in proofRefs"
    seen := seen.insert name

/-- Normalize facts at their creation boundary; decoding rejects invalid facts instead of repairing them. -/
def TheoremExport.create (declaration : Name) (declarationKind : RecordedDeclarationKind)
    (projectId : String) (refs : Array RefInfo) (dependencies : Array Name) :
    Except String TheoremExport := do
  let refs := refs.foldl RefInfo.mergeRef []
  let names := dependencies.foldl (fun names name =>
    if name == declaration then names else names.insert name) ({} : NameSet)
  let value : TheoremExport := {
    declaration := declaration
    declarationKind := declarationKind
    projectId := projectId
    proofRefs := (refs.toArray.filter (·.name != declaration)).qsort (fun a b => Name.lt a.name b.name)
    proofDependencies := names.toArray.qsort Name.lt }
  value.validate
  return value

instance : FromJson TheoremExport where
  fromJson? json := do
    let fields ← json.getObj?
    for (key, _) in fields.toList do
      unless #["declaration", "declarationKind", "projectId", "proofRefs", "proofDependencies"].contains key do
        throw s!"unknown theorem export field `{key}`"
    let refs ← match json.getObjVal? "proofRefs" with
      | .ok refs => fromJson? refs
      | .error _ => throw "missing proofRefs; rebuild the defining module"
    let value := {
      declaration := ← json.getObjValAs? Name "declaration"
      declarationKind := ← json.getObjValAs? RecordedDeclarationKind "declarationKind"
      projectId := ← json.getObjValAs? String "projectId"
      proofRefs := refs
      proofDependencies := ← json.getObjValAs? (Array Name) "proofDependencies"
      : TheoremExport }
    value.validate
    return value

end ProofScript
