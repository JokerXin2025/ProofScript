import Lean.Elab.Tactic
import Lean.Parser.Command
import Lean.Parser.Term

namespace ProofScript

open Lean
open Parser (atomic darrow sepBy optional ppSpace many1 termParser withPosition
             nonReservedSymbol suppressInsideQuot)
open Parser.Term (ident)
open Parser.Command (macroArg macroRhs docComment)

declare_syntax_cat scriptTactic (behavior := both)
register_option proofScript.scriptMode.active : Bool := {
  defValue := false
  descr := "internal execution context for script tactics"
}

def withScriptMode {α} (action : Lean.Elab.Tactic.TacticM α) : Lean.Elab.Tactic.TacticM α :=
  Lean.withOptions (·.setBool `proofScript.scriptMode.active true) action


/-- 配置值：`[ident, ident, …]`（可空 `[]`）。直接写标识符名（与 `syntax` 参数名一致），
    不带双引号、不经 `evalExprWithElab` 求值——从语法树里直接取 ident 名字。 -/
def scriptCfgIdents := leading_parser "[" >> sepBy ident ", " >> "]"

def scriptCfgBool := leading_parser nonReservedSymbol "true" <|> nonReservedSymbol "false"

def paramCfgItem := leading_parser ident >> " := " >> (ident <|> Lean.Parser.strLit)
def paramCfg := leading_parser "(" >> sepBy paramCfgItem ", " >> ")"
def scriptParamCfg := leading_parser "[" >> sepBy (ident >> paramCfg) ", " >> "]"

def scriptCfgValue := leading_parser
  atomic scriptParamCfg <|> scriptCfgIdents <|> scriptCfgBool <|> Lean.Parser.numLit

def scriptCfgItem := leading_parser ident >> ":=" >> scriptCfgValue

def scriptCfg := leading_parser "(" >> sepBy scriptCfgItem ", " >> ")"


def scriptMacroTacticTail := leading_parser darrow >> macroRhs
def scriptElabTacticTail := leading_parser darrow >> withPosition termParser

  /-- `script_macro`：生成 `script_` 执行入口和独立录制入口。
      复用 `macro` 命令的参数和 RHS parser。 -/
@[command_parser] def scriptMacro := leading_parser
  suppressInsideQuot <|
    optional docComment >> "script_macro" >> ppSpace >> ident >> optional scriptCfg >> many1 (ppSpace >> macroArg) >> scriptMacroTacticTail

 /-- `script_elab`：生成 `script_` 执行入口和独立录制入口。 -/
@[command_parser] def scriptElab := leading_parser
  suppressInsideQuot <|
    optional docComment >> "script_elab" >> ppSpace >> ident >> optional scriptCfg >> many1 (ppSpace >> macroArg) >> scriptElabTacticTail

/-- `script_recorder <id>`：按本地注册 ID 覆盖默认自动录制入口。
    ID 后的第一个字符串仍是该注册原本的策略关键字。
     `recordStep` / `recordStrategy` 按注册 ID 执行对应的执行版。 -/
def scriptRecorderCfg := leading_parser "(" >> nonReservedSymbol "fields" >> " := " >> termParser >> ")"

@[command_parser] def scriptRecorder := leading_parser
  suppressInsideQuot <|
    optional docComment >> "script_recorder" >> ppSpace >> ident >> optional scriptRecorderCfg >>
      many1 (ppSpace >> macroArg) >> scriptElabTacticTail

end ProofScript
