import ProofScript.Page.Component.Command
import Lean.Data.Json
import ProofScript.Output.Path
import ProofScript.Page.Model
import ProofScript.Script.Recording.ComputationEncoding

open Lean
open System
open Lean.Elab.Command (CommandElabM liftCoreM liftIO liftTermElabM)
open ProofScript


namespace ProofScript.Computation


private def success (value : Json) := json% { ok: true, value: $value }

private def failure (code message : String) := json% {
  ok: false,
  "error": { code: $code, message: $message }
}

/-- Executes a typed pure function behind the `proofscript-json-v1` string ABI. -/
def invokeJson [FromJson α] [ToJson β]
    (f : α → Except String β) (input : String) : String :=
  let result := do
    let json ← Json.parse input |>.mapError fun error => failure "invalid-json" error
    let request ← fromJson? json |>.mapError fun error => failure "invalid-input" error
    let response ← f request |>.mapError fun error => failure "computation-error" error
    return success (toJson response)
  Json.compress <| match result with
    | .ok response => response
    | .error error => error


structure EntryType where
  input : String
  output : String
  errorMode : String
deriving Inhabited, ToJson

structure PendingEntry where
  schemaVersion : String := "0.0.0"
  abi : String := "proofscript-json-v1"
  bundleId : String
  entry : String
  wrapper : String
  module : String
  functionType : EntryType
  source : SourceLocation
deriving Inhabited, ToJson

def pendingEntryPath (moduleName declaration : String) : FilePath :=
  let modulePath := String.intercalate "/" <| moduleName.splitOn "."
  let declarationPath := String.intercalate "/" <| declaration.splitOn "."
  outputRoot / "computations" / "pending" /
    FilePath.mk modulePath / s!"{declarationPath}.json"

def writePendingEntry (entry : PendingEntry) : IO FilePath := do
  let reference := pendingEntryPath entry.module entry.entry
  let path ← activeOutputPath reference
  path.ensureParentDir
  IO.FS.writeFile path (toJson entry).pretty
  -- Persist a logical reference; a staging directory must not change page content digests.
  return reference


end ProofScript.Computation


namespace ProofScript


/-- Frozen provenance for the Lean declaration backing an interactive computation.
    Complete JSON export goes through `encode`, which exports its independent expression graph. -/
structure ComputationFunction where
  recording : RecordedValue
deriving Inhabited

/-- Encode frozen provenance without consulting the declaration again. -/
def ComputationFunction.encode (function : ComputationFunction) : Except String Json :=
  encodeComputationFunction function.recording

structure ComputationExecution where
  backend : String := "wasm"
  status : String := "pending"
  abi : String := "proofscript-json-v1"
  bundleId : String
  entry : String
  wrapper : String
  manifest : String
deriving Inhabited, ToJson

/--
Page-level contract for an interactive computation.

`payload` is interpreted by the named renderer. ProofScript additionally exports a
structured Lean expression as provenance and an intermediate artifact; it is not a
browser execution ABI. Renderers should select an execution backend by `renderer`.
-/
structure ComputationComponent where
  schemaVersion : String := "0.0.0"
  metadata : ComponentMetadata
  renderer : String
  function : ComputationFunction
  execution : ComputationExecution
  payload : Json
deriving Inhabited

def ComputationComponent.encode (component : ComputationComponent) : Except String Json := do
  let function ← component.function.encode
  return json% {
    schemaVersion: $(component.schemaVersion), metadata: $(component.metadata),
    renderer: $(component.renderer), function: $function,
    execution: $(component.execution), payload: $(component.payload)
  }

private structure FunctionShape where
  input : Expr
  output : Expr
  errorMode : String

