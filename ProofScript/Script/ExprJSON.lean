import Lean.Meta
import ProofScript.Script.Core

open Lean (MetaM Level Literal Expr BinderInfo MData Json Syntax)
open Lean
open Lean.Meta (inferType)
open Lean.JsonNumber (fromNat)


namespace ProofScript

structure ExprJsonConfig where
  withTypes       : Bool  := true
  withMData       : Bool  := false
  withFVarDetails : Bool  := true
  withSourceRanges : Bool := true
  deriving Inhabited, Repr

structure ExprJsonState where
  nodes : Array Json := #[]
  fullCache : Std.HashMap Expr String := {}
  compactCache : Std.HashMap Expr String := {}
deriving Inhabited

/- Each export has its own non-persistent, backtrackable expression table. -/
initialize exprJsonExportExt : EnvExtension (Option ExprJsonState) ←
  registerEnvExtension (pure none)

def withExprJsonExport {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadFinally m] (action : m α) : m α := do
  let previous := exprJsonExportExt.getState (← getEnv)
  modifyEnv (exprJsonExportExt.setState · (some {}))
  try
    action
  finally
    modifyEnv (exprJsonExportExt.setState · previous)

private def getExprJsonState {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] : m ExprJsonState := do
  match exprJsonExportExt.getState (← getEnv) with
  | some state => return state
  | none => liftM (throw (IO.userError "ProofScript: no active expression export") : IO ExprJsonState)

private def modifyExprJsonState {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] (f : ExprJsonState → ExprJsonState) : m Unit := do
  let state ← getExprJsonState
  modifyEnv (exprJsonExportExt.setState · (some (f state)))

def getExprJsonTable {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] : m Json := do
  let state ← getExprJsonState
  return Json.mkObj <| state.nodes.toList.mapIdx fun index node => (s!"e{index}", node)

/-- Rebase all expression references, including those nested inside exported nodes. -/
private partial def rebaseExprRefs (value : Json) (offset : Nat) : Json :=
  match value with
  | .arr values => .arr (values.map (rebaseExprRefs · offset))
  | .obj fields => .mkObj <| fields.toList.map fun (key, value) =>
      if key == "$ref" then
        match value with
        | .str id =>
          match (id.drop 1).toString.toNat? with
          | some n => (key, Json.str s!"e{offset + n}")
          | none => (key, value)
        | _ => (key, value)
      else (key, rebaseExprRefs value offset)
  | other => other

/-- Import an isolated expression export into the active proof's expression table. -/
def mergeExprJsonSnapshot {m : Type → Type} [Monad m] [MonadEnv m]
    [MonadLiftT IO m] (root table : Json) : m Json := do
  let state ← getExprJsonState
  let .ok entries := table.getObj?
    | liftM (throw (IO.userError "invalid expression snapshot table") : IO Json)
  let offset := state.nodes.size
  let mut nodes := state.nodes
  for index in [:entries.size] do
    let node ← match table.getObjVal? s!"e{index}" with
      | .ok node => pure node
      | .error _ => liftM (throw (IO.userError "incomplete expression snapshot table") : IO Json)
    nodes := nodes.push (rebaseExprRefs node offset)
  modifyExprJsonState fun state => { state with nodes }
  return rebaseExprRefs root offset

private def exprRef (id : String) : Json :=
  Json.mkObj [("$ref", Json.str id)]

/-- `Nat` → `JSON` number -/
private def natJson (num : Nat) : Json :=
  Json.num (fromNat num)

/-- `BinderInfo` → `String` -/
private def binderInfoToString : BinderInfo → String
| .default        => "default"
| .implicit       => "implicit"
| .strictImplicit => "strictImplicit"
| .instImplicit   => "instImplicit"

/-- 把「可能抛异常的 `MetaM`」包装成 `Option`
    用于 `typeOf` 推断、`mvar.getDecl` 等可能失败的操作：失败时返回 `none` -/
