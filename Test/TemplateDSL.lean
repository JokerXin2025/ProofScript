import ProofScript.Info.Decl.Commands

open Lean Elab Command ProofScript

run_cmd do
  for source in [
      "{ label := \"bad\", precedence := 70, content := template% { arg(0) } }",
      "{ label := \"bad\", auto_arity := false, content := template% { arg(0) } }",
      "{ label := \"bad\", isolated_args := [0], content := template% { arg(0) } }",
      "{ label := \"bad\", content := template%:101 { arg(0) } }",
      "{ label := \"bad\", binders := [(0, 1)], content := template% { arg(0) } }"] do
    let .ok stx := Parser.runParserCategory (← getEnv) `term source
      | throwError "invalid test source"
    let rejected ← try
      let _ ← liftCoreM <| InfoCodec.decode (α := DefinitionTemplate) ⟨stx⟩
      pure false
    catch _ => pure true
    unless rejected do throwError "obsolete field or invalid priority was accepted"

run_cmd do
  let env ← getEnv
  for source in [
      "template% { $ arg(0) }",
      "template% ${ $ arg(0) }$",
      "template% { $ $ }",
      "template% ${ arg(x) }$",
      "template% raw :70 { arg(0) }"] do
    match Parser.runParserCategory env `term source with
    | .error _ => pure ()
    | .ok _ => throwError "malformed template unexpectedly parsed: {source}"

/- Exercise decoding, native argument mapping, and the exact renderer wire data. -/
run_cmd do
  let input ← `(term| {
    label := "mixed",
    content := template% { "从" arg(0) "到" $ arg!(1) " + " arg(0) $ "结束" }
  })
  let template ← liftCoreM <| InfoCodec.decode (α := DefinitionTemplate) input
  let facts : DefinitionArgumentFacts := {
    binder_infos := #[.implicit, .default, .default], explicit_indices := #[1, 2] }
  let frozen ← match freezeDefinitionTemplate facts template with
    | .ok value => pure value
    | .error error => throwError error
  unless (frozen.getObjVal? "argument_indices").toOption == some (toJson (#[1, 2] : Array Nat)) do
    throwError "incorrect explicit argument mapping"
  let expected := #[
    DefinitionTemplateInstruction.literal "从", .argument 0 .text,
    .literal "到", .modeSwitch .formula #[.argument 1 .formula true, .literal " + ", .argument 0 .formula],
    .literal "结束"]
  unless (frozen.getObjVal? "instructions").toOption == some (toJson expected) do
    throwError "incorrect mixed-mode instructions: {frozen}"

run_cmd do
  let input ← `(term| {
     label := "lambda",
     content := template%:100 ${ binder!(0, 1) "," binder(0, 2) ":" body!(0, 2) }$
  })
  let template ← liftCoreM <| InfoCodec.decode (α := DefinitionTemplate) input
  unless template.content.precedence == some 100 do throwError "priority was not decoded"
  let expected := #[DefinitionTemplateInstruction.binder 0 1 .formula true,
    .literal ",", .binder 0 2 .formula, .literal ":", .body 0 2 .formula true]
  unless (compileDefinitionInstructions template).toOption == some expected do
    throwError "binder and body must lower to distinct selectors"

run_cmd do
  let input ← `(term| { label := "literal", content := template% { "#0 @0 #*" } })
  let template ← liftCoreM <| InfoCodec.decode (α := DefinitionTemplate) input
  unless (compileDefinitionInstructions template).toOption == some #[.literal "#0 @0 #*"] do
    throwError "literal strings must not be interpreted as selectors"

/-- error: content: expected a template% literal -/
#guard_msgs in
decl_info Nat { templates := [{ label := "old", content := "#0" }] }

/-- error: binder layers start at 1 -/
#guard_msgs in
decl_info Nat { templates := [{ label := "bad", content := template% ${ binder(0, 0) }$ }] }

run_cmd do
  let input ← `(term| { label := "body", content := template% ${ body(0, 0) body(0, 3) binder(0, 4) }$ })
  let template ← liftCoreM <| InfoCodec.decode (α := DefinitionTemplate) input
  unless (compileDefinitionInstructions template).toOption == some
      #[.body 0 0 .formula, .body 0 3 .formula, .binder 0 4 .formula] do
    throwError "body zero and unconstrained selector depths must compile"

