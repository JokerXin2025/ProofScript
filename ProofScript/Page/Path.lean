import Lean

open Lean System


namespace ProofScript


def outputRoot : FilePath := ".ProofScript"

def activeOutputRoot : IO FilePath := do
  return FilePath.mk ((← IO.getEnv "PROOF_SCRIPT_OUTPUT_ROOT").getD outputRoot.toString)

def activeOutputPath (path : FilePath) : IO FilePath := do
  let root ← activeOutputRoot
  return root / FilePath.mk ((path.toString.drop ".ProofScript/".length).toString)

private def modulePath (moduleName : Name) : FilePath :=
  FilePath.mk <|
    String.intercalate "/" <|
      moduleName.components.map (·.toString)

private def relativeDeclarationPath (moduleName declName : Name) : FilePath :=
  let components := if moduleName.isPrefixOf declName then
    declName.components.drop moduleName.components.length
  else
    declName.components
  FilePath.mk <|
    String.intercalate "/" <|
      components.map (·.toString)

def pageOutputPath (moduleName : Name) : FilePath :=
  let path := modulePath moduleName
  let parent := path.parent.getD (FilePath.mk "")
  outputRoot / "pages" / parent / s!"{path.fileName.getD "Page"}.json"

def projectInfoOutputPath (moduleName : Name) : FilePath :=
  outputRoot / "projects" / s!"{(modulePath moduleName).toString}.json"

def proofOutputPath (moduleName declName : Name) : FilePath :=
  let moduleDir := modulePath moduleName
  let declPath := relativeDeclarationPath moduleName declName
  let declDir := declPath.parent.getD (FilePath.mk "")
  let declFile := s!"{declPath.fileName.getD "proof"}.json"
  outputRoot / "proofs" / moduleDir / declDir / declFile

def resourceOutputPath (kind hash extension : String) : FilePath :=
  outputRoot / "resources" / kind / s!"{hash}.{extension}"

def ensureParentDir (path : FilePath) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent

def contentHash (content : String) : String :=
  toString (hash content)

def resourceJson (path : FilePath) (content mediaType : String) : Json :=
  Json.mkObj [("$resource", Json.mkObj [
    ("path", Json.str path.toString),
    ("hash", Json.str (contentHash content)),
    ("mediaType", Json.str mediaType),
    ("encoding", Json.str "utf-8")
  ])]

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