private def trySome {α : Type} (m : MetaM α) : MetaM (Option α) :=
  tryCatch (some <$> m) (fun _ => pure none)

/-- `Level` → `JSON` object
    - `zero`  → `Type 0` 's level
    - `succ`  → the successive level
    - `max`   → 取大（`max u v` = 两者较大者，用于归纳类型宇宙）
    - `imax`  → 弱取大（`imax u v`，当 `v = 0` 时结果为 0，用于 `Prop` 消去）
    - `param` → parameter level (in polymorphic definition)
    - `mvar`  → meta level (to be solved) -/
private def levelToJson : Level → Json
| .zero =>
  Json.mkObj [("kind", Json.str "level.zero")]
| .succ u =>
  Json.mkObj [("kind", Json.str "level.succ"),
              ("level", levelToJson u)]
| .max u v =>
  Json.mkObj [("kind", Json.str "level.max"),
              ("u", levelToJson u),
              ("u", levelToJson v)]
| .imax u v =>
  Json.mkObj [("kind", Json.str "level.imax"),
              ("v", levelToJson u),
              ("v", levelToJson v)]
| .param name =>
  Json.mkObj [("kind", Json.str "level.param"),
              ("name", Json.str name.toString)]
| .mvar lmvarId =>
  Json.mkObj [("kind", Json.str "level.mvar"),
              ("id", Json.str lmvarId.name.toString)]

/-- `Literal` → `JSON` object
    - `natVal` → natural numeric literal
    - `strVal` → string literal -/
private def litToJson : Literal → Json
| .natVal n =>
  Json.mkObj [("kind", Json.str "literal.nat"),
              ("value", natJson n)]
| .strVal s =>
  Json.mkObj [("kind", Json.str "literal.str"),
              ("value", Json.str s)]

/-- `MData` → `JSON` object
    `MData = KVMap`，`m.entries` 是 `(Name, DataValue)` 键值对列表
    键取 `Name.toString`，值用 `reprStr` 兜底 -/
private def mdataToJson (data : MData) :=
  Json.mkObj <| data.entries.map fun (name, val) =>
    (name.toString, Json.str (reprStr val))

private def sourceRangeFromMData (data : MData) : Option Syntax.Range :=
  data.entries.findSome? fun (_, value) =>
    match value with
    | .ofSyntax stx => stx.getRange?
    | _ => none

private def binderInfoJson (binderInfo? : Option BinderInfo) : Json :=
  match binderInfo? with
  | some binderInfo => Json.str (binderInfoToString binderInfo)
  | none => Json.null

private def binderIsExplicitJson (binderInfo? : Option BinderInfo) : Json :=
  match binderInfo? with
  | some .default => Json.bool true
  | some _ => Json.bool false
  | none => Json.null

private def binderIsTypeclassJson (binderInfo? : Option BinderInfo) : Json :=
  match binderInfo? with
  | some .instImplicit => Json.bool true
  | some _ => Json.bool false
  | none => Json.null

private def applicationBinderInfos (expr : Expr) : MetaM (Array (Option BinderInfo)) := do
  let args := expr.getAppArgs
  let mut result := #[]
  let mut type? : Option Expr ← match expr.getAppFn.const? with
    | some (name, levels) =>
        match (← Lean.getEnv).find? name with
        | some info => pure <| some (info.type.instantiateLevelParams info.levelParams levels)
        | none => pure none
    | none => pure none
  for arg in args do
    match type? with
    | some type =>
        -- Instantiating a dependent binder with a raw bvar can leave an open
        -- type. Meta reduction is only defined for locally closed expressions.
        match (← if type.hasLooseBVars then pure none else trySome (Lean.Meta.whnf type)) with
        | some (.forallE _ _ body binderInfo) =>
            result := result.push (some binderInfo)
            type? := some (body.instantiate1 arg)
        | _ =>
            result := result.push none
            type? := none
    | none => result := result.push none
  return result

mutual

