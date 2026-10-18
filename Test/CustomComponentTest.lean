import ProofScript

open Lean
open ProofScript

structure VideoComponent where
  title : String
  source : String
deriving ToJson

-- Internal component fields must not change the public page format.
run_cmd do
  let component : Component := {
    source := { file := "component.lean", start := 3, stop := 9 }
    kind := "video"
    value := json% { title: "Introduction", source: "assets/introduction.mp4" }
    declaration := some `Internal.declaration
    «references» := #[`Internal.reference]
    boundary := .before 17 }
  let expected := json% {
    source: { file: "component.lean", start: 3, stop: 9 },
    data: { video: { value: { title: "Introduction", source: "assets/introduction.mp4" } } }
  }
  unless (toJson component).compress == expected.compress do
    throwError "component JSON changed its data envelope or exposed internal fields"
  let resolved := { component with snapshotId := some "snapshot" }
  unless (toJson resolved).compress == (expected.setObjVal! "snapshotId" (toJson "snapshot")).compress do
    throwError "component JSON lost its optional snapshot ID"

elab "#video" title:str source:str : command => whenPageBuild do
  let value : VideoComponent := {
    title := title.getString
    source := source.getString
  }
  addPageComponent source.raw "video" (toJson value)

#video "Introduction" "assets/introduction.mp4"

page_end
