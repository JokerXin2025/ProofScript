import ProofScript.Script.Basic
import ProofScript.Info.Commands

/-! Default presentation for the stable registrations in Script.Basic. -/

script_info ProofScript.Script.Basic.«assumption» {
  template := [{
    lang := "zh", tag := "«assumption»",
    content := ""
  }, {
    lang := "en", tag := "«assumption»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«change» {
  template := [{
    lang := "zh", tag := "改写目标",
    content := "待证目标即 ${equation_before}"
  }, {
    lang := "en", tag := "«change»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«contradiction» {
  template := [{
    lang := "zh", tag := "«contradiction»",
    content := ""
  }, {
    lang := "en", tag := "«contradiction»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«exfalso» {
  template := [{
    lang := "zh", tag := "«exfalso»",
    content := ""
  }, {
    lang := "en", tag := "«exfalso»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«omega» {
  template := [{
    lang := "zh", tag := "整数算术",
    content := ""
  }, {
    lang := "en", tag := "«omega»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«rfl» {
  template := [{
    lang := "zh", tag := "自反性",
    content := ""
  }, {
    lang := "en", tag := "«rfl»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«symm» {
  template := [{
    lang := "zh", tag := "对称性",
    content := ""
  }, {
    lang := "en", tag := "«symm»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«trivial» {
  template := [{
    lang := "zh", tag := "显然",
    content := ""
  }, {
    lang := "en", tag := "«trivial»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«simp» {
  template := [{
    lang := "zh", tag := "化简",
    content := ""
  }, {
    lang := "en", tag := "«simp»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«rw» {
  template := [{
    lang := "zh", tag := "代换",
    content := ""
  }, {
    lang := "en", tag := "«rw»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«unfold» {
  template := [{
    lang := "zh", tag := "展开定义",
    content := ""
  }, {
    lang := "en", tag := "«unfold»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«have» {
  template := [{
    lang := "zh", tag := "引入事实",
    content := "${h}"
  }, {
    lang := "en", tag := "«have»",
    content := "${h}"
  }]
}

script_info ProofScript.Script.Basic.«exact» {
  template := [{
    lang := "zh", tag := "«exact»",
    content := ""
  }, {
    lang := "en", tag := "«exact»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«exact_proj» {
  template := [{
    lang := "zh", tag := "投影",
    content := "待证目标蕴涵于已知条件“${value_before}”之中"
  }, {
    lang := "en", tag := "«exact_proj»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«intro» {
  template := [{
    lang := "zh", tag := "«intro»",
    content := ""
  }, {
    lang := "en", tag := "«intro»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«left» {
  template := [{
    lang := "zh", tag := "确定目标",
    content := ""
  }, {
    lang := "en", tag := "«left»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«right» {
  template := [{
    lang := "zh", tag := "确定目标",
    content := ""
  }, {
    lang := "en", tag := "«right»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«unpack_and» {
  template := [{
    lang := "zh", tag := "拆分合取",
    content := ""
  }, {
    lang := "en", tag := "«unpack_and»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«unpack_iff» {
  template := [{
    lang := "zh", tag := "拆分等价",
    content := ""
  }, {
    lang := "en", tag := "«unpack_iff»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«obtain_exist» {
  template := [{
    lang := "zh", tag := "解构存在性",
    content := ""
  }, {
    lang := "en", tag := "«obtain_exist»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«obtain_exist'» {
  template := [{
    lang := "zh", tag := "解构存在性",
    content := ""
  }, {
    lang := "en", tag := "«obtain_exist'»",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«funext» {
  template := [{
    lang := "zh", tag := "函数外延性",
    content := ""
  }, {
    lang := "en", tag := "By function extensionality,",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«provide» {
  template := [{
    lang := "zh", tag := "选取",
    content := "${data_before}"
  }, {
    lang := "en", tag := "«provide»",
    content := "${data_before}"
  }]
}

script_info ProofScript.Script.Basic.«apply» {
  template := [{
    lang := "zh", tag := "应用定理",
    content := "${h}"
  }, {
    lang := "en", tag := "Applying the theorem,",
    content := "${h}"
  }]
}

script_info ProofScript.Script.Basic.«quot_induction» {
  template := [{
    lang := "zh", tag := "商归纳",
    content := ""
  }, {
    lang := "en", tag := "By quotient induction,",
    content := ""
  }]
}

script_info ProofScript.Script.Basic.«claim» {
  template := [{
    lang := "zh", tag := "先证明断言",
    cases := [{name := "proof", tag := "证明", title := ""}]
  }, {
    lang := "en", tag := "Proving an intermediate claim,",
    cases := [{name := "proof", tag := "Proof", title := ""}]
  }]
}

script_info ProofScript.Script.Basic.«claimExistTwo» {
  template := [{
    lang := "zh", tag := "先证明存在性断言",
    cases := [{name := "proof", tag := "证明", title := ""}]
  }, {
    lang := "en", tag := "Proving an existential claim,",
    cases := [{name := "proof", tag := "Proof", title := ""}]
  }]
}

script_info ProofScript.Script.Basic.«claimExistThree» {
  template := [{
    lang := "zh", tag := "先证明存在性断言",
    cases := [{name := "proof", tag := "证明", title := ""}]
  }, {
    lang := "en", tag := "Proving an existential claim,",
    cases := [{name := "proof", tag := "Proof", title := ""}]
  }]
}

script_info ProofScript.Script.Basic.«witness» {
  color := (some "#166a80", some "#9ac7d0", some "#eff8fa"),
  template := [{
    lang := "zh", tag := "构造性证明",
    introducer := {tag := "目标拆解", content := "将目标拆分为数据构造和性质证明两个子目标"},
    cases := [
      {name := "data", tag := "子目标 I", title := ""},
      {name := "proof", tag := "子目标 II", title := ""}
    ]
  }, {
    lang := "en", tag := "As a constructive proof,",
    introducer := {tag := "To construct the proof,", content := "split the goal into data construction and proof subgoals"},
    cases := [
      {name := "data", tag := "Subgoal I,", title := ""},
      {name := "proof", tag := "Subgoal II,", title := ""}
    ]
  }]
}

script_info ProofScript.Script.Basic.«split_and» {
  template := [{
    lang := "zh", tag := "拆分合取",
    introducer := {tag := "目标拆解", content := "将目标拆分为子目标逐一证明"},
    cases := [
      {name := "left", tag := "子目标 I", title := ""},
      {name := "right", tag := "子目标 II", title := ""}
    ]
  }, {
    lang := "en", tag := "To split the conjunction,",
    introducer := {tag := "To decompose the goal,", content := "decompose the goal into subgoals and prove them one by one"},
    cases := [
      {name := "left", tag := "Subgoal I,", title := ""},
      {name := "right", tag := "Subgoal II,", title := ""}
    ]
  }]
}

script_info ProofScript.Script.Basic.«split_and!» {
  renderer := «strategy»
}

script_info ProofScript.Script.Basic.«split_iff» {
  template := [{
    lang := "zh", tag := "拆分充分必要",
    introducer := {tag := "目标拆解", content := "将目标拆分为充分性和必要性两个子目标"},
    cases := [
      {name := "suffice", tag := "子目标 I", title := ""},
      {name := "necess", tag := "子目标 II", title := ""}
    ]
  }, {
    lang := "en", tag := "To split the equivalence,",
    introducer := {tag := "To decompose the goal,", content := "split the equivalence into sufficiency and necessity"},
    cases := [
      {name := "suffice", tag := "Subgoal I,", title := ""},
      {name := "necess", tag := "Subgoal II,", title := ""}
    ]
  }]
}

script_info ProofScript.Script.Basic.«cases_by» {
  template := [{
    lang := "zh", tag := "分类讨论",
    introducer := {tag := "分类依据", content := "对命题 ${subject} 的不同情形分别讨论"},
    cases := [
      {name := "left", tag := "情形 I", title := ""},
      {name := "right", tag := "情形 II", title := ""}
    ]
  }, {
    lang := "en", tag := "By cases,",
    introducer := {tag := "As the case distinction,", content := "consider the possible cases of ${subject}"},
    cases := [
      {name := "left", tag := "In Case I,", title := ""},
      {name := "right", tag := "In Case II,", title := ""}
    ]
  }]
}

script_info ProofScript.Script.Basic.«cases_by!» {
  renderer := «strategy»
}

script_info ProofScript.Script.Basic.«cases_on» {
  renderer := «strategy»
}

script_info ProofScript.Script.Basic.«contra» {
  color := (some "#a33b45", some "#ddb0b4", some "#fcf2f2"),
  template := [{
    lang := "zh", tag := "反证法",
    inline := true,
    introducer := {tag := "假设", content := "假设 ${hypothesis}，推得矛盾"},
    cases := [{name := "proof", tag := "", title := ""}]
  }, {
    lang := "en", tag := "By contradiction,",
    inline := true,
    introducer := {tag := "For the contrary assumption,", content := "suppose ${hypothesis} and derive a contradiction."},
    cases := [{name := "proof", tag := "", title := ""}]
  }]
}

script_info ProofScript.Script.Basic.«induction» {
  color := (some "#2b6a4a", some "#a3c2b1", some "#f2f7f4"),
  template := [{
    lang := "zh", tag := "数学归纳法",
    introducer := {tag := "归纳对象", content := "对变量 ${n} 使用数学归纳法"},
    cases := [
      {name := "zero", tag := "基础情形", title := "验证命题对 $0$ 成立"},
      {name := "succ", tag := "归纳步骤", title := "假设命题对 $k$ 成立，下面证明命题对 $k+1$ 成立"}
    ]
  }, {
    lang := "en", tag := "By induction,",
    introducer := {tag := "On the induction variable,", content := "on the natural number ${n}, apply mathematical induction."},
    cases := [
      {name := "zero", tag := "In the base case,", title := "verify that the proposition holds for $0$"},
      {name := "succ", tag := "In the inductive step,", title := "suppose the proposition holds for $k$, then prove it for $k+1$"}
    ]
  }]
}

script_info ProofScript.Script.Basic.«complete_induction» {
  color := (some "#61519a", some "#bdb3d8", some "#f6f3fa"),
  template := [{
    lang := "zh", tag := "强数学归纳法",
    introducer := {tag := "归纳对象", content := "对自然数 ${n} 使用强数学归纳法。"},
    cases := [
      {name := "zero", tag := "基础情形", title := "验证命题对 $0$ 成立"},
      {name := "succ", tag := "归纳步骤", title := "假设命题对所有小于 $k+1$ 的自然数成立，证明 $k+1$ 的情形"}
    ]
  }, {
    lang := "en", tag := "By strong induction,",
    introducer := {tag := "On the induction variable,", content := "on the natural number ${n}, apply strong induction."},
    cases := [
      {name := "zero", tag := "In the base case,", title := "verify the proposition for $0$"},
      {name := "succ", tag := "In the inductive step,", title := "suppose the proposition holds for all smaller numbers, then prove it for $k+1$"}
    ]
  }]
}

script_info ProofScript.Script.Basic.«constructor» {
  renderer := «strategy»,
  color := (some "#a26423", some "#dfc39d", some "#fdf8ee")
}

script_info ProofScript.Script.Basic.«constructor!» {
  renderer := «strategy»,
  color := (some "#a26423", some "#dfc39d", some "#fdf8ee")
}

script_info ProofScript.Script.Basic.«remark» {
  renderer := «remark»
}

script_info ProofScript.Script.Basic.«svg» {
  renderer := «diagram»
}

script_info ProofScript.Script.Basic.«latex» {
  renderer := «media»
}

script_info ProofScript.Script.Basic.«admit» {
  renderer := «admit»
}

script_info ProofScript.Script.Basic.«cite» {
  template := [{
    lang := "zh", tag := "引用定理",
    content := "${theorem}"
  }, {
    lang := "en", tag := "Citing the theorem,",
    content := "${theorem}"
  }]
}

script_info ProofScript.Script.Basic.«renderCalc» {
  renderer := «calc»
}

script_info ProofScript.Script.Basic.«infer» {
  renderer := «infer»
}
