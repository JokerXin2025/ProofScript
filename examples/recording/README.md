# 录制 API 示例

[`RecordingAPI.lean`](RecordingAPI.lean) 展示当前录制协议的最小手写 recorder：

- `record_goal` 写入框架目标字段；
- `record_param` 在 `ProofScript.ParamRecorder` scope 中用 `RecordValue` 实例记录参数值；
- `record_value` 在 `ProofScript.ValueRecorder` scope 中用 `RecordValue` 实例记录已有值；
- `execute` 执行当前 recorder 的前一版本（首次显式定义时执行 script 本体）。

`record_param` 和 `record_value` 都只记录值，
即使表达式或嵌套容器中包含定理常量，也不写入引用暂存区。`snapshot_only`
把 `snapshotEvidence` 保存为参数和嵌套表达式，实际执行只使用局部假设 `h`，因此
`recordedParameterOnly` 的 `proofRefs` 为空。

`explicitCitation` 在 `dependencyCollection false` 下用 `cite snapshotEvidence` 手动
加入文献，导出项的 `isDependency` 为 `false`，导航依赖数组为空。随后的 `#page references`
展示并清空动态暂存区，定理已经保存的 `proofRefs` 仍保留。`dependencyCollection` 只影响
完成证明后的自动收集，不影响这些录制操作或手动引用。若实际证明使用了某个证明常量，
开启自动收集时它仍会成为依赖，参数是否被录制不影响这一判断。

步骤对象使用 `$ruleId`、`$goal_before`、`$goal_after` 和 `$branches` 等框架字段。
用户声明参数名及普通 recorder 键名必须非空，且不能以 `$` 开头；其他键名及可录制值不设白名单，
展示所需结构由 PS4HTML 校验。需要迁移旧 proof JSON 时，请在页面模式下重新运行
`lake build <Library>:ps4html`。

在仓库根目录可以只检查该示例：

```sh
lake env lean examples/recording/RecordingAPI.lean
```
