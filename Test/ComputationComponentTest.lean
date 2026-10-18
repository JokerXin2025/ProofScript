import ProofScript

def chooseOffset (large : Bool) : Nat :=
  if large then 128 else 112

structure ComputationRequest where
  value : Nat
deriving Lean.FromJson

structure ComputationResponse where
  doubled : Nat
deriving Lean.ToJson

def doubleValue (request : ComputationRequest) : Except String ComputationResponse :=
  if request.value > 100 then .error "value is too large"
  else .ok { doubled := request.value * 2 }

@computation {
  metadata := (title := "Finite computation", label := "finite-computation"),
  renderer := "proofscript/test-table-v1",
  function := chooseOffset,
  payload := r#"{"inputs":[{"value":false,"output":112},{"value":true,"output":128}]}"#}

@computation {
  metadata := (title := "Typed computation", label := "typed-computation"),
  renderer := "proofscript/test-json-v1",
  function := doubleValue,
  payload := r#"{"input":{"value":21}}"#}

@computation {
  payload := r#"{"inputs":[{"value":false,"output":112}]}"#,
  function := chooseOffset,
  renderer := "proofscript/test-table-v1",
  metadata := (title := "Reordered computation", label := "reordered-computation")}

/--
error: unknown @computation field `renderre`
-/
#guard_msgs (error) in
@computation {
  metadata := (title := "Invalid computation"),
  renderre := "proofscript/test-table-v1",
  function := chooseOffset,
  payload := r#"{}"#}

/--
error: duplicate @computation field `renderer`
-/
#guard_msgs (error) in
@computation {
  metadata := (title := "Duplicate computation"),
  renderer := "proofscript/test-table-v1",
  renderer := "proofscript/test-json-v1",
  function := chooseOffset,
  payload := r#"{}"#}

structure MissingCodec where
  value : Nat

def missingCodec (request : MissingCodec) : Nat := request.value

/--
error: failed to synthesize
  Lean.FromJson MissingCodec

Hint: Additional diagnostic information may be available using the `set_option diagnostics true` command.
-/
#guard_msgs (error) in
@computation {
  metadata := (title := "Missing codec"),
  renderer := "proofscript/test-json-v1",
  function := missingCodec,
  payload := r#"{}"#}

def twoArguments (left right : Nat) : Nat := left + right

/--
error: @computation requires a function with exactly one explicit argument
-/
#guard_msgs (error) in
@computation {
  metadata := (title := "Two arguments"),
  renderer := "proofscript/test-json-v1",
  function := twoArguments,
  payload := r#"{}"#}

-- Re-exporting into a fresh staging root must keep the page manifest reference stable.
run_cmd do
  let env ← Lean.getEnv
  for component in (ProofScript.getPageState env).components do
    if component.kind == "computation" then
      let execution ← Lean.ofExcept <| component.value.getObjVal? "execution"
      let entry ← Lean.ofExcept <| execution.getObjValAs? String "entry"
      let manifest ← Lean.ofExcept <| execution.getObjValAs? String "manifest"
      let expected := ProofScript.Computation.pendingEntryPath env.mainModule.toString entry
      unless manifest == expected.toString do
        throwError "computation page contains a physical staging path"
      let physical ← Lean.Elab.Command.liftIO <| ProofScript.activeOutputPath expected
      unless ← Lean.Elab.Command.liftIO physical.pathExists do
        throwError "computation manifest was not written into the active output root"

page_end