private def functionShape (stx : Syntax) (info : ConstantInfo) : CommandElabM FunctionShape :=
  liftTermElabM do
    unless info.levelParams.isEmpty do
      throwErrorAt stx "#page computation does not yet support universe-polymorphic entry functions"
    let type ← Meta.whnf info.type
    let .forallE _ input result binderInfo := type
      | throwErrorAt stx "#page computation requires a function with exactly one explicit argument"
    unless binderInfo == .default do
      throwErrorAt stx "#page computation requires an explicit input argument"
    if result.hasLooseBVars then
      throwErrorAt stx "#page computation does not support dependent output types"
    let result ← Meta.whnf result
    match result with
    | .forallE .. =>
        throwErrorAt stx "#page computation requires a function with exactly one explicit argument"
    | _ => pure ()
    let (output, errorMode) ←
      match result with
      | .app (.app (.const ``Except _) errorType) output =>
          unless ← Meta.isDefEq errorType (mkConst ``String ) do
            throwErrorAt stx "#page computation requires Except String as its error type"
          pure (output, "except")
      | output => pure (output, "pure")
    discard <| Meta.synthInstance (← Meta.mkAppM ``FromJson #[input])
    discard <| Meta.synthInstance (← Meta.mkAppM ``ToJson #[output])
    return { input, output, errorMode }

private def wrapperName (declaration : Name) : Name :=
  declaration.getPrefix ++ Name.str .anonymous s!"__proofScript_{declaration.getString!}"

private def addWrapper (declaration : Name) (shape : FunctionShape)
    : CommandElabM Name := do
  let name := wrapperName declaration
  let functionIdent := mkIdent declaration
  let term ← if shape.errorMode == "except" then
    `(fun input : String =>
        Computation.invokeJson $functionIdent input)
  else
    `(fun input : String =>
        Computation.invokeJson
          (fun request => Except.ok ($functionIdent request)) input)
  let wrapperType := .forallE `input (mkConst ``String) (mkConst ``String) .default
  let value ← liftTermElabM do
    let value ← Lean.Elab.Term.elabTerm term (some wrapperType)
    Lean.Elab.Term.synthesizeSyntheticMVarsNoPostponing
    instantiateMVars value
  let env ← getEnv
  if env.contains name then
    let existing := env.constants.find! name
    let existingValue ← match existing with
      | .defnInfo info => pure info.value
      | .opaqueInfo info => pure info.value
      | _ => throwError s!"generated computation wrapper name '{name}' is already used"
    let compatible ← liftTermElabM do
      Meta.isDefEq existing.type wrapperType <&&> Meta.isDefEq existingValue value
    unless compatible do
      throwError s!"generated computation wrapper name '{name}' collides with an existing declaration"
  else
    liftCoreM <| addAndCompile <| .defnDecl {
      name
      levelParams := []
      type := wrapperType
      value
      hints := .opaque
      safety := .safe
    }
  return name

private def parseJsonAt (stx : Syntax) (source : String) : CommandElabM Json :=
  match Json.parse source with
  | .ok value => pure value
  | .error message => throwErrorAt stx s!"invalid #page computation payload JSON: {message}"

private def resolveDeclaration (stx : Syntax) (name : Name) : CommandElabM Name := do
  let env ← getEnv
  let candidates := ((← getCurrNamespace) ++ name) :: (← getOpenDecls).filterMap fun
    | .simple ns _ => some (ns ++ name)
    | .explicit ns alias => if alias == name then some ns else none
  let candidates := candidates ++ [name]
  let some resolved := candidates.find? env.contains
    | throwErrorAt stx s!"unknown Lean declaration '{name}'"
  return resolved

private def addComputationComponent (metadataStx : Syntax)
                                    (rendererStx : TSyntax `str)
                                    (functionStx : TSyntax `ident)
                                    (payloadStx : TSyntax `str)
                                    : CommandElabM Unit := do
  let metadata ←  match parseComponentMetadata metadataStx with
                  | .ok metadata => pure metadata
                  | .error message => throwErrorAt metadataStx message
  let declaration ← resolveDeclaration functionStx.raw functionStx.getId
  Elab.addConstInfo functionStx.raw declaration
  let env ← getEnv
  let info := env.constants.find! declaration
  let implementation ← match info with
    | .defnInfo value => pure value.value
    | .opaqueInfo value => pure value.value
    | _ => throwErrorAt functionStx s!"#page computation requires a definition with an implementation; '{declaration}' is not executable"
  let type ← liftTermElabM do
    return toString (← Meta.ppExpr info.type)
  let recorded ← liftTermElabM do
    let action := recordComputationFunction declaration type implementation (some functionStx.raw)
    (action { elaborator := .anonymous }).run' { goals := [] }
  let payload ← parseJsonAt payloadStx.raw payloadStx.getString
  let shape ← functionShape functionStx.raw info
  let wrapper ← addWrapper declaration shape
  let moduleName ← getMainModule
  let bundleId := moduleName.toString
  let location ← liftCoreM <| sourceLocation functionStx.raw
  let inputType ← liftTermElabM <| toString <$> Meta.ppExpr shape.input
  let outputType ← liftTermElabM <| toString <$> Meta.ppExpr shape.output
  let pending : Computation.PendingEntry := {
    bundleId
    entry := declaration.toString
    wrapper := wrapper.toString
    module := moduleName.toString
    functionType := { input := inputType, output := outputType, errorMode := shape.errorMode }
    source := location
  }
  let manifest ← liftIO <| Computation.writePendingEntry pending
  let labels := match metadata.label with
    | some label => #[(("figure" : ReferenceKind), label)]
    | none => #[]
  let value : ComputationComponent := {
    metadata
    renderer := rendererStx.getString
    function := { recording := recorded }
    execution := {
      bundleId
      entry := declaration.toString
      wrapper := wrapper.toString
      manifest := manifest.toString
    }
    payload
  }
  let encoded ← ofExcept <| value.encode
  addPageComponent functionStx.raw "computation" encoded labels

/--
Adds an interactive computation backed by a Lean declaration.

The final JSON string is a renderer-specific, versioned manifest. Keeping execution
behind a named renderer avoids treating Lean compiler internals as a stable web ABI.
-/
syntax computationFieldValue := componentMeta <|> str <|> ident
syntax computationField := ident " := " computationFieldValue

private def annotateComputationFields (fields : Array (TSyntax ``computationField))
    : CommandElabM Unit := do
  for field in fields do
    match field with
    | `(computationField| $key:ident := $value:computationFieldValue) =>
        match key.getId with
        | `metadata =>
            Elab.addConstInfo key.raw ``ComputationComponent.metadata
            if let `(computationFieldValue| $metadata:componentMeta) := value then
              addComponentMetadataInfo metadata.raw
        | `renderer => Elab.addConstInfo key.raw ``ComputationComponent.renderer
        | `function => Elab.addConstInfo key.raw ``ComputationComponent.function
        | `payload => Elab.addConstInfo key.raw ``ComputationComponent.payload
        | _ => pure ()
    | _ => pure ()

private def annotateComputationFunction (fields : Array (TSyntax ``computationField))
    : CommandElabM Unit := do
  -- Skipped page payloads remain unchecked, while existing function names
  -- still participate in editor navigation and reference highlighting.
  for field in fields do
    match field with
    | `(computationField| $key:ident := $value:computationFieldValue) =>
        if key.getId == `function then
          if let `(computationFieldValue| $functionStx:ident) := value then
            try
              let declaration ← resolveDeclaration functionStx.raw functionStx.getId
              Elab.addConstInfo functionStx.raw declaration
            catch error =>
              if error.isInterrupt || error.isMaxHeartbeat || error.isMaxRecDepth then
                throw error
    | _ => pure ()

private def parseComputationFields (fields : Array (TSyntax ``computationField)) :
    CommandElabM (Syntax × TSyntax `str × TSyntax `ident × TSyntax `str) := do
  let mut metadata : Option Syntax := none
  let mut renderer : Option (TSyntax `str) := none
  let mut function : Option (TSyntax `ident) := none
  let mut payload : Option (TSyntax `str) := none
  let mut assigned : List String := []
  for field in fields do
    match field with
    | `(computationField| $key:ident := $value:computationFieldValue) =>
        let name := key.getId.toString
        unless ["metadata", "renderer", "function", "payload"].contains name do
          throwErrorAt key m!"unknown #page computation field `{name}`"
        if assigned.contains name then
          throwErrorAt key m!"duplicate #page computation field `{name}`"
        assigned := name :: assigned
        if name == "metadata" then
          match value with
          | `(computationFieldValue| $item:componentMeta) => metadata := some item.raw
          | _ => throwErrorAt value "invalid value for #page computation field `metadata`"
        else if name == "function" then
          match value with
          | `(computationFieldValue| $item:ident) => function := some item
          | _ => throwErrorAt value "invalid value for #page computation field `function`"
        else
          match value with
          | `(computationFieldValue| $item:str) =>
              if name == "renderer" then renderer := some item else payload := some item
          | _ => throwErrorAt value m!"invalid value for #page computation field `{name}`"
    | _ => throwErrorAt field "invalid #page computation field"
  let some metadataStx := metadata | throwError "#page computation requires metadata"
  let some rendererStx := renderer | throwError "#page computation requires renderer"
  let some functionStx := function | throwError "#page computation requires function"
  let some payloadStx := payload | throwError "#page computation requires payload"
  return (metadataStx, rendererStx, functionStx, payloadStx)

page_component "computation" "{" fields:computationField,* "}" => do
  annotateComputationFields fields
  unless ← pageBuildEnabled do
    annotateComputationFunction fields
    return
  let (metadataStx, rendererStx, functionStx, payloadStx) ← parseComputationFields fields
  when_page_build
    addComputationComponent metadataStx rendererStx functionStx payloadStx


end ProofScript
