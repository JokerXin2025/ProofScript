import ProofScript

project_info "Test.NestedStrategyTest" { title := "NestedStrategyTest" }

-- Both the outer `claim` and inner `contra` have a `proof` branch.
@theorem nestedRecordedStrategy (P : Prop) (hP : P) : True := script
  claim h : P
  | proof =>
    contra h_c
    | proof =>
      exact h_c hP
  trivial
