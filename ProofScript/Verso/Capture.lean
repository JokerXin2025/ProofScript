import ProofScript.Output.Path
import Verso.Code.Highlighted

namespace ProofScript.Verso

open Lean Elab Command SubVerso.Highlighting

/-- Stage-one resource format. The SubVerso payload is opaque to Python. -/
def formatId : String := "proofscript.verso.highlighted.v1"
def mediaType : String := "application/vnd.proofscript.verso-highlighted+json"

private partial def containsPrivateName (name : Name) : Bool :=
  name.components.any fun part => match part with
    | .str _ s => s.startsWith "scriptcheck_" || s.startsWith "scriptProof%" ||
        s.startsWith "_record_theorem_statement"
    | _ => false

private partial def safeHighlight : Highlighted → Bool
  | .token tok => match tok.kind with
    | .const name .. | .anonCtor name .. => !containsPrivateName name
    | _ => !(tok.content.splitOn "scriptcheck_").length > 1 &&
        !(tok.content.splitOn "scriptProof%").length > 1
  | .seq pieces => pieces.all safeHighlight
  | .span info content => safeHighlight content && info.all (safeMessage ·.2)
  | .tactics goals _ _ content => safeHighlight content && goals.all safeGoal
  | .point _ info => safeMessage info
  | .text text | .unparsed text =>
    !(text.splitOn "scriptcheck_").length > 1 &&
      !(text.splitOn "scriptProof%").length > 1
where
  safeGoal (goal : Highlighted.Goal Highlighted) : Bool :=
    safeHighlight goal.conclusion && goal.hypotheses.all fun hyp =>
      safeHighlight hyp.typeAndVal && hyp.names.all fun tok =>
        match tok.kind with
        | .const name .. => !containsPrivateName name
        | _ => true
  safeMessage : Highlighted.MessageContents Highlighted → Bool
    | .text text => !(text.splitOn "scriptcheck_").length > 1
    | .goal goal => safeGoal goal
    | .term term => safeHighlight term
    | .append parts => parts.all safeMessage
    | .trace _ msg children _ => safeMessage msg && children.all safeMessage

private partial def takeSource (hl : Highlighted) (remaining : Nat) : Option (Highlighted × Nat) := do
  if remaining == 0 then return (.empty, 0)
  match hl with
  | .text text =>
    let part := String.Pos.Raw.extract text 0 ⟨min remaining text.utf8ByteSize⟩
    return (.text part, remaining - part.utf8ByteSize)
  | .unparsed text =>
    let part := String.Pos.Raw.extract text 0 ⟨min remaining text.utf8ByteSize⟩
    return (.unparsed part, remaining - part.utf8ByteSize)
  | .token tok =>
    if tok.content.utf8ByteSize > remaining then none
    else some (hl, remaining - tok.content.utf8ByteSize)
  | .point .. => some (hl, remaining)
  | .seq pieces =>
    let mut left := remaining
    let mut result := #[]
    for piece in pieces do
      if left == 0 then break
      let (next, rest) ← takeSource piece left
      result := result.push next
      left := rest
    return (.seq result, left)
  | .span info content => do
    let (next, rest) ← takeSource content remaining
    return (.span info next, rest)
  | .tactics goals start stop content => do
    let (next, rest) ← takeSource content remaining
    return (.tactics goals start stop next, rest)

/-- The native public theorem is elaborated by the following command; the helper
    InfoTree therefore cannot yet contain its declaration identity. Project it
    onto the exact source range of the declaration identifier, not a token whose
    spelling happens to resemble the resolved name. Source spelling can be
    qualified, escaped, or relative to the current namespace.

    Highlighted nodes retain source text but not token positions. Accumulate
    UTF-8 byte offsets from the command's start; annotations consume no bytes. -/
private partial def markDeclaration (name : Name) (range : Syntax.Range)
    (hl : Highlighted) (offset : Nat) : Highlighted × Nat := Id.run do
  match hl with
  | .token tok =>
    if offset == range.start.byteIdx && offset + tok.content.utf8ByteSize == range.stop.byteIdx then
      return (.token { tok with kind := .const name name.toString none true none }, 1)
    return (hl, 0)
  | .seq pieces =>
    let mut seen := 0
    let mut result := #[]
    let mut position := offset
    for piece in pieces do
      let (next, count) := markDeclaration name range piece position
      seen := seen + count
      result := result.push next
      position := position + piece.toString.utf8ByteSize
    return (.seq result, seen)
  | .span info content =>
    let (next, count) := markDeclaration name range content offset
    return (.span info next, count)
  | .tactics goals start stop content =>
    let (next, count) := markDeclaration name range content offset
    return (.tactics goals start stop next, count)
  | _ => return (hl, 0)

private partial def splitAtBytes (hl : Highlighted) (bytes : Nat) : Option (Highlighted × Highlighted) := do
  if bytes == 0 then return (.empty, hl)
  let size := hl.toString.utf8ByteSize
  if bytes == size then return (hl, .empty)
  if bytes > size then none
  match hl with
  | .text text | .unparsed text =>
    let first := String.Pos.Raw.extract text 0 ⟨bytes⟩
    let rest := String.Pos.Raw.extract text ⟨bytes⟩ ⟨size⟩
    unless first.utf8ByteSize == bytes && first ++ rest == text do none
    return (.text first, .text rest)
  | .seq pieces =>
    let mut first := #[]
    let mut rest := #[]
    let mut left := bytes
    for piece in pieces do
      if left == 0 then
        rest := rest.push piece
      else
        let length := piece.toString.utf8ByteSize
        if left >= length then
          first := first.push piece
          left := left - length
        else
          let (a, b) ← splitAtBytes piece left
          first := first.push a
          rest := rest.push b
          left := 0
    unless left == 0 do none
    return (.seq first, .seq rest)
  | .span info inner =>
    let (a, b) ← splitAtBytes inner bytes
    return (.span info a, .span info b)
  | .tactics goals start stop inner =>
    let (a, b) ← splitAtBytes inner bytes
    return (.tactics goals start stop a, .tactics goals start stop b)
  | .point .. | .token .. => none

