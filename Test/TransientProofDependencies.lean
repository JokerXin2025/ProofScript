import ProofScript.Page.Component.Declaration
import ProofScript.Builtin.Scripts
import ProofScript.Output.Module

open Lean ProofScript

set_option pageBuild true

namespace TransientProofDependencies

/-- Keep ordinary private declarations and public names resembling helpers. -/
private def privateValue (x : Nat) := x
def publicValue (x : Nat) := x
def scriptcheck_public (x : Nat) := x
def proof_1 (x : Nat) := x

-- `calc` records a temporary replay before executing the real proof. `grind`
-- creates `_proof_N` constants in that temporary environment.
#page theorem nested_grind (x : Nat) : x + 0 = x := script
  calc
    _ = x := by grind
    _ = x := by grind

#page theorem user_dependencies (x : Nat) :
    privateValue x + publicValue x + proof_1 x = x + x + x := script
  calc
    _ = x + x + x := by rfl

run_cmd do
  let env ← getEnv
  let owner ← getMainModule
  -- Check both constant nodes and effective type descriptors. Neither may
  -- introduce a rendering request for a compiler-generated auxiliary.
  let check := fun (name : Name) (expected : Array Name) => do
    let constant := json% { kind: "const", name: $(name.toString) }
    let descriptor := json% {
      kind: "mdata", data: { "ProofScript.type": $("decl:" ++ name.toString) },
      expr: { kind: "sort" } }
    for expression in #[constant, descriptor] do
      let document := json% { expression: $expression }
      let dependencies ← ofExcept <| recordedDependencies env .null document #[]
        #[#[.key "expression"]]
      unless dependencies == expected do
        throwError "unexpected dependencies for {name}: {dependencies}"
  for name in #[``privateValue, ``scriptcheck_public, ``proof_1, `MissingUserDeclaration] do
    check name #[name]
  for name in #[`helper._proof_1, `helper._proof_7, ``privateValue |>.str "_proof_2",
      Lean.addMacroScope owner `scriptcheck_generated 17] do
    check name #[]

  let explicitTheorem := `helper._proof_1
  let binding : StepBinding := { path := #[.key "step"], contract := default }
   let document := json% { step: { "theorem": {
     kind: "plain", value: $(explicitTheorem.toString) } } }
  let explicitDependencies ← ofExcept <| recordedDependencies env .null document #[binding] #[]
  unless explicitDependencies == #[explicitTheorem] do
    throwError "explicit theorem dependency was discarded"

  -- Even a plain object shaped like an expression reference cannot add roots.
  let fakeRef := json% { step: { "payload": {
    kind: "plain", value: { "$ref": "e0", "kind": "const",
      "name": $(explicitTheorem.toString) } } } }
  let opaqueDependencies ← ofExcept <| recordedDependencies env .null fakeRef #[] #[]
  unless opaqueDependencies.isEmpty do
    throwError "opaque plain payload added dependencies: {opaqueDependencies}"

  -- Explicit requests must still report missing declarations, including an
  -- internal name if a caller explicitly requests it.
  for name in #[`MissingUserDeclaration, `helper._proof_1] do
    match freezeRequestedInfo env owner { decls := #[name] } with
    | .error error =>
        unless (error.splitOn "unknown declaration").length == 2 do throwError "{error}"
    | .ok _ => throwError "missing declaration request was silently discarded: {name}"

  let requests := moduleInfoRequests env owner
  for name in #[``privateValue, ``publicValue, ``proof_1] do
    unless requests.decls.contains name do
      throwError "user declaration was omitted from Info requests: {name}"
  for artifact in moduleArtifacts env owner do
    for dependency in artifact.dependencies do
      if (privateToUserName dependency).isInternal then
        throwError "internal rendering dependency: {dependency}"
  match freezeRequestedInfo env owner requests with
  | .error error => throwError "{error}"
  | .ok _ => pure ()

end TransientProofDependencies
