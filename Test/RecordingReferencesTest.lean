import ProofScript

project_info "Test.RecordingReferencesTest" { title := "RecordingReferencesTest" }

theorem recordingRefFirst : True := True.intro
theorem_info recordingRefFirst {name := "First reference"}

theorem recordingRefSecond : True := True.intro
theorem_info recordingRefSecond {name := "Second reference"}

@theorem recordingRefRepeated : True := script
  cite recordingRefFirst
  cite recordingRefFirst
  trivial

@references

@theorem recordingRefOrdered : True := script
  cite recordingRefFirst
  cite recordingRefSecond
  trivial

@references
page_end
