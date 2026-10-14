# 嵌入式计算前端快速示例

仓库提供一个独立的 Fibonacci 示例：

```text
Test/EmbeddedComputationDemo.lean
```

它适合验证前端 renderer 的完整效果，因为同时包含：

- typed JSON 输入 `{ n : Nat }`。
- Lean/Wasm 递归计算。
- 结构化响应。
- 可视化序列数据。
- `n > 40` 的业务错误。
- 页面标题、fallback 和 range control metadata。

## Lean 入口

```lean
structure FibonacciRequest where
  n : Nat
deriving Lean.FromJson, Lean.ToJson

structure FibonacciResponse where
  n : Nat
  value : Nat
  sequence : Array Nat
deriving Lean.FromJson, Lean.ToJson

def computeFibonacci
    (request : FibonacciRequest) :
    Except String FibonacciResponse := ...
```

组件 renderer ID：

```text
proofscript/fibonacci-calculator-v1
```

entry：

```text
computeFibonacci
```

## 构建

```sh
# 在 ProofScript 仓库根目录安装站点工具
python3 -m pip install -e ./tools/ps4html
# 先按本机安装位置激活 Emscripten
export PROOF_SCRIPT_LEAN_WASM_PREFIX=/path/to/matching/lean-wasm-prefix
# 构建、导出、编译 Wasm、finalize 和渲染
lake build Test:ps4html
ps4html serve
```

Finalized 页面：

```text
.PS4HTML/inputs/ProofScript/Test/.ProofScript/pages/Test/EmbeddedComputationDemo.json
```

## 不写前端也能先测试

```sh
node scripts/invoke-finalized-computation.mjs \
  .PS4HTML/inputs/ProofScript/Test/.ProofScript/pages/Test/EmbeddedComputationDemo.json \
  computeFibonacci \
  '{"n":10}'
```

预期：

```json
{
  "ok": true,
  "value": {
    "n": 10,
    "value": 55,
    "sequence": [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
  }
}
```

错误测试：

```sh
node scripts/invoke-finalized-computation.mjs \
  .PS4HTML/inputs/ProofScript/Test/.ProofScript/pages/Test/EmbeddedComputationDemo.json \
  computeFibonacci \
  '{"n":41}'
```

预期错误代码：

```text
computation-error
```

错误消息：

```text
n must not exceed 40
```

## 内置前端 UI

`tools/ps4html/PS4HTML/assets/js/fibonacci-computation.js` 已提供：

1. `0..40` 的 range slider。
2. 当前 `F(n)` 大号数字。
3. `sequence` 的柱状图或折线图。
4. Wasm 调用耗时。
5. Loading、timeout 和 Lean error 状态。

payload 中已有：

```json
{
  "defaultInput": {"n": 10},
  "controls": {
    "n": {
      "kind": "range",
      "min": 0,
      "max": 40,
      "step": 1
    }
  },
  "views": ["value", "sequence-bars", "timing"]
}
```

前端应把 payload 当作 UI 配置，把实际结果完全交给 Lean/Wasm。

## Renderer 注册

```ts
PS4HTMLComputation.register("my-project/fibonacci-v1", async ({ compute, element }) => {
  const result = await compute({ n: 10 });
  element.textContent = result.ok ? String(result.value.value) : result.error.message;
});
```

Renderer 的领域接口：

```ts
type FibonacciRequest = { n: number };

type FibonacciResponse = {
  n: number;
  value: number;
  sequence: number[];
};
```

调用：

```ts
const result = await compute<FibonacciRequest, FibonacciResponse>({ n });
if (result.ok) {
  renderValue(result.value.value);
  renderBars(result.value.sequence);
} else {
  renderError(result.error.message);
}
```

底层 Worker、资源校验和 Wasm ABI 请直接参照：

```text
docs/Frontend-Computation-Handoff-zh.md
```