run_cmd do
  let input ← `(term| { label := "missing", content := template% { $ arg(1) $ } })
  let template ← liftCoreM <| InfoCodec.decode (α := DefinitionTemplate) input
  let facts : DefinitionArgumentFacts := { binder_infos := #[.default], explicit_indices := #[0] }
  match freezeDefinitionTemplate facts template with
  | .error "content: template references a missing declaration argument" => pure ()
  | _ => throwError "out-of-range selectors must fail at freezing"

run_cmd do
  let input ← `(term| { label := "raw",
    content := template%:70 raw ${ arg(0) $ "text" $ }$ })
  let template ← liftCoreM <| InfoCodec.decode (α := DefinitionTemplate) input
  let facts : DefinitionArgumentFacts := {
    binder_infos := #[.implicit, .default], explicit_indices := #[1] }
  let .ok frozen := freezeDefinitionTemplate facts template
    | throwError "raw parameter template failed to freeze"
  unless (frozen.getObjVal? "argument_indices").toOption == some (toJson (#[0, 1] : Array Nat)) do
    throwError "raw parameter mapping must include implicit slots"
  unless (compileDefinitionInstructions template).toOption ==
      some #[.argument 0 .formula, .modeSwitch .text #[.literal "text"]] do
    throwError "formula templates must switch to text"

-- Page mode exercises persistence, final-view merging and symbol shorthands.
set_option pageBuild true

def templateDSLJuxtapose (a b : Nat) := a * b
decl_info infix templateDSLJuxtapose "" (mode := formula, precedence := 70)
decl_info infixl templateDSLJuxtapose "" (mode := formula, precedence := 70)
decl_info infixr templateDSLJuxtapose "" (mode := formula, precedence := 70)
run_cmd do
  let (frozen, _) ← ofExcept <| freezeDeclInfo (← getEnv) (← getEnv).mainModule ``templateDSLJuxtapose
  let templates ← ofExcept <| frozen.getObjValAs? (Array Json) "templates"
  unless templates.size == 3 do throwError "empty infix shorthands were not retained"
  for template in templates do
    let instructions ← ofExcept <| template.getObjVal? "instructions"
    unless instructions == toJson (#[DefinitionTemplateInstruction.argument 0 .formula,
        .literal "  ", .argument 1 .formula] : Array DefinitionTemplateInstruction) do
      throwError "empty infix shorthand must keep its operand separator"

-- A returned predicate is an interval object, not another native argument.
-- Counting its reducible function type would prevent the endpoint template
-- from matching complete interval applications in theorem statements.
def TemplateDSLSet := Nat → Prop
def templateDSLInterval (a b : Nat) : TemplateDSLSet := fun x => a ≤ x ∧ x ≤ b
decl_info templateDSLInterval { templates := [{ label := "interval",
  content := template%:100 ${ "[" arg!(0) "," arg!(1) "]" }$ }] }
run_cmd do
  let env ← getEnv
  let (frozen, _) ← ofExcept <| freezeDeclInfo env env.mainModule ``templateDSLInterval
  unless (frozen.getObjVal? "arity").toOption == some (toJson (2 : Nat)) &&
      (frozen.getObjVal? "parameter_argument_indices").toOption ==
        some (toJson (#[0, 1] : Array Nat)) do
    throwError "a returned set must not add an argument to the interval template"

def templateDSLPair (a b : Nat) := (a, b)
decl_info templateDSLPair { templates := [{ label := "mixed",
  content := template% { "从" arg(0) "到" $ arg(1) $ } }] }
run_cmd do
  let env ← getEnv
  let .ok (frozen, _) := freezeDeclInfo env env.mainModule ``templateDSLPair
    | throwError "DSL template did not survive persistence and merging"
  unless (frozen.getObjVal? "default_template").toOption == some (toJson "mixed") do
    throwError "incorrect frozen default"

decl_info infix templateDSLPair "and" (mode := text)
decl_info infixl templateDSLPair "+" (precedence := 65)
decl_info infixr templateDSLPair "^" (precedence := 70)
run_cmd do
  let env ← getEnv
  let .ok view := resolveTypedDecl env env.mainModule ``templateDSLPair
    | throwError "missing symbol configuration"
  let .ok templates := view.readTemplates | throwError "missing symbol templates"
  let some template := templates[0]? | throwError "empty symbol templates"
  unless template.label == "$infixr" && templates.any (·.label == "$infixl") &&
      templates.any (·.label == "$infix") do
    throwError "infix shorthand variants must retain their distinct labels"
  let .ok info := view.materialize | throwError "missing declaration classification"
  unless info.kind == .operator do throwError "symbol shorthand must classify operators"
  let some template := templates.find? (·.label == "$infix")
    | throwError "missing original infix template"
  unless (compileDefinitionInstructions template).toOption ==
      some #[.argument 0 .text, .literal " and ", .argument 1 .text] do
    throwError "symbol shorthand must build typed fragments in the selected mode"
