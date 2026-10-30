import Test.RecorderVersionFixture

open ProofScript

script_recorder importedVersionRule => do
  execute
  record_value "third" true
