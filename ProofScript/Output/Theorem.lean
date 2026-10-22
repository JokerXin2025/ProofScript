import ProofScript.Utils.Json

namespace ProofScript.Output

open Lean
open scoped InfoJson

/-- Read-only proof facts projected into named proof artifacts, independent of editable `TheoremInfo`. -/
structure TheoremExport where
  declaration : Name
  projectId : String
  /-- Direct theorem references in the final proof, restricted to the frozen source project. -/
  proofDependencies : Array Name
  deriving Inhabited, Repr, BEq, ToJson

private def validateName (name : Name) : Except String Unit := do
  -- Use the same component validation as the wire codec, including quoted dots and numeric parts.
  discard <| (fromJson? (toJson name) : Except String Name)

def TheoremExport.validate (value : TheoremExport) : Except String Unit := do
  validateName value.declaration |>.mapError ("declaration: " ++ ·)
  if value.projectId.isEmpty then throw "projectId: expected a nonempty project ID"
  let mut seen : NameSet := {}
  for index in [:value.proofDependencies.size] do
    let name := value.proofDependencies[index]!
    validateName name |>.mapError (s!"proofDependencies[{index}]: " ++ ·)
    if name == value.declaration then throw s!"proofDependencies[{index}]: self dependency"
    if seen.contains name then throw s!"proofDependencies[{index}]: duplicate dependency"
    seen := seen.insert name

/-- Normalize facts at their creation boundary; decoding rejects invalid facts instead of repairing them. -/
def TheoremExport.create (declaration : Name) (projectId : String) (dependencies : Array Name) :
    Except String TheoremExport := do
  let names := dependencies.foldl (fun names name =>
    if name == declaration then names else names.insert name) ({} : NameSet)
  let value : TheoremExport := {
    declaration := declaration
    projectId := projectId
    proofDependencies := names.toArray.qsort Name.lt }
  value.validate
  return value

instance : FromJson TheoremExport where
  fromJson? json := do
    let fields ← json.getObj?
    for (key, _) in fields.toList do
      unless #["declaration", "projectId", "proofDependencies"].contains key do
        throw s!"unknown theorem export field `{key}`"
    let value := {
      declaration := ← json.getObjValAs? Name "declaration"
      projectId := ← json.getObjValAs? String "projectId"
      proofDependencies := ← json.getObjValAs? (Array Name) "proofDependencies"
      : TheoremExport }
    value.validate
    return value

end ProofScript.Output
