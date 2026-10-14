import Lean

open Lean


namespace ProofScript

structure ProjectInfo where
  title : String := ""
  authors : List String := []
  keywords : List String := []
  description : String := ""
  year : String := ""
  license : String := ""
  base_url : String := ""
  extra : List (String × String) := []
  deriving Inhabited, Repr, ToJson, FromJson

structure TheoremInfo where
  project : ProjectInfo := {}
  name : String := ""
  tags : List String := []
  extra : List (String × String) := []
  deriving Inhabited, Repr, ToJson, FromJson

initialize theoremInfoExt : MapDeclarationExtension TheoremInfo ←
  mkMapDeclarationExtension `ProofScript.theoremInfo

def findTheoremInfo (env : Environment) (name : Name) : Option TheoremInfo :=
  theoremInfoExt.find? env name

end ProofScript
