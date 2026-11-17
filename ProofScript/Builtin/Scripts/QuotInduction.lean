import ProofScript.Script.Command
import ProofScript.Info.Script.Commands


#guard_msgs (drop info) in
#check Quot.inductionOn
script_macro «quotInduction»
"quot_induction " q:term "with" a:ident => `(tactic|
  refine Quot.inductionOn $q (fun $a => ?_)
)

script_recorder «quotInduction» auto (intro := [a])

script_info «quotInduction» {
  templates := [{
    lang := zh, tag := "商归纳",
    content := ""
  }, {
    lang := en, tag := "quot-induct",
    content := ""
  }]
}
