import ProofScript.Script.Command
import ProofScript.Info.Commands


#guard_msgs (drop info) in
#check And.intro
#guard_msgs (drop info) in
#check Lean.Name.mkSimple
#guard_msgs (drop info) in
#check Nat.toRoman

/-- Split the conjunction goal into its two subgoals `left` and `right`.

Here is an example:
```lean
example {P : Prop} : P → P ∧ P := script
  intro h
  split_and
  | left => exact h
  | right => exact h
```
-/
script_macro «splitAnd» (kind := strategy)
"split_and" => `(tactic| focus
  first
  | guard_target =~ (_ ∧ _)
  | fail "`split_and` can only be used with `∧` propositions"
  apply And.intro
  set_goal_tags [`left, `right]
)

script_info «splitAnd» {
  template := [{
    lang := zh, tag := "目标拆解",
    introducer := {tag := "拆解", content := "先证明 L , 再证明 R"},
    cases := [
      {name := "left", tag := "子目标 I", title := ""},
      {name := "right", tag := "子目标 II", title := ""}
    ]
  }, {
    lang := en, tag := "Goal Decomposition",
    introducer := {tag := "decompose", content := "First prove L , then prove R"},
    cases := [
      {name := "left", tag := "Subgoal I,", title := ""},
      {name := "right", tag := "Subgoal II,", title := ""}
    ]
  }]
}

/-- Recursively split the conjunction goal into subgoals `goalI`, `goalII`, etc.

Here is an example:
```lean
example {P : Prop} : P → P ∧ (P ∧ P) := script
  intro h
  split_and!
  · exact h
  · exact h
  · exact h
```
-/
script_macro «splitAnd!» (kind := strategy)
"split_and!" => `(tactic| focus
  first
  | guard_target =~ (_ ∧ _)
  | fail "`split_and!` can only be used with `∧` propositions"
  repeat'
    -- An unresolved proposition also matches `False`.
    -- This prevents turning unknown propositions into new conjunctions.
    fail_if_success guard_target =~ False
    guard_target =~ (_ ∧ _)
    apply And.intro
  set_goal_tags' fun i => Lean.Name.mkSimple ("goal" ++ (i + 1).toRoman)
)

script_info «splitAnd!» {
  renderer := «strategy»
}
