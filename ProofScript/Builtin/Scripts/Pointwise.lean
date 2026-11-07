import ProofScript.Script.Command
import ProofScript.Info.Commands
import Mathlib.Algebra.Torsor.Basic
import Mathlib.Order.Lattice
import Mathlib.Data.Nat.Cast.Basic
import Mathlib.Data.Int.Cast.Pi
import Mathlib.Algebra.Order.Group.Unbundled.Abs

open Lean.Parser.Tactic (location)


#guard_msgs (drop info) in
#check Pi.zero_apply
#guard_msgs (drop info) in
#check Pi.one_apply
#guard_msgs (drop info) in
#check Pi.smul_apply
#guard_msgs (drop info) in
#check Pi.smul_apply'
#guard_msgs (drop info) in
#check Pi.add_apply
#guard_msgs (drop info) in
#check Pi.neg_apply
#guard_msgs (drop info) in
#check Pi.sub_apply
#guard_msgs (drop info) in
#check Pi.mul_apply
#guard_msgs (drop info) in
#check Pi.inv_apply
#guard_msgs (drop info) in
#check Pi.div_apply
#guard_msgs (drop info) in
#check Pi.pow_apply
#guard_msgs (drop info) in
#check Pi.star_apply
#guard_msgs (drop info) in
#check Pi.vadd_apply
#guard_msgs (drop info) in
#check Pi.vadd_apply'
#guard_msgs (drop info) in
#check Pi.vsub_apply
#guard_msgs (drop info) in
#check Pi.sdiv_apply
#guard_msgs (drop info) in
#check Pi.bot_apply
#guard_msgs (drop info) in
#check Pi.top_apply
#guard_msgs (drop info) in
#check Pi.sup_apply
#guard_msgs (drop info) in
#check Pi.inf_apply
#guard_msgs (drop info) in
#check Pi.compl_apply
#guard_msgs (drop info) in
#check Pi.sdiff_apply
#guard_msgs (drop info) in
#check Pi.natCast_apply
#guard_msgs (drop info) in
#check Pi.ofNat_apply
#guard_msgs (drop info) in
#check Pi.intCast_apply
#guard_msgs (drop info) in
#check Pi.mabs_apply
#guard_msgs (drop info) in
#check Pi.abs_apply
/-- Pointwise-expand the expression. -/
macro "pointwise" loc:(location)? : tactic => `(tactic|
  dsimp only [
    Pi.zero_apply,
    Pi.one_apply,
    Pi.smul_apply,
    Pi.smul_apply',
    Pi.add_apply,
    Pi.neg_apply,
    Pi.sub_apply,
    Pi.mul_apply,
    Pi.inv_apply,
    Pi.div_apply,
    Pi.pow_apply,
    Pi.star_apply,
    Pi.vadd_apply,
    Pi.vadd_apply',
    Pi.vsub_apply,
    Pi.sdiv_apply,
    Pi.bot_apply,
    Pi.top_apply,
    Pi.sup_apply,
    Pi.inf_apply,
    Pi.compl_apply,
    Pi.sdiff_apply,
    Pi.natCast_apply,
    Pi.ofNat_apply,
    Pi.intCast_apply,
    Pi.mabs_apply,
    Pi.abs_apply
  ] $[$loc]?
)

script_macro «pointwise» (clear := [loc])
"pointwise" loc:(location)? => `(tactic| pointwise $[$loc]?)

script_info «pointwise» {
  template := [{
    lang := zh, tag := "逐点化",
    content := ""
  }, {
    lang := en, tag := "pointwise",
    content := ""
  }]
}
