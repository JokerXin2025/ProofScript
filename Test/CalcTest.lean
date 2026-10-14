import ProofScript

set_option linter.defProp false

-- 测试：不带 @theorem 的 calc
theorem test_calc_no_export (a b c : Nat) (hab : a = b) (hbc : b = c) : a = c := script
  calc
    a = b := hab
    _ = c := hbc

-- 测试：@theorem + calc 录制
@theorem test_calc_with_export (a b c d : Nat)
    (hab : a = b) (hbc : b = c) (hcd : c = d) : a = d := script
  calc
    a = b := hab
    _ = c := hbc
    _ = d := hcd

-- 测试：calc 中使用 ?_
@theorem test_calc_with_hole (a b c : Nat) (hab : a = b) (hbc : b = c) : a = c := script
  calc
    a = b := hab
    _ = c := ?_
  assumption
