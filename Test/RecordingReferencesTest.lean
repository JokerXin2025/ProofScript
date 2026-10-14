import ProofScript

open Lean ProofScript

theorem recordingRefFirst : True := True.intro
theorem_info recordingRefFirst {name := "First reference"}

theorem recordingRefSecond : True := True.intro
theorem_info recordingRefSecond {name := "Second reference"}

run_cmd do
  -- References live across commands, but command rollback must discard additions.
  let saved ← get
  addTheoremRef ``recordingRefFirst
  set saved
  unless (← getTheoremRefs).isEmpty do
    throwError "reference survived command rollback"

run_cmd do
  addTheoremRef ``recordingRefFirst
  addTheoremRef ``recordingRefFirst

run_cmd do
  unless (← getTheoremRefs) == [``recordingRefFirst] do
    throwError "reference accumulation or deduplication changed"
  addTheoremRef ``recordingRefSecond

run_cmd do
  unless (← getTheoremRefs) ==
      [``recordingRefFirst, ``recordingRefSecond] do
    throwError "reference insertion order changed"

@references

run_cmd do
  unless (← getTheoremRefs).isEmpty do
    throwError "@references did not consume the collected references"

page_end
