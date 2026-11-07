import ProofScript

namespace InfoTargetValidation

def existing : Nat := 1
def ignoredFields (n : Nat) := n

decl_info ignoredFields { wrapper_info := { index := some 0 },
  relation_info := { symbol := "=" },
  operator_info := { symbol := "+", fixity := «infix», precedence := 10, associativity := left },
  concept_info := { templates := [{ label := "formula", content := "#0" }] } }

project_info { title := "Info validation" }
decl_info existing {}
theorem_info Nat.add_comm {}
script_info «simp» {}

set_option pageBuild true

/-- error: expected a string literal -/
#guard_msgs (substring := true) in
project_info { title := h }

/-- error: expected a string literal -/
#guard_msgs (substring := true) in
theorem_info Nat.add_comm { name := h }

/-- error: expected a string literal -/
#guard_msgs (substring := true) in
decl_info existing { var_name := h }

/-- error: expected a string literal -/
#guard_msgs (substring := true) in
script_info «simp» { template := [{ lang := zh, tag := "test", content := h }] }

/-- error: theorem_info.project has been removed -/
#guard_msgs (substring := true) in
theorem_info Nat.add_comm { project := "obsolete" }

/-- error: expected a JSON literal -/
#guard_msgs (substring := true) in
project_info { extra := { invalid := h } }

/-- error: duplicate field `title` -/
#guard_msgs (substring := true) in
project_info { title := "first", title := "second" }

/-- error: invalid value `not_a_kind` -/
#guard_msgs (substring := true) in
decl_info existing { kind := not_a_kind }

/-- error: unknown field `fixity` -/
#guard_msgs (substring := true) in
decl_info existing { concept_info := { templates := [{ label := "formula", content := "n", fixity := «infix» }] } }

/-- error: precedence: precedence exceeds 100 -/
#guard_msgs (substring := true) in
decl_info existing { operator_info := { precedence := 101 } }

/-- error: unknown field `unwrap` -/
#guard_msgs (substring := true) in
decl_info existing { wrapper_info := { unwrap := some 0 } }

/-- error: Unknown constant `missing` -/
#guard_msgs (substring := true) in
decl_info missing {}

def asciiLabel : Nat := 1

/- error: label must be a nonempty printable ASCII string -/
#guard_msgs (substring := true) in
decl_info asciiLabel { concept_info := { templates := [{ label := "", content := "n" }] } }

/- error: formula label must not specify lang -/
#guard_msgs (substring := true) in
decl_info asciiLabel { concept_info := { templates := [{ label := "formula", lang := en, content := "n" }] } }

/- error: label must be a nonempty printable ASCII string -/
#guard_msgs (substring := true) in
decl_info asciiLabel { concept_info := { templates := [{ label := "粗体", content := "n" }] } }

/- error: default label must have an en template -/
#guard_msgs (substring := true) in
decl_info asciiLabel { concept_info := { default := "plain", templates := [
  { label := "formula", content := "n" },
  { label := "plain", lang := ja, content := "n" }
] } }

/- error: at least one formula or en template is required -/
#guard_msgs (substring := true) in
decl_info asciiLabel { concept_info := { default := "zh", templates := [{ label := "zh", lang := zh, content := "n" }] } }

/- error: duplicate label and lang combination -/
#guard_msgs (substring := true) in
decl_info asciiLabel { concept_info := { default := "plain", templates := [
  { label := "plain", lang := en, content := "n" },
  { label := "plain", lang := en, content := "m" }
] } }

/-- error: Unknown constant `missing` -/
#guard_msgs (substring := true) in
theorem_info missing {}

/-- error: unknown script_info registration ID `missing` -/
#guard_msgs (substring := true) in
script_info missing {}

end InfoTargetValidation
