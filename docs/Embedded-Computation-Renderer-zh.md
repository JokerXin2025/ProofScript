# 嵌入式计算渲染协议

本文描述当前实现。完整资源交接见 [前端交接文档](Frontend-Computation-Handoff-zh.md)，
可运行示例见 [快速开始](Embedded-Computation-Quickstart-zh.md)。

## 数据契约

`@computation` 将 Lean 函数与浏览器 renderer 关联。页面、计算组件、pending manifest、
构建 bundle、发布 bundle 和计算 index 的 `schemaVersion` 统一为 `0.0.0`。
ABI 标识仍为 `proofscript-json-v1`，renderer ID 的 `v1/v2` 是独立标识，不是 Schema 版本。

组件包括 metadata、renderer、function、execution、payload。function 包含声明名、类型及
expression/implementation/expressions；这些表达式用于来源追踪与分析，不作为浏览器执行 ABI。
payload 是 UI 配置；实际执行由 `execution.backend/status/abi` 决定。

当前实现的执行后端是 **wasm**。table/rpc/declarative 不属于已实现的通用后端。

## 编译与发布

1. Lean elaboration 检查一个显式、非依赖输入，接受 `α → β` 或 `α → Except String β`。
2. 合成 `FromJson α` 和 `ToJson β`，生成 `String → String` wrapper。
3. 导出 pending manifest，页面标记 `execution.status = pending`。
4. Lake 产生模块 C IR。
5. `scripts/build-computations.mjs` 按 bundleId 分组，定位 wrapper 和计算支持代码，
   沿可用 imported C artifacts 的符号依赖选择链接模块，调用 Emscripten 并 smoke test。
6. `scripts/finalize-computations.mjs` 发布到
   `.ProofScript/resources/computation/<bundleHash>/`，将页面更新为 ready。
7. PS4HTML 发布 HTML 与计算资源。

支持代码现位于 `ProofScript/Page/Component/Computation.lean`。
manifest 中仍使用 `linking.mode = module-local` 标签；实际 builder 已有 C 符号依赖闭包选择。
该逻辑不等价于支持任意外部 FFI 或任意复杂 Lake workspace。

Finalize 必须在最后一次 Lean 编译之后执行；重编页面可能重新导出 pending。
`lake build MyLibrary:ps4html` 自动编排这些阶段（将 `MyLibrary` 替换为实际库名）。运行需匹配 Lean commit 的 Wasm runtime 和 Emscripten。

## ABI

输入和输出为 UTF-8 JSON。成功响应为 `{"ok":true,"value":...}`；失败为
`{"ok":false,"error":{"code":"...","message":"..."}}`。
Lean 解码/计算错误包括 invalid-json、invalid-input、computation-error；dispatcher 还返回 unknown-entry。

导出函数为 `proof_script_init`、`proof_script_alloc`、`proof_script_free`、`proof_script_invoke`。
调用参数包括 entry ID、输入字节和输出缓冲区；容量不足时按返回长度重新分配并再次调用。

## 浏览器实现

实际代码在 `tools/ps4html/PS4HTML/assets/js/computation.js`：

- 接受 `0.0.0` 组件、wasm backend 和 `proofscript-json-v1` ABI。
- pending 显示 fallback；ready 从本地 registry 选择 renderer。
- 读取 manifest/module/wasm，校验 SHA-256 和 byteSize。
- 专用 module Worker 内执行；按 module hash 复用客户端。
- 默认输入限制 64 KiB、输出限制 8 MiB、调用超时 2000 ms。
- 超时或取消终止 Worker；错误在页面显示。

注册接口：

```js
PS4HTMLComputation.register("example/calculator-v1", async ({ component, compute, element }) => {
  const result = await compute(component.payload.defaultInput);
  element.textContent = result.ok ? JSON.stringify(result.value) : result.error.message;
});
```

内置 Fibonacci、E8 root explorer/walk、公式实例 renderer。E8 explorer ID 为
`proofscript/e8-root-explorer-v2`；根坐标、计数和精确结果来自 Lean response，二维投影属于 UI。
通用 runtime 不提供任意 payload JSON Schema 插件校验；领域 renderer 自行检查其输入。

页面通过 HTTP(S) 发布，Wasm 使用 `application/wasm`，服务配置 COOP/COEP/CSP。
`ps4html serve` 提供这些响应头；跨设备 SharedArrayBuffer 使用要求受信任 HTTPS。
