import ProofScript

set_option pageBuild true

#page theorem Qualified.root (P : Prop) (h : P) : P := by
  exact h

namespace Outer

#page theorem Qualified.nested (P : Prop) (h : P) : P := by
  exact h

end Outer

#page end
