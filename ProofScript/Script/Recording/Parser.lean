import ProofScript.Script.Recording.Shape

namespace ProofScript.Recording

open Lean

/-- Parser extraction and semantic shape are deliberately separate. -/
inductive ParamParser where
  | category (name : Name)
  | array (element : ParamParser) (separated : Bool)
  | optional (element : ParamParser)
  deriving Repr, Inhabited, BEq

def ParamParser.shape : ParamParser → ParamShape
  | .category name => .category name
  | .array element _ => .array element.shape
  | .optional element => .optional element.shape

/-- Registration signatures retain parser extraction for supported shapes and structural
    syntax for unsupported parsers. Two unsupported parsers must not match merely because
    both lack a shape. Only immutable metadata is persisted, never capture actions. -/
inductive ParamParserSignature where
  | normalized (parser : ParamParser)
  | unsupported (parser : Syntax)
  deriving Repr, Inhabited, BEq

def ParamParserSignature.shape? : ParamParserSignature → Option ParamShape
  | .normalized parser => some parser.shape
  | .unsupported _ => none

end ProofScript.Recording