/-- 统一递归入口：为每一个 Expr 节点追加通用语义字段。 -/
private partial def serializeNode (expr : Expr)
                                  (cfg : ExprJsonConfig)
                                  (sourceRange? : Option Syntax.Range := none)
                                   : MetaM Json := do
  let expr ← Lean.instantiateMVars expr
  let cacheable := sourceRange?.isNone && !cfg.withMData && cfg.withFVarDetails && cfg.withSourceRanges
  if cacheable then
    let state ← getExprJsonState
    let cache := if cfg.withTypes then state.fullCache else state.compactCache
    if let some id := cache.get? expr then
      return exprRef id
  let state ← getExprJsonState
  let index := state.nodes.size
  let id := s!"e{index}"
  let state := { state with nodes := state.nodes.push Json.null }
  let state := if cacheable then
      if cfg.withTypes then { state with fullCache := state.fullCache.insert expr id }
      else { state with compactCache := state.compactCache.insert expr id }
    else state
  modifyExprJsonState fun _ => state
  let body ← serializeCore expr cfg sourceRange?
  let body ← match body with
    | Json.obj fields =>
        -- Binder bodies are exported structurally, retaining de Bruijn indices.
        -- They are not standalone terms; catching exceptions does not catch a
        -- Lean panic caused by passing them to type inference/reduction.
        let isProp ← if expr.hasLooseBVars then pure none else trySome (Lean.Meta.isProp expr)
        let fields := fields.insert "isProp" (Json.bool (isProp.getD false))
        let fields ← if cfg.withTypes && !expr.isFVar && !expr.hasLooseBVars then
          match (← trySome (inferType expr)) with
          | some type =>
              let type ← Lean.instantiateMVars type
              let typeJson ← serializeNode type { cfg with withTypes := false } none
              pure <| fields.insert "typeOf" typeJson
          | none => pure fields
        else pure fields
        let fields ← if cfg.withSourceRanges then
          match sourceRange? with
          | some range =>
              let sourceRange := Json.mkObj [
                ("file", Json.str (← Lean.getFileName)),
                ("start", natJson range.start.byteIdx),
                ("stop", natJson range.stop.byteIdx)
              ]
              pure <| fields.insert "sourceRange" sourceRange
          | none => pure fields
        else pure fields
        pure (Json.obj fields)
    | other => pure other
  modifyExprJsonState fun state => { state with nodes := state.nodes.set! index body }
  return exprRef id

