import ProofScript

@theorem citedTheorem (info := {
  name := "Cited theorem"
}) (P : Prop) (h : P) : P := script
  assumption


example (P : Prop) (h : P) : P := script
  cite citedTheorem P h
  exact h

example (P : Prop) (h : P) : P := script
  cite (citedTheorem P h)
  exact h

/-- error: `cite` requires a theorem declaration -/
#guard_msgs in
example (P : Prop) (h : P) : P := script
  cite h
  exact h

theorem ordinaryTheorem (P : Prop) : P → P := fun h => h

/-- error: `ordinaryTheorem` is not a literature theorem -/
#guard_msgs in
example (P : Prop) (h : P) : P := script
  cite ordinaryTheorem
  exact h
