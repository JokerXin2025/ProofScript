import ProofScript.Script.Command
import ProofScript.Info.Commands


#guard_msgs (drop info) in
#check Quot.inductionOn
script_macro «quotInduction» (intro := [a])
"quot_induction " q:term "with" a:ident => `(tactic|
  refine Quot.inductionOn $q (fun $a => ?_)
)

script_info «quotInduction» {
  template := [{
    lang := zh, tag := "商归纳",
    content := ""
  }, {
    lang := en, tag := "quot-induct",
    content := ""
  }]
}
