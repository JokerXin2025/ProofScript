import ProofScript

theorem option_ref (P : Prop) (h : P) : P := h
theorem_info option_ref {tags := ["option"]}

set_option referenceCollection false in
@theorem references_disabled (P : Prop) (h : P) : P := script
  apply (option_ref P)
  assumption

@references

@theorem references_enabled (P : Prop) (h : P) : P := script
  apply (option_ref P)
  assumption

@references
page_end
