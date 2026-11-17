/-
    ProofScript.Utils.Sundry
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean


/-- Render a natural number as a Roman numeral. Zero renders as `""`. -/
partial def Nat.toRoman (n : Nat) : String :=
  if n >= 1000 then "M" ++ toRoman (n - 1000)
  else if n >= 900 then "CM" ++ toRoman (n - 900)
  else if n >= 500 then "D" ++ toRoman (n - 500)
  else if n >= 400 then "CD" ++ toRoman (n - 400)
  else if n >= 100 then "C" ++ toRoman (n - 100)
  else if n >= 90 then "XC" ++ toRoman (n - 90)
  else if n >= 50 then "L" ++ toRoman (n - 50)
  else if n >= 40 then "XL" ++ toRoman (n - 40)
  else if n >= 10 then "X" ++ toRoman (n - 10)
  else if n >= 9 then "IX" ++ toRoman (n - 9)
  else if n >= 5 then "V" ++ toRoman (n - 5)
  else if n >= 4 then "IV" ++ toRoman (n - 4)
  else if n >= 1 then "I" ++ toRoman (n - 1)
  else ""
