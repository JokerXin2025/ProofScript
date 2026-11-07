import ProofScript.Page.State
import ProofScript.Extensions.Title
import ProofScript.Extensions.ProofText

/-!
Title component regression checks and a visual gallery.
Preview: `lake build +Test.PageTitle:ps4html`.
-/

set_option pageBuild true

open Lean Elab Command ProofScript

#page title (label := "title-main") "标题组件：*行内格式* 与 $x^2$"

#page sub title (label := "title-two") "二级标题"
#page sub sub title "三级标题"
#page sub sub sub title "四级标题"
#page sub sub sub sub title (label := "title-five") "五级标题：最小字号"
#page sub sub sub sub sub title (label := "title-six") "六级标题：一个箭头"
#page sub sub sub sub sub sub title "七级标题：两个箭头"
#page sub sub sub sub sub sub sub title (label := "title-eight") "八级标题：三个箭头"

#page sub title "无标签标题，包含 _强调_、`代码`、==高亮== 和 @<title-main>"

-- Exercise a depth well beyond the native HTML heading range.
#page sub sub sub sub sub sub sub sub sub sub sub sub sub sub sub
  sub sub sub sub sub sub sub sub sub sub sub sub sub sub sub sub
  sub sub sub sub sub sub sub sub sub sub sub sub sub sub sub sub
  sub sub sub sub sub sub sub sub sub sub sub sub sub sub sub sub
  title (label := "title-deep") "六十四级标题"

-- Former heading text is now paragraph content and never registers a label.
#page text "= 普通段落 <title-main>\n= 这行仍属于同一段落"
#page text "==段落开头的高亮=="
#page text "> = 引用中的普通段落 <quoted-title>"

#page text r#"
+ 有序列表中的 @<title-main>
  - 嵌套列表中的 @<title-six>
"#

#page sub title (label := "after-text") "正文之后的标题"

/-- error: title label must match [A-Za-z][A-Za-z0-9_-]* -/
#guard_msgs in
#page title (label := "2-invalid") "标签错误"

/-- error: unclosed ProofText delimiter '*' -/
#guard_msgs in
#page sub title "*未闭合的行内格式"

/-- error: duplicate "heading" label 'title-main' -/
#guard_msgs (substring := true) in
#page sub sub title (label := "title-main") "重复标签"

run_cmd do
  let state := getPageState (← getEnv)
  let titles := state.components.filter (·.kind == "title")
  let levels ← titles.mapM fun (component : Component) =>
    Lean.ofExcept <| component.value.getObjValAs? Nat "level"
  unless levels == #[1, 2, 3, 4, 5, 6, 7, 8, 2, 64, 2] do
    throwError m!"title levels were lost or capped: {levels}"
  unless (← ofExcept <| titles[8]!.value.getObjValAs? (Option String) "label").isNone do
    throwError "an unlabeled title acquired a label"
  let firstInlines ← ofExcept <| titles[0]!.value.getObjValAs? (Array Json) "content"
  unless firstInlines.any (fun inline => (inline.getObjVal? "strong").isOk) &&
      firstInlines.any (fun inline => (inline.getObjVal? "math").isOk) do
    throwError "titles lost ProofText inline formatting"
  for label in #["title-main", "title-two", "title-five", "title-six", "title-eight",
      "title-deep", "after-text"] do
    unless state.labels.contains ("heading", label) do
      throwError m!"missing title reference target {label}"
  if state.labels.contains ("heading", "quoted-title") then
    throwError "ProofText still registers headings"
  let texts := state.components.filter (·.kind == "text")
  let literalBlocks ← ofExcept <| texts[1]!.value.getObjValAs? (Array Json) "blocks"
  unless literalBlocks.size == 1 && (literalBlocks[0]!.getObjVal? "paragraph").isOk do
    throwError "old heading markers still split paragraph blocks"
  unless (← ofExcept <| literalBlocks[0]!.getObjVal? "paragraph").getObjValAs?
      (Array ProofText.Inline) "content" |>.isOk do
    throwError "the former heading is not normal inline content"
  unless state.components.back?.any (·.kind == "title") do
    throwError "the title was reordered relative to the text components"

#page end

run_cmd do
  let some page := modulePageDraft? (← getEnv) (← getMainModule)
    | throwError "the title gallery was not persisted"
  unless page.components.size == 15 do
    throwError m!"failed title commands changed the page: {page.components.size} components"

/-- error: page component appears after #page end -/
#guard_msgs in
#page title "关闭页面后的标题"

/-- error: page component appears after #page end -/
#guard_msgs in
#page sub sub sub title "关闭页面后的深层标题"
