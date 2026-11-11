import ProofScript

open Lean Parser Tactic Elab.Tactic Meta ProofScript

/-! A page-local simplifier recorder runs the same Lean simplifier as the macro,
    but retains its `Simp.Stats` instead of re-running the tactic for diagnostics. -/
private def simplifyForBoard (rules : TSyntax ``Parser.Tactic.simpArgs)
    (loc : Option (TSyntax ``Parser.Tactic.location)) : TacticM (Array String) := withMainContext do
  let `(simpArgs| [$items,*]) := rules | throwError "expected simplification rules"
  let stx ← `(tactic| simp only [$items,*] $[$loc:location]?)
  let r@{ ctx, simprocs, dischargeWrapper, .. } ← mkSimpContext stx.raw (eraseLocal := false)
  let stats ← dischargeWrapper.with fun discharge? =>
    withLoopChecking r do
      simpLocation ctx simprocs discharge? (expandOptLocation stx.raw[5])
  let lctx ← getLCtx
  return stats.usedTheorems.toArray.filterMap fun origin =>
    match origin with
    | .decl name _ _ => some name.toString
    | .fvar id => some (lctx.get! id).userName.toString
    | .stx _ arg => some (arg.reprint.getD (reprStr arg))
    | .other _ => none

script_macro boardSimp "board_simp" rules:simpArgs loc:(location)? =>
  match rules with
  | `(simpArgs| [$items,*]) => `(tactic| simp only [$items,*] $[$loc:location]?)
  | _ => Lean.Macro.throwUnsupported

script_recorder boardSimp => do
  record_goal "$goal_before"
  record_context "$context_before"
  record_value "requested_rules" (rules.raw.reprint.getD "" |>.trimAscii.toString)
  record_value "location" (loc.map (fun s => s.raw.reprint.getD "" |>.trimAscii.toString) |>.getD "目标")
  let start ← IO.monoNanosNow
  let used ← Lean.Elab.Tactic.withoutModifyingState' (simplifyForBoard rules loc)
  execute
  record_value "duration_ns" ((← IO.monoNanosNow) - start)
  record_value "used_lemmas" used
  record_goal "$goal_after"
  record_context "$context_after"

script_info boardSimp {
  template := [{ lang := zh, tag := "化简", content := "对 ${location} 进行化简" }],
  board := [("指定规则", "requested_rules"), ("化简位置", "location"),
    ("实际使用的引理", "used_lemmas"), ("执行耗时（纳秒）", "duration_ns")]
}

-- `only` makes the arithmetic inputs auditable; record their types before execution.
script_macro boardLinear "board_linear" "[" inputs:ident,* "]" =>
  `(tactic| linarith only [$inputs,*])

script_recorder boardLinear => do
  record_goal "$goal_before"
  record_context "$context_before"
  let goal ← getMainGoal
  let target ← goal.getType
  record_value "conclusion" target
  let mut premises : List (String × RecordedValue) := []
  for input in inputs.getElems do
    premises := premises ++ [(input.getId.toString, ← expressionType input.raw)]
  record_value "premises" (RecordedValue.object premises)
  let start ← IO.monoNanosNow
  execute
  record_value "duration_ns" ((← IO.monoNanosNow) - start)
  let proof ← instantiateMVars (mkMVar goal)
  let mut dependencies : Array String := #[]
  for id in (Lean.collectFVars {} proof).fvarIds do
    let decl ← goal.withContext id.getDecl
    if ← goal.withContext (isProp decl.type) then
      let name := decl.userName.toString
      if !dependencies.contains name then dependencies := dependencies.push name
  record_value "proof_dependencies" dependencies
  record_goal "$goal_after"
  record_context "$context_after"

script_info boardLinear {
  template := [{ lang := zh, tag := "线性推理", content := "由 ${premises}，推出 ${conclusion}" }],
  board := [("输入算术事实", "premises"), ("待证结论", "conclusion"),
    ("证明项依赖的局部命题", "proof_dependencies"), ("执行耗时（纳秒）", "duration_ns")]
}

script_recorder «norm_num» => do
  record_goal "$goal_before"
  record_context "$context_before"
  record_value "verification" (← getMainTarget)
  let start ← IO.monoNanosNow
  execute
  record_value "duration_ns" ((← IO.monoNanosNow) - start)
  record_goal "$goal_after"
  record_context "$context_after"

script_info «norm_num» {
  template := [{ lang := zh, tag := "数值验证", content := "计算并验证 ${verification}" }],
  board := [("验证的命题", "verification"), ("执行耗时（纳秒）", "duration_ns")]
}

script_recorder «unpack_and» => do
  let start ← IO.monoNanosNow
  execute
  record_value "duration_ns" ((← IO.monoNanosNow) - start)

script_info «unpack_and» { board := [("执行耗时（纳秒）", "duration_ns")] }

script_macro boardCases (kind := strategy) "board_cases" x:ident y:ident => `(tactic| focus
  by_cases hxy : $y ≤ $x
  set_goal_tags [`nonnegative, `negative])

