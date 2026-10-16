import Lean

open Lean System


namespace ProofScript


def outputRoot : FilePath := ".ProofScript"

def activeOutputRoot : IO FilePath := do
  return FilePath.mk ((← IO.getEnv "PROOF_SCRIPT_OUTPUT_ROOT").getD outputRoot.toString)

def activeOutputPath (path : FilePath) : IO FilePath := do
  let root ← activeOutputRoot
  return root / FilePath.mk ((path.toString.drop ".ProofScript/".length).toString)

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

private def modulePath (moduleName : Name) : FilePath :=
  FilePath.mk <|
    String.intercalate "/" <|
      moduleName.components.map encodePathComponent

private def relativeDeclarationPath (moduleName declName : Name) : FilePath :=
  let components := if moduleName.isPrefixOf declName then
    declName.components.drop moduleName.components.length
  else
    declName.components
  FilePath.mk <|
    String.intercalate "/" <|
      components.map encodePathComponent

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

def ensureParentDir (path : FilePath) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent

def contentHash (content : String) : String :=
  toString (hash content)

def resourceJson (path : FilePath) (content mediaType : String) := json% {
  "$resource": {
    path: $(path.toString),
    hash: $(contentHash content),
    mediaType: $mediaType,
    encoding: "utf-8"
  }
}

def resourceReferencePath (path : FilePath) : IO FilePath := do
  let root ← activeOutputRoot
  let rootPrefix := root.toString ++ "/"
  if path.toString.startsWith rootPrefix then
    return outputRoot / FilePath.mk ((path.toString.drop rootPrefix.length).toString)
  return path

private partial def chooseResourcePath (kind extension content hash : String)
    (suffix : Nat) : IO FilePath := do
  let name := if suffix == 0 then hash else s!"{hash}-{suffix}"
  let path ← activeOutputPath (resourceOutputPath kind name extension)
  if !(← path.pathExists) then return path
  if (← IO.FS.readFile path) == content then return path
  chooseResourcePath kind extension content hash (suffix + 1)

def writeTextResource (kind extension mediaType content : String) : IO Json := do
  let hash := contentHash content
  let path ← chooseResourcePath kind extension content hash 0
  ensureParentDir path
  unless ← path.pathExists do
    IO.FS.writeFile path content
  return resourceJson (← resourceReferencePath path) content mediaType

def existingTextResource (path : FilePath) (mediaType : String) : IO Json := do
  let active ← activeOutputPath path
  let content ← IO.FS.readFile active
  return resourceJson (← resourceReferencePath active) content mediaType


end ProofScript