/-- 对 `Expr` 的构造子逐一序列化主体字段。 -/
private partial def serializeCore (expr : Expr)
                                   (cfg : ExprJsonConfig)
                                   (sourceRange? : Option Syntax.Range)
                                   : MetaM Json := do
  match expr with
  | .bvar deBruijnIndex =>
    let data := [("kind", Json.str "bvar"),
                 ("index", natJson deBruijnIndex)]
    return Json.mkObj data
  | .fvar fvarId => do
    let decl ← fvarId.getDecl
    let typeJson ← serializeNode decl.type cfg
    let mut data := [("kind", Json.str "fvar"),
                     ("name", Json.str decl.userName.toString),
                     ("id", Json.str fvarId.name.toString),
                     ("type", typeJson)]
    if cfg.withFVarDetails then
      data := data ++ [("index", natJson decl.index),
                       ("binderInfo", Json.str (binderInfoToString decl.binderInfo))]
    if let some v := decl.value? then
      data := data ++ [("value", ← serializeNode v cfg)]
    return Json.mkObj data
  | .mvar mvarId => do
    let mut data := [("kind", Json.str "mvar"),
                     ("id", Json.str mvarId.name.toString)]
    match (← trySome mvarId.getDecl) with
    | some d =>
      data := data ++ [("name", Json.str d.userName.toString),
                        ("type", ← serializeNode d.type cfg)]
    | none => pure ()
    return Json.mkObj data
  | .sort u =>
    let data := [("kind", Json.str "sort"),
                 ("level", levelToJson u)]
    return Json.mkObj data
  | .const declName us =>
    let data := [("kind", Json.str "const"),
                 ("name", Json.str declName.toString),
                 ("levels", Json.arr (us.map levelToJson).toArray)]
    return Json.mkObj data
  | .app fn arg =>
    let args := expr.getAppArgs
    let binderInfos ← applicationBinderInfos expr
    let arguments ← args.mapIdxM fun index argument => do
      let binderInfo? := binderInfos[index]!
      pure <| Json.mkObj [
        ("expr", ← serializeNode argument cfg),
        ("binderInfo", binderInfoJson binderInfo?),
        ("isExplicit", binderIsExplicitJson binderInfo?),
        ("isTypeclass", binderIsTypeclassJson binderInfo?)
      ]
    let headConstant := match expr.getAppFn.const? with
      | some (name, _) => Json.str name.toString
      | none => Json.null
    let data := [("kind", Json.str "app"),
                 ("fn", ← serializeNode fn cfg),
                 ("arg", ← serializeNode arg cfg),
                 ("headConstant", headConstant),
                 ("arguments", Json.arr arguments)]
    return Json.mkObj data
  | .lam binderName binderType body binderInfo =>
    let data := [("kind", Json.str "lam"),
                 ("name", Json.str binderName.toString),
                  ("type", ← serializeNode binderType cfg),
                  ("body", ← serializeNode body cfg),
                 ("binderInfo", Json.str (binderInfoToString binderInfo))]
    return Json.mkObj data
  | .forallE binderName binderType body binderInfo =>
    let data := [("kind", Json.str "forall"),
                 ("name", Json.str binderName.toString),
                  ("type", ← serializeNode binderType cfg),
                  ("body", ← serializeNode body cfg),
                 ("binderInfo", Json.str (binderInfoToString binderInfo))]
    return Json.mkObj data
  | .letE declName type value body nondep =>
    let data := [("kind", Json.str "let"),
                 ("name", Json.str declName.toString),
                  ("type", ← serializeNode type cfg),
                  ("value", ← serializeNode value cfg),
                  ("body", ← serializeNode body cfg),
                 ("nondep", Json.bool nondep)]
    return Json.mkObj data
  | .lit lit =>
    let data := [("kind", Json.str "lit"),
                 ("lit", litToJson lit)]
    return Json.mkObj data
  | .mdata data expr =>
      let range? := sourceRangeFromMData data <|> sourceRange?
      let data := data.erase witnessDataGoalMDataKey
      if data.isEmpty then
        serializeCore expr cfg range?
      else if cfg.withMData then
        let data := [("kind", Json.str "mdata"),
                     ("data", mdataToJson data),
                     ("expr", ← serializeNode expr cfg range?)]
        return Json.mkObj data
      else
        serializeCore expr cfg range?
  | .proj typeName idx struct =>
    let data := [("kind", Json.str "proj"),
                 ("structName", Json.str typeName.getPrefix.toString),
                 ("index", natJson idx),
                 ("fieldName", Json.str typeName.toString),
                  ("expr", ← serializeNode struct cfg)]
    return Json.mkObj data

end

/-- 核心：把任意 Lean 项序列化为结构保持的 JSON 对象。
    1. `serializeCore` 逐构造子序列化出主体 JSON
    2. 若 `withTypes=true` 且当前节点不是 `fvar`（fvar 的 `type` 字段已是其声明类型，
       等价于推断类型，无需重复），调用 `inferType` 推断该节点的类型
    3. 推断成功则把类型（以 `withTypes := false` 序列化，避免无限递归膨胀）作为
       `typeOf` 字段插入主体；推断失败（如孤立 `bvar`）则跳过 -/
def Expr2JSON (expr : Expr)
              (cfg : ExprJsonConfig := {})
              : MetaM Json := do
  -- 统一入口先 instantiateMVars：把已实例化的元变量替换为具体值，避免序列化出
  -- `mvar` 节点（否则渲染端会出现 `[mvar]` 占位符）。未实例化的 mvar 仍保留。
  serializeNode expr cfg

end ProofScript
