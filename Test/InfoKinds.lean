import ProofScript

open Lean Elab Command ProofScript

set_option pageBuild true

namespace InfoKinds

def plain (n : Nat) := n
def relation (n m : Nat) := n = m
def wrapper (n : Nat) := n
def aliasTarget (n m : Nat) := n = m
def symbolic (n m : Nat) := n + m
def macroConcept (n : Nat) := n

decl_info plain { wrapper_info := { index := some 0 },
  relation_info := { symbol := "=" },
  concept_info := { templates := [{ label := "formula", content := "#0" }] } }
relation_info relation { symbol := "=" }
wrapper_info wrapper { index := some 0 }
alias_info aliasTarget { target := some relation }
operator_info symbolic { symbol := "+", fixity := «infix», precedence := 65, associativity := left }
concept_info macroConcept { auto_arity := true,
  templates := [{ label := "formula", content := "#0" }], default := "formula" }

run_cmd do
  let env ← getEnv
  let query : Query := { moduleName := env.mainModule }
  let resolve := fun name => match resolveDefinitionInfo env query name with
    | .ok info => pure info.value
    | .error error => throwError error.render
  let plainInfo ← resolve `InfoKinds.plain
  unless plainInfo.kind == .concept && plainInfo.concept_info.templates.size == 1 do
    throwError "concept must retain its templates without activating unrelated fields"
  let relationInfo ← resolve `InfoKinds.relation
  unless relationInfo.kind == .relation && relationInfo.relation_info.symbol == "=" do
    throwError "relation command must configure its symbol"
  let wrapperInfo ← resolve `InfoKinds.wrapper
  unless wrapperInfo.kind == .wrapper && wrapperInfo.wrapper_info.index == some 0 do
    throwError "wrapper command must configure its index"
  let aliasInfo ← resolve `InfoKinds.aliasTarget
  unless aliasInfo.kind == .alias && aliasInfo.alias_info.target.map (·.name) == some `InfoKinds.relation do
    throwError "alias command must configure its target"
  let operatorInfo ← resolve `InfoKinds.symbolic
  unless operatorInfo.kind == .operator && operatorInfo.operator_info.symbol == "+" &&
      operatorInfo.operator_info.precedence == 65 do
    throwError "operator command must configure its symbol and layout"
  let conceptInfo ← resolve `InfoKinds.macroConcept
  unless conceptInfo.kind == .concept && conceptInfo.concept_info.templates.size == 1 do
    throwError "concept command must configure templates"

end InfoKinds