script_recorder boardCases => do
  record_goal "$goal_before"
  record_context "$context_before"
  let start ← IO.monoNanosNow
  execute
  record_value "duration_ns" ((← IO.monoNanosNow) - start)

script_info boardCases {
  template := [{ lang := zh, tag := "绝对值分类",
    introducer := { tag := "分类", content := "按 y ≤ x 分类讨论绝对值" },
    cases := [{ name := "nonnegative", tag := "情形一", title := "y ≤ x" },
      { name := "negative", tag := "情形二", title := "x < y" }] }],
  board := [("执行耗时（纳秒）", "duration_ns")]
}

#page title "绝对值线性优化：上界与唯一最优点"

#page text "在两个线性资源约束下，求 |x − y| + x + y 的最大值。证明将绝对值按符号分类，分别展示化简器实际使用的规则、线性推理的输入及执行耗时。"

private def feasible (x y : ℝ) : Prop :=
  0 ≤ x ∧ 0 ≤ y ∧ 2 * x + y ≤ 8 ∧ x + 2 * y ≤ 7

private def objective (x y : ℝ) : ℝ := |x - y| + x + y

#page sub title "全局上界"

#page text "当 y ≤ x 时绝对值等于 x − y；当 x < y 时等于 y − x，且第二种情况有更强的上界 7。"

#page theorem board_upper_bound (x y : ℝ) (h : feasible x y) :
    objective x y ≤ 8 := script
  unpack_and ⟨hx, hy, h₁, h₂⟩ := h
  board_cases x y
  | nonnegative hxy =>
    board_simp [objective, abs_of_nonneg (sub_nonneg.mpr hxy)]
    board_linear [hy, h₁]
  | negative hxy =>
    board_simp [objective, abs_of_neg (sub_neg.mpr (lt_of_not_ge hxy))]
    board_linear [hx, h₂]

#page sub title "何时取到上界"

#page text "若达到 8，则 x < y 分支的上界 7 构成矛盾；剩余分支的约束迫使 y = 0、x = 4。"

#page theorem board_equality (x y : ℝ) (h : feasible x y) :
    objective x y = 8 ↔ x = 4 ∧ y = 0 := script
  split_iff
  | suffice heq =>
    unpack_and ⟨hx, hy, h₁, h₂⟩ := h
    board_cases x y
    | nonnegative hxy =>
      board_simp [objective, abs_of_nonneg (sub_nonneg.mpr hxy)] at heq
      split_and
      | left => board_linear [heq]
      | right => board_linear [hy, h₁, heq]
    | negative hxy =>
      board_simp [objective, abs_of_neg (sub_neg.mpr (lt_of_not_ge hxy))] at heq
      board_linear [hx, h₂, heq]
  | necess heq =>
    unpack_and ⟨heqx, heqy⟩ := heq
    board_simp [objective, heqx, heqy]
    norm_num

#page sub title "最优点的数值验证"

#page text "最后代入 (4, 0)，用数值归一化逐一验证可行条件与目标值，从而确认上界可以达到。"

#page theorem board_optimum : feasible 4 0 ∧ objective 4 0 = 8 := script
  norm_num [feasible, objective]
