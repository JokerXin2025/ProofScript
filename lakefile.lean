import Lake
open Lake DSL System

package ProofScript where
  version := v!"0.1.0"

require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.32.0"

@[default_target]
lean_lib ProofScript

@[default_target]
lean_lib Test where
  roots := #[
    `Test.BasicRestrictionsTest, `Test.CasesByTermTest,
    `Test.CiteTest0,
    `Test.ClaimContextTest, `Test.ClaimExistTest,
    `Test.MultiIntroUnpackTest, `Test.UnpackTermTest,
    `Test.ObtainExistTest, `Test.CalcTest,
    `Test.CalcExecutionCounter, `Test.NativeTacticIsolationTest,
    `Test.NestedStrategyTest,
    `Test.CustomComponentTest, `Test.ComputationComponentTest,
    `Test.ExprJSONFieldsTest, `Test.InferRecordingTest,
    `Test.LatexComponentsTest,
    `Test.PaperExtensionTest,
    `Test.ReferencesOptionTest, `Test.RecordingReferencesTest,
    `Test.RecordingSessionTest, `Test.RecorderSelectionTest,
    `Test.RecordingKernelTest, `Test.RecordingPlanTest,
    `Test.RecordingNormalizeTest, `Test.RecordingConfigTest,
    `Test.RecordingComplexRules, `Test.RecordingComplexTest,
    `Test.RecordingRegistrationTest,
    `Test.TacticRewriteTest
  ]

/-- Build the complete HTML site for the requested Lean library. -/
library_facet ps4html (lib) : FilePath := do
  let mods ← (← lib.modules.fetch).await
  let jobs ← mods.mapM fun mod => mod.leanArts.fetch
  let arts := Job.collectArray jobs
  let root ← getRootPackage
  let pkg := lib.pkg
  arts.mapM fun _ => do
    let names := mods.map (·.name.toString)
    let sources := mods.map (·.leanFile.toString)
    let output := root.dir / ".PS4HTML" / "build" / pkg.baseName.toString / lib.name.toString / "index.html"
    let python := (← IO.getEnv "PS4HTML_PYTHON").getD "python3"
    let backend := (← getWorkspace).packages.findSome? fun p =>
      if p.baseName == `ProofScript then some (p.dir / "tools" / "ps4html") else none
    let some backend := backend | error "ProofScript package not found in Lake workspace"
    proc {
      cmd := python
      args := #["-m", "PS4HTML", "_build-library", pkg.baseName.toString, lib.name.toString] ++ (names.zip sources).flatMap fun (name, source) => #[name, source]
      cwd := root.dir
      env := (← getAugmentedEnv).push ("PYTHONPATH", some backend.toString)
    }
    return output
