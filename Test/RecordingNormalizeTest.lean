import Test.RecordingComplexRules

set_option linter.unusedVariables false

script_elab labelSingle "label_single" _x:recordingLabel => pure ()
script_elab labelMany "label_many" "[" _xs:recordingLabel+ "]" => pure ()
script_elab labelStar "label_star" "[" _xs:recordingLabel* "]" => pure ()
script_elab labelOptional "label_optional" "[" _x:(recordingLabel)? "]" => pure ()
script_elab labelSeparated "label_separated" "[" _xs:sepBy(recordingLabel, ",") "]" => pure ()
script_elab labelSeparatedOne "label_separated_one" "[" _xs:sepBy1(recordingLabel, ",") "]" => pure ()
script_elab labelIndented "label_indented" _xs:(colGt recordingLabel)+ => pure ()

@theorem recordingNormalizedParameters : True := script
  label_single alpha
  label_many [alpha beta]
  label_star []
  label_star [alpha]
  label_star [alpha beta]
  label_optional []
  label_optional [alpha]
  label_separated []
  label_separated [alpha]
  label_separated [alpha, beta]
  label_separated_one [alpha]
  label_indented
    alpha beta
  trivial
