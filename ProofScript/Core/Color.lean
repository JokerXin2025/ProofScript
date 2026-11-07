/-
    ProofScript.Core.Color
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean

open Lean


namespace ProofScript

/-- An RGBA color with byte-valued red, green, blue, and optional alpha channels.

Natural-number tuples can be used wherever an `RGBA` is expected:

```lean
def opaque : RGBA := (255, 128, 0)
def translucent : RGBA := (255, 128, 0, 128)
```

The three-channel coercion sets `alpha = none` (fully opaque). Channels above 255
wrap modulo 256. For example, `(256, 0, 0)` refers to `(0, 0, 0)`. In JSON, colors
are written as `"#RRGGBB"` or `"#RRGGBBAA"`. -/
structure RGBA where
  red : UInt8
  green : UInt8
  blue : UInt8
  alpha : Option UInt8

namespace RGBA

-- Encode one channel as exactly two lowercase hexadecimal digits.
private def hexByte (channel : UInt8) : String :=
  let value := channel.toNat
  hexDigitRepr (value / 16) ++ hexDigitRepr (value % 16)

instance : ToJson RGBA where
  toJson color := Json.str <|
    "#" ++ hexByte color.red ++ hexByte color.green ++ hexByte color.blue
    ++ (color.alpha.map hexByte).getD ""

instance : Coe (Nat × Nat × Nat) RGBA where
  coe := fun (red, green, blue) => {
    red := UInt8.ofNat red,
    green := UInt8.ofNat green,
    blue := UInt8.ofNat blue,
    alpha := none
  }

instance : Coe (Nat × Nat × Nat × Nat) RGBA where
  coe := fun (red, green, blue, alpha) => {
    red := UInt8.ofNat red,
    green := UInt8.ofNat green,
    blue := UInt8.ofNat blue,
    alpha := some (UInt8.ofNat alpha)
  }

end RGBA

end ProofScript
