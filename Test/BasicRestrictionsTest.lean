import ProofScript

example : ∃ n : Nat, n = 0 := script
  witness
  | data => provide 0
  | proof => rfl

example (n : Nat) (h : 0 + n = n) : 0 + n = n := script
  rw [Nat.zero_add] at h ⊢

example (n : Nat) (_ : 0 + n = n) : n = n := script
  rw [Nat.zero_add] at *

example (n : Nat) (h : (fun x => x) n = n) : n = n := script
  change n = n at h
  assumption

example (n : Nat) (h : (fun x => x) n = n) : (fun x => x) n = n := script
  change n = n at h ⊢
  assumption

example (n : Nat) (h : (fun x => x) n = n) : (fun x => x) n = n := script
  change n = n at *
  assumption

example : ∃ n : Nat, n = 0 := script
  provide 0