private partial def hasTacticRange (hl : Highlighted) (start stop : Nat) : Bool :=
  match hl with
  | .tactics _ s e inner => (s == start && e == stop) || hasTacticRange inner start stop
  | .seq pieces => pieces.any (hasTacticRange · start stop)
  | .span _ inner => hasTacticRange inner start stop
  | _ => false

private def wrapRange (hl : Highlighted) (base start stop : Nat)
    (goals : Array (Highlighted.Goal Highlighted)) : Option Highlighted := do
  unless base ≤ start && start < stop && stop - base ≤ hl.toString.utf8ByteSize do none
  let (before, rest) ← splitAtBytes hl (start - base)
  let (inside, after) ← splitAtBytes rest (stop - start)
  return .seq #[before, .tactics goals start stop inside, after]

/-- A generated recording tactic has a different syntax identity from its user
    `script` statement, even though their canonical source ranges coincide.
    Project only registered wrapper tactic results onto those exact ranges. -/
private def projectScriptStates (original : Syntax) (trees : PersistentArray InfoTree)
    (highlighted : Highlighted) : CommandElabM Highlighted := do
  let table := InfoTable.ofInfoTrees trees.toArray
  let some base := original.getPos? | throwError "Verso: missing command position"
  let mut regions : Array (Nat × Nat × Array (Highlighted.Goal Highlighted)) := #[]
  let mut nodes := #[original]
  for _ in [:64] do
    let mut next := #[]
    for node in nodes do
      if node.getKind.toString.startsWith "scriptTactic" then
        if let some range := node.getRange? (canonicalOnly := true) then
          if !hasTacticRange highlighted range.start.byteIdx range.stop.byteIdx then
            let candidates := (table.tacticInfo[range]?.getD #[]).filter fun (_, ti) =>
              ti.stx.getKind.toString.startsWith "tactic_script_" &&
                !ti.goalsBefore.isEmpty && ti.stx.getRange? (canonicalOnly := true) == some range
            if candidates.size > 0 && candidates.all (fun (_, ti) => ti.goalsAfter.isEmpty) then
              regions := regions.push (range.start.byteIdx, range.stop.byteIdx, #[])
      next := next ++ node.getArgs
    nodes := next
    if nodes.isEmpty then break
  let mut result := highlighted
  for (start, stop, goals) in regions do
    let some wrapped := wrapRange result base.byteIdx start stop goals
      | throwError "Verso: script tactic does not align with original source tokens"
    result := wrapped
  return result

/-- Called while the helper's single check still owns its InfoTree. -/
def capture (declaration : Name) (identifier : TSyntax `ident) (code : String) : CommandElabM String := do
  let file := (← getFileMap).source
  let original? := (← read).macroStack.findSome? fun frame =>
    let source := frame.before.getSubstring?.map (·.toString) |>.getD ""
    if (source.startsWith "#page theorem " || source.startsWith "#page lemma " ||
        source.startsWith "/--") &&
        (match frame.before.getPos?, frame.before.getTailPos? with
         | some start, some stop => String.Pos.Raw.extract file start stop == code
         | _, _ => false) then some frame.before else none
  let some original := original?
    | throwError "Verso: cannot locate original #page command in macro stack"
  let some start := original.getPos?
    | throwError "Verso: original command has no source position"
  let some stop := original.getTailPos?
    | throwError "Verso: original command has no end position"
  let source := String.Pos.Raw.extract (← getFileMap).source start stop
  unless source == code do
    throwError "Verso: captured source differs from proof code"
  let some declarationRange := identifier.raw.getRange? (canonicalOnly := true)
    | throwErrorAt identifier "Verso: declaration identifier has no source range"
  unless start ≤ declarationRange.start && declarationRange.start < declarationRange.stop &&
      declarationRange.stop ≤ stop do
    throwErrorAt identifier "Verso: declaration identifier is outside the captured command"
  let raw ← liftTermElabM <|
    highlightIncludingUnparsed original #[] (← getInfoTrees)
      (startPos? := some start) (endPos? := some stop)
  let highlighted ← if raw.toString == code then pure raw else do
    unless raw.toString.startsWith code do
      throwError "Verso: highlighted source differs from proof code"
    let some (trimmed, 0) := takeSource raw code.utf8ByteSize
      | throwError "Verso: cannot bound highlighted syntax to source range"
    pure trimmed
  let highlighted ← projectScriptStates original (← getInfoTrees) highlighted
  let (highlighted, marked) := markDeclaration declaration declarationRange highlighted start.byteIdx
  unless marked == 1 do
    throwErrorAt identifier "Verso: declaration identifier does not align with a unique source token"
  unless highlighted.toString == code do
    throwError "Verso: highlighted source differs from proof code"
  unless safeHighlight highlighted do
    throwError "Verso: private implementation name in semantic projection"
  let payload := hlToExport highlighted
  let decoded ← match (← ofExcept <| Json.parse payload).getObjVal? "top" with
    | .ok _ => pure (hlFromExport! payload)
    | .error message => throwError "Verso: invalid highlight export: {message}"
  unless decoded.toString == code do
    throwError "Verso: highlight export round-trip changed source"
  return (json% {
    format: $formatId, sourceHash: $(contentHash code), declaration: $declaration,
    producer: "verso-v4.32.0/subverso-0076a9e8", highlighted: $payload }).compress

end ProofScript.Verso
