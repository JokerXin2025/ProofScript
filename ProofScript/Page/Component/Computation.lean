import ProofScript.Page.Component.Core
import Lean.Data.Json
import ProofScript.Page.Path
import ProofScript.Page.Data
import ProofScript.Script.ExprJSON

open Lean
open System
open Lean.Elab.Command (CommandElabM liftCoreM liftIO liftTermElabM)
open ProofScript


namespace ProofScript.Computation


structure ErrorBody where
  code : String
  message : String
deriving ToJson

private def success (value : Json) : Json :=
  Json.mkObj [("ok", true), ("value", value)]

private def failure (code message : String) : Json :=
  Json.mkObj [("ok", false), ("error", toJson ({ code, message } : ErrorBody))]

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
  let path ← activeOutputPath (pendingEntryPath entry.module entry.entry)
  ensureParentDir path
  IO.FS.writeFile path (toJson entry).pretty
  return path


end ProofScript.Computation


namespace ProofScript


/-- Stable description of the Lean declaration backing an interactive computation. -/
structure ComputationFunction where
  declaration : String
  type : String
  expression : Json
  implementation : Json
  expressions : Json
deriving Inhabited, ToJson

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
deriving Inhabited, ToJson

private structure FunctionShape where
  input : Expr
  output : Expr
  errorMode : String

private def functionShape (stx : Syntax) (info : ConstantInfo) : CommandElabM FunctionShape :=
  liftTermElabM do
    unless info.levelParams.isEmpty do
      throwErrorAt stx "@computation does not yet support universe-polymorphic entry functions"
    let type ← Meta.whnf info.type
    let .forallE _ input result binderInfo := type
      | throwErrorAt stx "@computation requires a function with exactly one explicit argument"
    unless binderInfo == .default do
      throwErrorAt stx "@computation requires an explicit input argument"
    if result.hasLooseBVars then
      throwErrorAt stx "@computation does not support dependent output types"
    let result ← Meta.whnf result
    match result with
    | .forallE .. =>
        throwErrorAt stx "@computation requires a function with exactly one explicit argument"
    | _ => pure ()
    let (output, errorMode) ←
      match result with
      | .app (.app (.const ``Except _) errorType) output =>
          unless ← Meta.isDefEq errorType (mkConst ``String ) do
            throwErrorAt stx "@computation requires Except String as its error type"
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
  | .error message => throwErrorAt stx s!"invalid @computation payload JSON: {message}"

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
  let env ← getEnv
  let info := env.constants.find! declaration
  let implementation ← match info with
    | .defnInfo value => pure value.value
    | .opaqueInfo value => pure value.value
    | _ => throwErrorAt functionStx s!"@computation requires a definition with an implementation; '{declaration}' is not executable"
  let (expression, implementation, expressions) ← withExprJsonExport do
    let expression ← liftTermElabM do
      Expr2JSON (mkConst declaration)
    let implementation ← liftTermElabM do
      Expr2JSON implementation
    let expressions ← getExprJsonTable
    return (expression, implementation, expressions)
  let type ← liftTermElabM do
    return toString (← Meta.ppExpr info.type)
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
    function := { declaration := declaration.toString, type, expression, implementation, expressions }
    execution := {
      bundleId
      entry := declaration.toString
      wrapper := wrapper.toString
      manifest := manifest.toString
    }
    payload
  }
  addPageComponent functionStx.raw "computation" (toJson value) labels

/--
Adds an interactive computation backed by a Lean declaration.

The final JSON string is a renderer-specific, versioned manifest. Keeping execution
behind a named renderer avoids treating Lean compiler internals as a stable web ABI.
-/
syntax computationFieldValue := componentMeta <|> str <|> ident
syntax computationField := ident " := " computationFieldValue
syntax (name := computationCmd) "@computation" "{" sepBy1(computationField, ", ") "}" : command

elab_rules : command
  | `(command| @computation { $[$fields:computationField],* }) => do
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
              throwErrorAt key m!"unknown @computation field `{name}`"
            if assigned.contains name then
              throwErrorAt key m!"duplicate @computation field `{name}`"
            assigned := name :: assigned
            if name == "metadata" then
              match value with
              | `(computationFieldValue| $item:componentMeta) => metadata := some item.raw
              | _ => throwErrorAt value "invalid value for @computation field `metadata`"
            else if name == "function" then
              match value with
              | `(computationFieldValue| $item:ident) => function := some item
              | _ => throwErrorAt value "invalid value for @computation field `function`"
            else
              match value with
              | `(computationFieldValue| $item:str) =>
                  if name == "renderer" then renderer := some item else payload := some item
              | _ => throwErrorAt value m!"invalid value for @computation field `{name}`"
        | _ => throwErrorAt field "invalid @computation field"
      let some metadataStx := metadata | throwError "@computation requires metadata"
      let some rendererStx := renderer | throwError "@computation requires renderer"
      let some functionStx := function | throwError "@computation requires function"
      let some payloadStx := payload | throwError "@computation requires payload"
      addComputationComponent metadataStx rendererStx functionStx payloadStx


end ProofScript
