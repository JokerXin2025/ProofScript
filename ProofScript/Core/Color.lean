/-
    ProofScript.Core.Color
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import ProofScript.Core.Codec

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

/-- Encode one channel as exactly two lowercase hexadecimal digits. -/
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

/-- Decode two hexadecimal digits as one color channel. -/
private def colorByte (value : String) : Except String UInt8 := do
  let some high := value.toList[0]? | throw "expected a hexadecimal CSS color"
  let some low := value.toList[1]? | throw "expected a hexadecimal CSS color"
  let digit (c : Char) : Except String Nat :=
    if c >= '0' && c <= '9' then pure (c.toNat - '0'.toNat)
    else if c >= 'a' && c <= 'f' then pure (c.toNat - 'a'.toNat + 10)
    else if c >= 'A' && c <= 'F' then pure (c.toNat - 'A'.toNat + 10)
    else throw "expected a hexadecimal CSS color"
  return UInt8.ofNat ((← digit high) * 16 + (← digit low))

/-- Decode a CSS color string in `#RRGGBB` or `#RRGGBBAA` form. -/
def colorFromString (value : String) : Except String RGBA := do
  let chars := value.toList
  unless chars.head? == some '#' && (chars.length == 7 || chars.length == 9) do
    throw "expected a hexadecimal CSS color (#RRGGBB or #RRGGBBAA)"
  let digits := chars.drop 1
  let red ← colorByte (String.ofList (digits.take 2))
  let green ← colorByte (String.ofList (digits.drop 2 |>.take 2))
  let blue ← colorByte (String.ofList (digits.drop 4 |>.take 2))
  let alpha ← if chars.length == 9 then
    some <$> colorByte (String.ofList (digits.drop 6 |>.take 2)) else pure none
  return ⟨red, green, blue, alpha⟩

/-- Parse an RGB or RGBA channel tuple, or a hexadecimal CSS color literal. -/
instance : InfoCodec RGBA where
  decode stx := do
    match stx with
    | `(term| ($red:term, $green:term, $blue:term)) =>
      return ((← InfoCodec.decode red : Nat), (← InfoCodec.decode green : Nat),
        (← InfoCodec.decode blue : Nat))
    | `(term| ($red:term, $green:term, $blue:term, $alpha:term)) =>
      return ((← InfoCodec.decode red : Nat), (← InfoCodec.decode green : Nat),
        (← InfoCodec.decode blue : Nat), (← InfoCodec.decode alpha : Nat))
    | `(term| $text:str) =>
      match colorFromString text.getString with
      | .ok color => return color
      | .error message => throwErrorAt stx message
    | _ => throwErrorAt stx "expected (red, green, blue) or (red, green, blue, alpha)"

/-- Decode the same hexadecimal CSS representation used by the color input codec. -/
instance : FromJson RGBA where
  fromJson? value := do colorFromString (← fromJson? value)

end ProofScript
