import ProofScript

open Lean
open ProofScript

structure VideoComponent where
  title : String
  source : String
deriving ToJson

elab "#video" title:str source:str : command => do
  let value : VideoComponent := {
    title := title.getString
    source := source.getString
  }
  addPageComponent source.raw "video" (toJson value)

#video "Introduction" "assets/introduction.mp4"

page_end
