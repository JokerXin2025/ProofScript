import ProofScript

open Lean ProofScript ProofScript.Recording

declare_syntax_cat labelValue
syntax ident : labelValue

instance : RecordParam (.category `labelValue) where
  schema := .name
  capture value := identifierName ⟨value.raw[0]⟩

script_macro recordLabels
  (params := [labels(timing := once, field := "items", failure := required)])
  "record_labels" "[" labels:sepBy(labelValue, ",") "]" => `(tactic| skip)

script_info recordLabels {
  template := [{ lang := "zh", tag := "标签", content := "${items}" },
               { lang := "en", tag := "Labels", content := "${items}" }]
}

script_macro recordLabel
  (params := [label(timing := once, failure := required)])
  "record_label" label:(colGt labelValue)? => `(tactic| skip)

script_info recordLabel {
  template := [{ lang := "en", tag := "Optional label", content := "${label}" }]
}

@theorem labelsExample : True := script
  record_labels []
  record_labels [alpha]
  record_labels [alpha, beta]
  record_label
  record_label gamma
  trivial

page_end
