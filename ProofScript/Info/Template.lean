import ProofScript.Info.Value

namespace ProofScript.Info

/-- Literal ${name} references. Rendering and language fallback remain consumer responsibilities. -/
def namedPlaceholders (template : String) : Array String := Id.run do
  let chars := template.toList.toArray
  let mut result := #[]
  let mut index := 0
  while index + 1 < chars.size do
    if chars[index]! == '$' && chars[index + 1]! == '{' then
      let start := index + 2
      index := start
      while index < chars.size && chars[index]! != '}' do index := index + 1
      if index < chars.size then
        result := result.push (String.ofList (chars.toList.drop start |>.take (index - start)))
    index := index + 1
  return result

structure ArgumentReferences where
  arguments : Array Nat := #[]
  /-- (selected argument index, @ depth); @@0 selects the body after one binder. -/
  binders : Array (Nat × Nat) := #[]
  dynamic : Bool := false
  deriving Inhabited

private def naturalAt (chars : Array Char) (start : Nat) : Nat × Nat := Id.run do
  let mut index := start
  let mut value := 0
  while index < chars.size && chars[index]!.isDigit do
    value := value * 10 + (chars[index]!.toNat - '0'.toNat)
    index := index + 1
  return (value, index)

/-- Matches the existing #N, #* and @...N selector grammar without interpreting TeX. -/
def argumentReferences (template : String) : ArgumentReferences := Id.run do
  let chars := template.toList.toArray
  let mut result : ArgumentReferences := {}
  let mut index := 0
  while index < chars.size do
    if chars[index]! == '#' && index + 1 < chars.size then
      if chars[index + 1]! == '*' then result := { result with dynamic := true }
      let (value, stop) := naturalAt chars (index + 1)
      if stop > index + 1 then
        result := { result with arguments := result.arguments.push value }
        index := stop
      else index := index + 1
    else if chars[index]! == '@' then
      let start := index
      while index < chars.size && chars[index]! == '@' do index := index + 1
      let (value, stop) := naturalAt chars index
      if stop > index then
        result := { result with binders := result.binders.push (value, index - start) }
        index := stop
    else index := index + 1
  return result

end ProofScript.Info
