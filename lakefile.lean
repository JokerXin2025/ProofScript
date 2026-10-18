import Lake

open Lake DSL System Lean


package ProofScript where
  version := v!"0.1.0"

require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.32.0"

@[default_target]
lean_lib ProofScript

lean_exe proofscriptExport where
  root := `ProofScript.Output.Main
  supportInterpreter := true

@[default_target]
lean_lib Test where
  roots := #[
    `Test.VerificationModeTest,
    `Test.BasicRestrictionsTest,
    `Test.InfoCoreAPITest,
    `Test.InfoSchemaTest,
    `Test.TheoremDependencyContractTest
  ]

/-- Tests that require recording and page effects; build with `TestPage:pageTests`. -/
lean_lib TestPage where
  roots := #[
    `Test.CasesByTermTest,
    `Test.CiteTest,
    `Test.ClaimContextTest,
    `Test.ClaimExistTest,
    `Test.UnpackTermTest,
    `Test.ObtainExistTest,
    `Test.CalcTest,
    `Test.NativeTacticIsolationTest,
    `Test.NestedStrategyTest,
    `Test.CustomComponentTest,
    `Test.ComputationComponentTest,
    `Test.ExprJSONFieldsTest,
    `Test.InferRecordingTest,
    `Test.LatexComponentsTest,
    `Test.PaperExtensionTest,
    `Test.ReferencesOptionTest,
    `Test.RecordingReferencesTest,
    `Test.RecordingSessionTest,
    `Test.RecorderSelectionTest,
    `Test.RecordingNormalizeTest,
    `Test.RecordingConfigTest,
    `Test.RecordingComplexRules,
    `Test.RecordingComplexTest,
    `Test.RecordingRegistrationTest,
    `Test.RecordingAPIRules,
    `Test.RecordingAPITest,
    `Test.RecorderDSLTest,
    `Test.TacticRewriteTest,
    `Test.InfoAPITest,
    `Test.MetadataScopeTest,
    `Test.MetadataScopeImportTest,
    `Test.RendererDependencyScopeTest,
    `Test.TheoremDependencyProbeSupport,
    `Test.TheoremDependencyProbeTest,
    `Test.TheoremDependencyFactsTest,
    `Test.TheoremDependencyModuleTest,
    `Test.TheoremDependencyConflict,
    `Test.TheoremDependencyImportTest,
    `Test.TheoremDependencyExportTest
  ]

namespace ProofScriptPageBuild

private partial def dependsOn (pkg : Package) (key : Name) : Bool :=
  pkg.keyName == key || pkg.depPkgs.any (dependsOn · key)

def sourcePackages (ws : Workspace) (selected : Package) (support : NameSet := {}) : NameSet := Id.run do
  let mut result := ({} : NameSet).insert selected.keyName
  let some framework := ws.packages.find? (·.baseName == `ProofScript) | return result
  for pkg in ws.packages do
    if pkg.keyName != framework.keyName && dependsOn selected pkg.keyName &&
        dependsOn pkg framework.keyName && !support.contains pkg.baseName then
      result := result.insert pkg.keyName
  return result

private def pageConfig (sources : NameSet) (buildRoot : FilePath) (pkg : Package) : PackageConfig pkg.keyName pkg.origName :=
  if sources.contains pkg.keyName then
    { pkg.config with
      buildDir := buildRoot / s!"{pkg.wsIdx}-{pkg.baseName}"
      enableArtifactCache? := some false
      restoreAllArtifacts? := some true }
  else pkg.config

private partial def remapDeps (sources : NameSet) (buildRoot : FilePath) (pkg : Package) : Array Package :=
  pkg.depPkgs.map fun dep =>
    { dep with
      config := pageConfig sources buildRoot dep
      depPkgs := remapDeps sources buildRoot dep }

