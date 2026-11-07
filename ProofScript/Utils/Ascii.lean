namespace ProofScript

/- Basic printable ASCII is deliberately narrower than Unicode so values can be
  used safely as stable labels in configuration, URLs, and generated metadata. -/
def isBasicAscii (character : Char) : Bool :=
  32 ≤ character.toNat && character.toNat ≤ 126

def isNonemptyBasicAscii (value : String) : Bool :=
  !value.isEmpty && value.toList.all isBasicAscii

end ProofScript
