import Lean
import ProofScript.Utils.FileSystem
import ProofScript.Utils.SHA256
import ProofScript.Core.ModuleExtensionEntries

open Lean System


namespace ProofScript


def outputRoot : FilePath := ".ProofScript"

private def encodePathComponent (name : Name) : String := match name with
  | .num _ index => "%N" ++ toString index
  | .str _ text => Id.run do
    let mut result := ""
    let digits := "0123456789ABCDEF".toList.toArray
    for byte in text.toUTF8.data do
      let char := Char.ofNat byte.toNat
      if byte.toNat < 128 && (char.isAlphanum || char == '_') then result := result.push char
      else result := result ++ "%" ++ String.singleton digits[byte.toNat / 16]! ++ String.singleton digits[byte.toNat % 16]!
    return result
  | .anonymous => ""

def modulePath (moduleName : Name) : FilePath :=
  FilePath.mk <|
    String.intercalate "/" <|
      moduleName.components.map encodePathComponent

private def relativeDeclarationPath (moduleName declName : Name) : FilePath :=
  -- Always encode the full identity: stripping a module prefix makes distinct
  -- names such as `foo` and `Project.A.foo` collide.
  let components := if moduleName.isPrefixOf declName then
    declName.components.drop moduleName.components.length
  else
    declName.components
  FilePath.mk <|
    (if moduleName.isPrefixOf declName then "" else "%X/") ++
      String.intercalate "/" (components.map encodePathComponent)

def pageOutputPath (moduleName : Name) : FilePath :=
  let path := modulePath moduleName
  let parent := path.parent.getD (FilePath.mk "")
  let base := outputRoot / "pages"
  let file := s!"{path.fileName.getD "Page"}.json"
  if parent.toString.isEmpty then base / file else base / parent / file

def proofOutputPath (moduleName declName : Name) : FilePath :=
  let moduleDir := modulePath moduleName
  let declPath := relativeDeclarationPath moduleName declName
  let declDir := declPath.parent.getD (FilePath.mk "")
  let declFile := s!"{declPath.fileName.getD "proof"}.json"
  let base := outputRoot / "proofs" / moduleDir
  if declDir.toString.isEmpty then base / declFile else base / declDir / declFile

def resourceOutputPath (kind hash extension : String) : FilePath :=
  outputRoot / "resources" / kind / s!"{hash}.{extension}"

def contentHash (content : String) : String :=
  Json.sha256 (toJson content)

def resourceJson (path : FilePath) (content mediaType : String) := json% {
  "$resource": {
    path: $(path.toString),
    hash: $(contentHash content),
    mediaType: $mediaType,
    encoding: "utf-8"
  }
}

structure TextResource where
  path : FilePath
  content : String

initialize textResourceExt : SimplePersistentEnvExtension TextResource Unit ←
  registerSimplePersistentEnvExtension {
    name := `ProofScript.textResources
    addEntryFn := fun _ _ => ()
    addImportedFn := fun _ => () }

def moduleTextResources (env : Environment) (owner : Name) : Array TextResource :=
  moduleExtensionEntries textResourceExt env owner

/-- A deterministic descriptor can be prepared before the caller commits the
    resource and its owning component together. -/
def textResourceDescriptor (kind extension mediaType content : String) : Json :=
  resourceJson (resourceOutputPath kind (contentHash content) extension)
    content mediaType

/-- Persist content; export writes the resource only after module compilation. -/
def recordTextResource (env : Environment) (kind extension mediaType content : String) :
    Environment × Json := Id.run do
  let path := resourceOutputPath kind (contentHash content) extension
  let resource := { path, content : TextResource }
  let entries := moduleTextResources env env.mainModule
  let updated := if entries.any (fun entry => entry.path == path && entry.content == content) then env
    else textResourceExt.addEntry env resource
  return (updated, resourceJson path content mediaType)

end ProofScript
