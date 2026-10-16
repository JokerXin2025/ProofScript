import ProofScript

@theorem recordingSessionFirst : True := script
  trivial

@theorem recordingSessionSecond : True := script
  trivial

@theorem recordingSessionCalc : (1 : Nat) = 1 := script
  calc
    1 = 1 := by
      rfl
