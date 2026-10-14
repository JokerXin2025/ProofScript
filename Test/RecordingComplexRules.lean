import ProofScript

open Lean ProofScript ProofScript.Recording

set_option linter.unusedVariables false

-- An external category requires only an instance; arrays and optionals compose it.
declare_syntax_cat recordingLabel
syntax ident : recordingLabel

instance : RecordCategory `recordingLabel where
  schema := .name
  capture value := identifierName ⟨value.raw[0]⟩

script_macro labels
  (params := [labels(timing := once, field := "items", failure := required)])
  "record_labels" "[" labels:sepBy(recordingLabel, ",") "]" => `(tactic| skip)

script_info labels {
  template := [{ lang := "zh", tag := "Labels", content := "${items}" }]
}

script_macro numberParam (params := [n(timing := once, failure := required)])
  "record_number" n:num => `(tactic| skip)

script_info numberParam {
  template := [{ lang := "zh", tag := "Number", content := "${n}" }]
}

script_macro optionalLabel
  (params := [label(timing := once, failure := required)])
  "record_optional" label:(colGt recordingLabel)? => `(tactic| skip)

script_info optionalLabel {
  template := [{ lang := "zh", tag := "Optional", content := "${label}" }]
}

-- Imported overrides take effect in this proof module and exercise nested paths.
script_info ProofScript.Script.Basic.rw {
  template := [{ lang := "zh", tag := "Rewrite", content := "${rules.0.expression}; ${loc_before.hypotheses}" }]
}
script_info ProofScript.Script.Basic.simp {
  template := [{ lang := "zh", tag := "Simplify", content := "${args}; ${config}" }]
}

