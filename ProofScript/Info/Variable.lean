import ProofScript.Info.Derive
import ProofScript.Info.Target

namespace ProofScript.Info

open Lean

structure VariableInfo where
  default : String
  names : Array String
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

def variableSpec : InfoSpec VariableInfo :=
  { kind := "variable" }

def resolveVariableInfo (env : Environment) (query : Query) (target : Name) :
    Except Diagnostic (ResolvedInfo VariableInfo) :=
  resolveConfiguredInfo variableSpec env query target

end ProofScript.Info
