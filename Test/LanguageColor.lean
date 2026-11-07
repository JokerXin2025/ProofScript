import ProofScript.Builtin.Script
import ProofScript.Info.Commands

open Lean ProofScript

#guard toJson Language.zh == Json.str "zh"
#guard toJson Language.zh_yue == Json.str "zh-yue"
#guard toJson (Language.custom "Example" "例" "xx") == Json.str "xx"
#guard (InfoCodec.decode (α := Language) (Json.str "xx")).isOk
#guard toJson ((22, 106, 128) : RGBA) == Json.str "#166a80"
#guard toJson ((22, 106, 128, 64) : RGBA) == Json.str "#166a8040"
#guard (InfoCodec.decode (α := Language) (toJson (Language.custom "Example" "例" "xx"))).isOk
#guard (InfoCodec.decode (α := RGBA) (toJson ((22, 106, 128, 64) : RGBA))).isOk
#guard (toJson ({
  tag := some ((22, 106, 128) : RGBA),
  border := some ((22, 106, 128, 64) : RGBA)
} : ScriptColor) == json% { tag: "#166a80", border: "#166a8040", background: null })

decl_info Nat.add { concept_info := {
  default := "plain",
  templates := [
    { label := "plain", lang := Language.custom "Example" "例" "xx", content := "#0 + #1" },
    { label := "plain", lang := en, content := "#0 + #1" }
  ]
} }

script_info «simp» {
  template := [{ lang := Language.custom "Example" "例" "xx", tag := "example", content := "" }],
  color := (some (22, 106, 128), some (22, 106, 128, 64), none)
}