private def remapPackage (sources : NameSet) (buildRoot : FilePath) (pkg : Package) : Package :=
  { pkg with
    config := pageConfig sources buildRoot pkg
    depPkgs := remapDeps sources buildRoot pkg }

def remapWorkspace (ws : Workspace) (sources : NameSet) (buildRoot : FilePath) : Workspace :=
  let packages := ws.packages.map (remapPackage sources buildRoot)
  { ws with
    packages := packages
    packageMap := packages.foldl (fun map pkg => map.insert pkg.keyName ⟨pkg, rfl⟩) {}
    size_packages_pos := by simpa [packages] using ws.size_packages_pos
    packages_wsIdx := by
      intro i hi
      simpa [packages, remapPackage] using ws.packages_wsIdx (by simpa [packages] using hi)
    depIdxs_packages := by
      intro pkg hp i hi
      obtain ⟨old, hold, rfl⟩ := Array.mem_map.mp hp
      simpa [packages] using ws.depIdxs_packages old hold i hi }

def pageOptions (ws : Workspace) (sources : NameSet) (original : NameMap LeanOptions) : NameMap LeanOptions :=
  ws.packages.foldl (init := original) fun options pkg =>
    if sources.contains pkg.keyName then
      options.insert pkg.baseName ((options.find? pkg.baseName |>.getD {}) ++
        -- Foundations may be compiled before the module that registers this option.
        -- Lean's weak option name still participates in Lake's setup-options trace.
        LeanOptions.ofArray #[⟨`weak.proofScript.pageBuild, .ofBool true⟩])
    else options

def buildRoot (ws : Workspace) (lib : LeanLib) : FilePath :=
  ws.root.dir / ".lake" / "ps4html" / lib.pkg.baseName.toString / lib.name.toString

private def checkedJson [FromJson α] (value : Json) (field : String) : IO α :=
  match value.getObjValAs? α field with
  | .ok result => pure result
  | .error message => throw <| IO.userError s!"invalid PS4HTML session field {field}: {message}"

structure Session where
  file : FilePath
  value : Json
  buildRoot : FilePath
  exportRoot : FilePath
  support : NameSet

/-- The Python coordinator owns the project lock and cleans this session's Lean directory. -/
def readSession (ws : Workspace) (lib : LeanLib) : IO Session := do
  let some session ← IO.getEnv "PS4HTML_BUILD_SESSION"
    | throw <| IO.userError "ps4htmlInputs requires a PS4HTML build session; use the ps4html facet"
  let file := FilePath.mk session |>.normalize
  let value ← match Json.parse (← IO.FS.readFile file) with
    | .ok value => pure value
    | .error message => throw <| IO.userError s!"invalid PS4HTML session JSON: {message}"
  unless (← checkedJson (α := Nat) value "schemaVersion") == 1 do
    throw <| IO.userError "unsupported PS4HTML build session version"
  unless (← checkedJson (α := String) value "package") == lib.pkg.baseName.toString &&
      (← checkedJson (α := String) value "library") == lib.name.toString do
    throw <| IO.userError "PS4HTML build session does not match the requested library"
  let sessionBuild := FilePath.mk (← checkedJson value "buildRoot") |>.normalize
  let exportRoot := FilePath.mk (← checkedJson value "exportRoot") |>.normalize
  unless sessionBuild.isAbsolute && sessionBuild == (buildRoot ws lib).normalize do
    throw <| IO.userError "PS4HTML session must use the library's dedicated page build directory"
  let staging := (ws.root.dir / ".PS4HTML" / "staging").normalize.toString ++ "/"
  unless file.isAbsolute && file.toString.startsWith staging &&
      exportRoot == file.parent.getD ws.root.dir / "release" / ".ProofScript" do
    throw <| IO.userError "PS4HTML exports must use the build session's unpublished release directory"
  unless (← IO.getEnv "PROOF_SCRIPT_OUTPUT_ROOT") == some exportRoot.toString do
    throw <| IO.userError "PROOF_SCRIPT_OUTPUT_ROOT disagrees with the PS4HTML session"
  IO.FS.createDirAll sessionBuild
  unless (← sessionBuild.readDir).isEmpty do
    throw <| IO.userError "PS4HTML page build directory was not cleaned before starting Lake"
  let supportNames : Array String ← match value.getObjVal? "supportPackages" with
    | .error _ => pure #[]
    | .ok _ => checkedJson value "supportPackages"
  let support := supportNames.foldl (fun names name => names.insert name.toName) ({} : NameSet)
  return { file, value, buildRoot := sessionBuild, exportRoot, support }

def mappedLibrary (ws : Workspace) (original : LeanLib) : FetchM LeanLib := do
  let some pkg := ws.findPackageByKey? original.pkg.keyName | error "page build package not found"
  let some lib := pkg.findLeanLib? original.name | error "page build library not found"
  return lib

def moduleClosure (mods : Array Lake.Module) : FetchM (Array Lake.Module) := do
  let mut seen : ModuleSet := ∅
  let mut result := #[]
  for mod in mods do
    for dep in (← (← mod.transImports.fetch).await).push mod do
      unless seen.contains dep do
        seen := seen.insert dep
        result := result.push dep
  return result

def sessionManifest (session : Session) (ws : Workspace) (sources : NameSet)
    (owners modules : Array Lake.Module) : Json :=
  session.value
    |>.setObjVal! "buildMode" (.str "page")
    |>.setObjVal! "pageBuildVersion" (toJson (1 : Nat))
    |>.setObjVal! "owners" (toJson (owners.map (·.name.toString)))
    |>.setObjVal! "sourcePackages" (toJson (ws.packages.filterMap fun pkg =>
      if sources.contains pkg.keyName then some pkg.baseName.toString else none))
    |>.setObjVal! "modules" (.arr (modules.map fun mod => json% {
      name: $(mod.name.toString), "package": $(mod.pkg.baseName.toString),
      source: $(mod.leanFile.toString), olean: $(mod.oleanFile.toString),
      c: $(mod.cFile.toString), setup: $(mod.setupFile.toString) }))

/-- Preserve package resolution when starting a fresh build store in another Lake process. -/
def forwardedLakeOptions (cwd : FilePath) : List String → Array String
  | "-K" :: value :: rest => #["-K", value] ++ forwardedLakeOptions cwd rest
  | "--packages" :: value :: rest =>
    #["--packages", (cwd / value).toString] ++ forwardedLakeOptions cwd rest
  | arg :: rest =>
    let forwarded := if arg.startsWith "-K" then #[arg]
      else if arg.startsWith "--packages=" then
        #["--packages", (cwd / (arg.drop "--packages=".length).toString).toString]
      else #[]
    forwarded ++ forwardedLakeOptions cwd rest
  | [] => #[]

end ProofScriptPageBuild

/-- Compile and export a fresh page session without touching ordinary verification products. -/
library_facet ps4htmlInputs (original) : Unit := do
  let ws ← getWorkspace
  let session ← ProofScriptPageBuild.readSession ws original
  let sources := ProofScriptPageBuild.sourcePackages ws original.pkg session.support
  let workspace := ProofScriptPageBuild.remapWorkspace ws sources session.buildRoot
  let options := ProofScriptPageBuild.pageOptions ws sources (← getLeanOptOverrides)
  withTheReader BuildContext (fun context => { context with
      opaqueWs := workspace, leanOptOverrides := options }) do
    let lib ← ProofScriptPageBuild.mappedLibrary workspace original
    let some exporter ← findLeanExe? `proofscriptExport | error "ProofScript Info exporter not found"
    let libraryJob ← lib.leanArts.fetch
    let exporterJob ← exporter.fetch
    let owners ← (← lib.modules.fetch).await
    let modules ← ProofScriptPageBuild.moduleClosure owners
    (libraryJob.mix exporterJob).mapM fun _ => do
      proc {
        cmd := exporter.file.toString
        args := #[session.exportRoot.toString] ++ owners.map (·.name.toString)
        cwd := workspace.root.dir
        env := (← getAugmentedEnv).push ("PROOF_SCRIPT_OUTPUT_ROOT", some session.exportRoot.toString)
      }
      IO.FS.writeFile session.file
        (ProofScriptPageBuild.sessionManifest session workspace sources owners modules).pretty

/-- Internal recording-test build; the public facet supplies a fresh process and build store. -/
library_facet pageTestInputs (original) : Unit := do
  unless (← IO.getEnv "PS4HTML_PAGE_TEST_TARGET") ==
      some s!"{original.pkg.baseName}/{original.name}" do
    error "pageTestInputs requires the pageTests coordinator; use the pageTests facet"
  let ws ← getWorkspace
  let directory := ws.root.dir / ".lake" / "ps4html-tests" /
    original.pkg.baseName.toString / original.name.toString
  if ← directory.pathExists then IO.FS.removeDirAll directory
  let sources := ProofScriptPageBuild.sourcePackages ws original.pkg
  let workspace := ProofScriptPageBuild.remapWorkspace ws sources directory
  let options := ProofScriptPageBuild.pageOptions ws sources (← getLeanOptOverrides)
  withTheReader BuildContext (fun context => { context with
      opaqueWs := workspace, leanOptOverrides := options }) do
    let lib ← ProofScriptPageBuild.mappedLibrary workspace original
    lib.leanArts.fetch

/-- Recording tests always use a fresh Lake build store, including in multi-target builds. -/
library_facet pageTests (lib) : Unit := do
  let ws ← getWorkspace
  let options := ProofScriptPageBuild.forwardedLakeOptions (← IO.currentDir)
    (ws.lakeArgs?.getD #[]).toList
  Job.async do
    proc {
      cmd := (← getLake).toString
      args := #["--file", ws.root.configFile.toString] ++ options ++
        #["--no-cache", "build", s!"@{lib.pkg.baseName}/{lib.name}:pageTestInputs"]
      cwd := ws.root.dir
      env := (← getAugmentedEnv).push
        ("PS4HTML_PAGE_TEST_TARGET", some s!"{lib.pkg.baseName}/{lib.name}")
    }

/-- Build the complete HTML site for the requested Lean library. -/
library_facet ps4html (lib) : FilePath := do
  let mods ← (← lib.modules.fetch).await
  let root ← getRootPackage
  let pkg := lib.pkg
  Job.async do
    let names := mods.map (·.name.toString)
    let sources := mods.map (·.leanFile.toString)
    let output := root.dir / ".PS4HTML" / "build" / pkg.baseName.toString / lib.name.toString / "index.html"
    let python := (← IO.getEnv "PS4HTML_PYTHON").getD "python3"
    let backend := (← getWorkspace).packages.findSome? fun p =>
      if p.baseName == `ProofScript then some (p.dir / "tools" / "ps4html") else none
    let some backend := backend | error "ProofScript package not found in Lake workspace"
    proc {
      cmd := python
      args := #["-m", "PS4HTML", "_build-library", pkg.baseName.toString, lib.name.toString,
        "--build-dir", (ProofScriptPageBuild.buildRoot (← getWorkspace) lib).toString] ++
        (names.zip sources).flatMap fun (name, source) => #[name, source]
      cwd := root.dir
      env := (← getAugmentedEnv).push ("PYTHONPATH", some backend.toString)
        |>.push ("LAKE", some (← getLake).toString)
        |>.push ("PS4HTML_LAKE_CONFIG", some root.configFile.toString)
        |>.push ("PS4HTML_LAKE_ARGS", some (Lean.toJson ((← getWorkspace).lakeArgs?.getD #[])).compress)
        |>.push ("PS4HTML_LAKE_CWD", some (← IO.currentDir).toString)
    }
    return output
