import Lean

open Lean


namespace ProofScript


/-- Compact index for locating the complete proof resource of a script theorem. -/
initialize scriptDB : MapDeclarationExtension Syntax ←
  mkMapDeclarationExtension `ProofScript.scriptDB

def mkScriptData (typeStx : Syntax) (stmts : Array Syntax) : Syntax :=
  Syntax.node typeStx.getHeadInfo `ProofScript.scriptData
    (stmts.foldl (init := #[typeStx]) (fun acc s => acc.push s))

def registerScript (env : Environment) (name : Name) (typeStx : Syntax)
    (stmts : Array Syntax) : Environment :=
  scriptDB.insert env name (mkScriptData typeStx stmts)

def findScript (env : Environment) (name : Name) : Option Syntax :=
  scriptDB.find? env name

def scriptDataParts (data : Syntax) : Syntax × Array Syntax :=
  (data.getArg 0, data.getArgs[1:])


end ProofScript
