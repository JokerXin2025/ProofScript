# Lean2TeX 变量管理系统

当前实现位于 [variable.py](Lean2TeX/variable.py)、[semantic.py](Lean2TeX/semantic.py) 和 [renderer.py](Lean2TeX/renderer.py)。声明类型的前缀使用 `def_info Nat { var_name := "n" }` 配置；Lean 按产物所属模块及其传递导入闭包的最终 Info 冻结，Python 只读取该产物 `snapshotId` 指定的配置。本模块后置的 `def_info` 也会更新前面证明的变量前缀。

默认 reader 给 fvar 和 lambda、forall、let 的绑定节点记录标量 `ProofScript.type`，描述的是变量的类型：

| 描述 | 自动名称前缀 |
| --- | --- |
| `decl:<完整声明名>` | 对应 `var_name`；为空或未配置时取声明末分量的首字母 |
| `proof` | `h` |
| `sort:Prop` | `P` |
| `sort:Type` | `T` |
| `function` | `f` |
| `unknown` 或缺少注解 | `v` |

类型描述由 Lean 在有效上下文中取得；Python 不从结构类型树重新分类。声明名按 Name 分量读取，例如 `Foo.«A.B»` 使用 `A`。已有外层同名 MData 优先，即使外层值不是字符串，也会遮蔽内层类型描述。自定义原样 recorder 自行提供注解，缺少注解时使用 `unknown` 的规则。

fvar 的可用名称取自 `ProofScript.userName`，binder 使用原生名称。空名、`_`、`[anonymous]`、内部生成名和卫生名视为匿名，普通 `_h` 保留。用户名称不因重名而改写，不占用自动编号。

匿名变量按前缀从 1 编号，例如 `n_{1}`、`n_{2}`。不同类型共用同一前缀时共用计数器；同一定理中的同一 fvar ID 复用已生成名称。binder 引入时只分配一次，其 bvar 继承名称、生成标记和绑定身份。退出局部作用域不回收编号。希腊字母和已有下标按数学名称分组，数字下标始终加花括号，前缀不作为 Script 模板解释。

`DisplayNode.generated` 决定自动名称的 `\textcolor{gray}{...}`，用户名称不着灰色。未赋值的表达式元变量固定显示为 `\textcolor{gray}{?}`，不编号；ID 仍保存在数据中。变量显示绕开声明宏匹配，同名声明的样式不会影响变量。

Script 模板继续使用实际表达式字段占位符，例如 `${subject}`；量词短语中的 `${binder}` 使用已经分配的变量名。Lean2TeX 统一处理名称、灰色和关联身份，模板无需读取 MData 或自行拼接编号。

最终 TeX 通过 `htmlData` 携带身份，供 [lean2tex.js](PS4HTML/assets/js/lean2tex.js) 在同一定理内高亮引用。fvar 按 `fvarId`，binder 和 bvar 按 `bindId`／`bindRef` 关联；同名不同变量仍各自独立。生成变量的 `data-l2t-generated` 标记让高亮只改变背景和边框，文字保持灰色。

每个定理创建独立 ProofEngine 和渲染器。外部调用者复用实例时应在定理边界调用 `renderer.reset()`。`render` 在转换或排版异常时恢复本次新增的计数和缓存；分开调用时，成功的 `convert` 提交分配，`render_display` 不改变分配状态。源码位置仍属于各自出现位置，局部定义的类型和值由专用 `let` 步骤展示，后续引用不生成声明悬停提示。

命名系统只保留表达式注解、声明前缀、前缀计数器、fvar 自动名称缓存和绑定身份。内置 `Nat/Int → n`、`Rat → q` 由基础配置提供，`Real → x` 由 Mathlib 配置提供；没有名字池、名称占用或作用域释放接口。Info 协议为 `9.0.0`、manifest 版本为 `9`、snapshot payload 版本为 `7`，旧缓存须重新执行 `lake build MyLibrary:ps4html`；录制协议 `0.3.0` 与调用契约 `2` 不变。完整接口见 [Lean2TeX 说明](Lean2TeX/README.md)，实施进度见[重构计划](../../docs/Variable-Naming-Refactor-Plan-zh.md)。
