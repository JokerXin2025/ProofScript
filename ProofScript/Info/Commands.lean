import ProofScript.Info.Theorem
import ProofScript.Info.Variable
import ProofScript.Info.Phrase
import ProofScript.Info.Definition
import ProofScript.Info.Script

open Lean ProofScript.Info


elab "project_info" target:(ppSpace str)? ppSpace fields:infoFields : command
=> do updateProjectInfo target (← readFields fields) (← getRef)

elab "theorem_info" ppSpace id:ident fields:(ppSpace infoFields)? : command
=> do updateTheoremInfo id ((← fields.mapM readFields).getD #[]) (← getRef)

elab "var_info" ppSpace target:str ppSpace fields:infoFields : command
=> do updateLiteralInfo variableSpec target (← readFields fields) (← getRef)

elab "phrase_info" ppSpace target:str ppSpace fields:infoFields : command
=> do updateLiteralInfo phraseSpec target (← readFields fields) (← getRef)

elab "def_info" ppSpace target:ident ppSpace fields:infoFields : command
=> do updateDeclarationInfo definitionSpec target (← readFields fields) (← getRef)

elab "script_info" ppSpace target:ident ppSpace fields:infoFields : command
=> do updateScriptInfo target (← readFields fields) (← getRef)
