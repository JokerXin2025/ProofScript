# 嵌入式计算前端交接文档

本文面向页面渲染器和前端运行时维护者，描述如何消费 ProofScript finalized page JSON、加载
Lean/Wasm bundle，并将计算结果交给具体页面组件。

当前内置实现位于 `tools/ps4html/PS4HTML/assets/js/computation.js`，注册入口为
`PS4HTMLComputation.register`。本文 TypeScript/React 片段为下游接入参考，不表示内置实现使用 React。
component、pending 和 bundle 的 `schemaVersion` 仍为 `0.0.0`，执行 ABI 为 `proofscript-json-v1`。函数来源信息单独采用 `function.recordingVersion = "0.1.0"`；缺失或旧版本必须重新运行 `lake build MyLibrary:ps4html`。缓存读取不会迁移旧来源数据。

## 站点构建器职责

前端仓库或页面渲染器不只负责读取已经存在的 JSON。负责发布网站的 build pipeline 必须先编译
Lean/ProofScript 项目，再构建和 finalize 计算资源。标准入口会依次完成页面编译、Wasm 构建、finalize、Info 完成清单校验和站点发布：

```sh
# 配置与当前 Lean commit 匹配的 Wasm runtime，然后构建页面
PROOF_SCRIPT_LEAN_WASM_PREFIX=/path/to/lean-wasm-prefix \
  lake build MyLibrary:ps4html
```

普通 `lake build` 只验证证明，不产生页面录制。自定义管线也必须先执行页面模式编译，取得 page/pending/wrapper/C IR，再以同一 `PROOF_SCRIPT_OUTPUT_ROOT` 调用 `build-computations.mjs` 和 `finalize-computations.mjs`，最后生成完整 Info 清单。标准 facet 已处理这些步骤；发布输入位于 `.PS4HTML/inputs/<包>/<库>/.ProofScript/`。

渲染器的生产构建必须在任一步失败时失败，不能继续发布旧页面或静态 fallback 冒充成功。推荐在
部署前额外检查：

```sh
# 不应有要部署的 pending 页面；所有 ready 资源必须存在
node /path/to/ProofScript/scripts/test-finalized-computation.mjs \
  .PS4HTML/inputs/<包>/<库>/.ProofScript/pages/<page>.json
```

重要约束：

- `@computation` 在 Lean elaboration 时登记 wrapper，但模块 C IR 在 elaboration 完成后才写出，所以
  不能省略第一步，也不能在 command elaborator 中同步链接 Wasm。
- Lake 若复用未变化的 `.olean`，编译期文件副作用不一定重新执行。清空 `.ProofScript/` 后应确保
  页面模块被重新 elaboration，必要时使用项目自己的 clean/rebuild 流程。
- Finalize 之后若再次编译页面模块，`page_end` 会把页面重新写回 `pending`。发布流程中 finalize
  必须位于最后一次 Lean 编译之后。
- 只有 `.ProofScript/pages/` 和 `.ProofScript/resources/` 是前端部署输入；pending 和 bundles 是
  构建中间产物。
- `PROOF_SCRIPT_LEAN_WASM_PREFIX` 必须指向与项目 Lean commit 匹配的 Emscripten Lean runtime，
  不能指向 macOS/Linux 宿主 toolchain。

## 交付产物

一次完整后端构建产生：

```text
.ProofScript/pages/**/*.json
.ProofScript/resources/computation/<bundleHash>/bundle.json
.ProofScript/resources/computation/<bundleHash>/bundle.mjs
.ProofScript/resources/computation/<bundleHash>/bundle.wasm
.ProofScript/computations/index.json
```

前端渲染页面时只需要 page JSON 中的 computation component。全局 index 用于预加载、诊断和
构建检查，不是单页渲染的必需输入。

## 页面组件

Finalized component 示例：

```json
{
  "data": {
    "computation": {
      "value": {
         "schemaVersion": "0.0.0",
        "metadata": {
          "title": "Typed computation",
          "label": "typed-computation",
          "extra": []
        },
        "renderer": "proofscript/test-json-v1",
        "function": {
          "recordingVersion": "0.1.0",
          "declaration": "Demo.compute",
          "type": "Bool → Nat",
          "expression": {"$ref": "e0"},
          "implementation": {"$ref": "e3"},
          "expressions": {
            "e0": {"kind": "const", "name": "Demo.compute", "levels": []},
            "e1": {"kind": "const", "name": "Bool", "levels": []},
            "e2": {"kind": "lit", "lit": {"kind": "literal.nat", "value": 0}},
            "e3": {"kind": "lam", "name": "_", "type": {"$ref": "e1"},
              "body": {"$ref": "e2"}, "binderInfo": "default"}
          },
          "expressionRoots": [["expression"], ["implementation"]]
        },
        "execution": {
          "backend": "wasm",
          "status": "ready",
          "abi": "proofscript-json-v1",
          "bundleId": "Test.ComputationComponentTest",
          "entry": "Demo.compute",
          "wrapper": "__proofScript_compute",
          "manifest": {"$resource": {}},
          "module": {"$resource": {}},
          "wasm": {"$resource": {}}
        },
        "payload": {}
      }
    }
  }
}
```

字段职责：

| 字段 | 前端用途 |
| --- | --- |
| `renderer` | 从受信任 renderer registry 选择具体 UI |
| `metadata` | 标题、锚点和展示提示 |
| `function` | Lean 来源展示和审计，不由浏览器解释执行 |
| `execution.entry` | 调用同一 bundle 中的具体 Lean wrapper |
| `execution.module` | Emscripten ES module loader |
| `execution.wasm` | Lean 函数和 Lean runtime 的 Wasm 二进制 |
| `execution.manifest` | bundle entries 和产物元数据 |
| `payload` | renderer 专用初始配置、fallback 和领域数据 |

`function` 的根路径相对于函数对象，节点表不与 proof 或其他函数共用。可选的 `expression_display` / `implementation_display` 由生产者显式提供，其辅助表达式仍属于本图。Finalizer 只回填执行资源，保留全部 function 数据；来源字段不参与浏览器执行 ABI。

前端必须要求：

```text
execution.backend = wasm
execution.status = ready
execution.abi = proofscript-json-v1
```

遇到 `pending` 时不得尝试运行，应显示 fallback 或“计算资源尚未完成构建”。

## Resource 解析

资源描述：

```ts
export type ResourceRef = {
  $resource: {
    path: string;
    hash: string;
    mediaType: string;
    encoding: "utf-8" | "binary";
    byteSize?: number;
  };
};
```

`path` 相对于项目发布根目录，不相对于 page JSON URL。渲染器应由宿主传入统一的
`projectBaseUrl`：

```ts
function resourceUrl(base: URL, ref: ResourceRef): URL {
  return new URL(ref.$resource.path, base);
}
```

部署层必须允许访问以 `.ProofScript/` 开头的静态路径，并为 Wasm 返回：

```http
Content-Type: application/wasm
```

ES module 返回：

```http
Content-Type: text/javascript
```

## 完整性校验

ProofScript 当前使用 SHA-256 十六进制 hash。加载器至少在第一次使用一个 bundle 时校验
module、Wasm 和 manifest：

```ts
async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map(byte => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function fetchVerified(base: URL, ref: ResourceRef): Promise<ArrayBuffer> {
  const response = await fetch(resourceUrl(base, ref), {
    credentials: "same-origin",
    cache: "force-cache",
  });
  if (!response.ok) throw new Error(`resource load failed: ${response.status}`);
  const bytes = await response.arrayBuffer();
  if (ref.$resource.byteSize !== undefined && bytes.byteLength !== ref.$resource.byteSize) {
    throw new Error("resource byte size mismatch");
  }
  if (await sha256Hex(bytes) !== ref.$resource.hash) {
    throw new Error("resource SHA-256 mismatch");
  }
  return bytes;
}
```

校验 module 后再对原始 URL 执行 dynamic import 仍存在理论上的 TOCTOU 窗口。对于不可信 CDN，
推荐将已校验资源放入同源 Service Worker/Cache Storage，再从不可变 hash URL 导入。当前资源目录
本身以 module + Wasm 内容组合 hash 命名，正常静态部署应设置：

```http
Cache-Control: public, max-age=31536000, immutable
```

## Worker 边界

不要在页面主线程直接运行 Lean/Wasm。推荐每个 bundle 对应一个 Worker instance，多个 entry 共用
同一个 Lean runtime。

主线程消息：

```ts
export type WorkerRequest = {
  requestId: string;
  type: "invoke";
  entry: string;
  input: unknown;
};

export type WorkerResponse = {
  requestId: string;
  result?: ProofScriptResult<unknown>;
  transportError?: string;
};
```

Lean JSON 响应：

```ts
export type ProofScriptResult<T> =
  | { ok: true; value: T }
  | {
      ok: false;
      error: {
        code: "invalid-json" | "invalid-input" | "computation-error" | "unknown-entry" | string;
        message: string;
      };
    };
```

## Emscripten 模块加载

Worker 初始化输入应包含 finalized execution 和 project base URL。初始化步骤：

```ts
async function loadBundle(base: URL, execution: ReadyExecution) {
  await Promise.all([
    fetchVerified(base, execution.manifest),
    fetchVerified(base, execution.module),
    fetchVerified(base, execution.wasm),
  ]);

  const moduleUrl = resourceUrl(base, execution.module);
  const wasmUrl = resourceUrl(base, execution.wasm);
  const factory = (await import(/* @vite-ignore */ moduleUrl.href)).default;
  const instance = await factory({
    locateFile(path: string) {
      return path.endsWith(".wasm") ? wasmUrl.href : new URL(path, moduleUrl).href;
    },
  });
  instance._proof_script_init();
  return instance;
}
```

Vite/Webpack 等 bundler 必须保留 runtime URL，不要试图在前端构建期解析该动态 import。

## Wasm 调用 ABI

导出函数：

```ts
type ProofScriptWasm = {
  HEAPU8: Uint8Array;
  _proof_script_init(): void;
  _proof_script_alloc(size: number): number;
  _proof_script_free(pointer: number): void;
  _proof_script_invoke(
    entryPointer: number,
    entryLength: number,
    inputPointer: number,
    inputLength: number,
    outputPointer: number,
    outputCapacity: number,
  ): number;
};
```

调用实现：

```ts
function invoke(instance: ProofScriptWasm, entry: string, input: unknown) {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const entryBytes = encoder.encode(entry);
  const inputBytes = encoder.encode(JSON.stringify(input));
  const entryPointer = instance._proof_script_alloc(entryBytes.length);
  const inputPointer = instance._proof_script_alloc(inputBytes.length);
  instance.HEAPU8.set(entryBytes, entryPointer);
  instance.HEAPU8.set(inputBytes, inputPointer);

  let capacity = 64 * 1024;
  let outputPointer = instance._proof_script_alloc(capacity);
  try {
    let length = instance._proof_script_invoke(
      entryPointer,
      entryBytes.length,
      inputPointer,
      inputBytes.length,
      outputPointer,
      capacity,
    );
    if (length > capacity) {
      instance._proof_script_free(outputPointer);
      capacity = length;
      outputPointer = instance._proof_script_alloc(capacity);
      length = instance._proof_script_invoke(
        entryPointer,
        entryBytes.length,
        inputPointer,
        inputBytes.length,
        outputPointer,
        capacity,
      );
    }
    const text = decoder.decode(instance.HEAPU8.slice(outputPointer, outputPointer + length));
    return JSON.parse(text) as ProofScriptResult<unknown>;
  } finally {
    instance._proof_script_free(entryPointer);
    instance._proof_script_free(inputPointer);
    instance._proof_script_free(outputPointer);
  }
}
```

当前 ABI 在输出缓冲区过小时会重新执行一次 Lean 函数。前端应设置合理初始容量，且在正式处理昂贵
计算前推动后端升级为 result-handle ABI。

## 超时与取消

同步 Wasm 调用无法通过 `Promise.race` 中止。主线程必须在超时后直接终止 Worker：

```ts
const timer = setTimeout(() => {
  worker.terminate();
  reject(new Error("computation timed out"));
}, timeoutMs);
```

终止后丢弃该 bundle instance，并按需创建新 Worker。不要尝试复用被终止 Worker 的 memory。

推荐默认限制：

| 限制 | 初始建议 |
| --- | ---: |
| 输入 JSON | 64 KiB |
| 输出 JSON | 8 MiB |
| 单次计算 | 2 秒 |
| 同 bundle 并发 | Worker 内串行 |
| Worker 缓存 | 每 bundleHash 一个 |

## Renderer Registry

`renderer` 只是受信任 registry key，不能当作 URL：

```ts
type RendererProps = {
  component: ComputationValue;
  compute<TInput, TOutput>(input: TInput): Promise<ProofScriptResult<TOutput>>;
};

const renderers = new Map<string, () => Promise<ComputationRenderer>>([
  ["proofscript/e8-root-explorer-v2", loadE8Renderer],
]);
```

页面渲染流程：

1. 渲染 metadata title 和 payload fallback。
2. 检查 execution status 和 ABI。
3. 按 bundleHash 取得或创建 Worker client。
4. 按 renderer ID 加载受信任 UI。
5. 将绑定了 `execution.entry` 的 `compute` 函数传给 UI。
6. UI 只提交领域输入并消费 typed output，不直接操作 Wasm memory。

未知 renderer 时保留 fallback，不执行 payload 中的任意代码。

## React 接入形态

建议将 transport 与具体 UI 分离：

```tsx
function ComputationBlock({ value }: { value: ComputationValue }) {
  const runtime = useComputationRuntime(value.execution);
  const Renderer = useTrustedRenderer(value.renderer);

  if (value.execution.status !== "ready") {
    return <ComputationFallback value={value} reason="pending" />;
  }
  if (!Renderer) {
    return <ComputationFallback value={value} reason="unknown-renderer" />;
  }
  return (
    <Renderer
      component={value}
      compute={input => runtime.invoke(value.execution.entry, input)}
    />
  );
}
```

组件卸载时用 `AbortSignal` 取消调用等待；若实际计算已经开始且需要强制取消，则终止 Worker。

## E8 Renderer 输入输出

内置 `proofscript/e8-root-explorer-v2` 已消费结构化请求/响应。请求字段为 family、projection
以及可选有理半径；具体编码见 `tools/ps4html/PS4HTML/assets/js/e8-computation.js`。
以下仅列响应中 UI 使用的部分字段，不替代领域后端的完整协议：

```ts
type E8Request = {
  family: "integral" | "halfIntegral" | "all";
  projection: "coxeterPlane" | { coordinates: { x: number; y: number } };
  radius?: { numerator: number; denominator: number };
};

type E8Response = {
  roots: Array<{
    numerators: number[];
    denominator: number;
    family: "integral" | "halfIntegral";
  }>;
  integralCount: number;
  halfIntegralCount: number;
  totalCount: number;
  selectedCount: number;
  normSquared: number;
  radiusAdmissible?: boolean;
  "radiusAdmissible?"?: boolean;
};
```

E8 UI 应实现根族切换、精确坐标检查、二维投影和密度视图。所有计数和根枚举来自 `compute`，前端
不得再次硬编码 `112`、`128` 或 `240`。payload 只用于初始视图、文字说明和静态 fallback。

## 安全与部署检查表

- 在专用 Worker 中运行 Wasm。
- 校验 module、Wasm 和 manifest SHA-256。
- 限制输入、输出、运行时间和 Worker 数量。
- 不启用 WASI、文件系统或网络 imports。
- 不使用 `eval`、`new Function` 或 payload 脚本。
- renderer ID 只通过本地 registry 解析。
- 资源路径只相对于受信任 project base URL。
- 设置 `.wasm` 正确 MIME type。
- 对 hash 资源设置 immutable cache。
- 当前 pthread build 要求 cross-origin isolation。

所需响应头：

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Content-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; worker-src 'self' blob:
```

实际 CSP 可根据是否使用 blob Worker 收紧。

## 错误展示

| 错误 | UI 行为 |
| --- | --- |
| `invalid-json` | transport bug，记录诊断并显示组件错误 |
| `invalid-input` | 表单或 renderer schema bug，展示字段错误 |
| `computation-error` | 展示 Lean 业务错误，不崩溃页面 |
| `unknown-entry` | 页面与 bundle 不一致，视为部署错误 |
| hash mismatch | 拒绝执行，视为资源完整性错误 |
| timeout | 终止 Worker，允许用户重试 |
| unknown renderer | 显示 fallback |

## 后端构建命令

以下命令与文档开头“站点构建器职责”相同，保留在此作为部署检查表：

```sh
# 1. Lean 页面编译，产生 pending manifests 和 C IR
lake build

# 2. 多入口 Wasm bundle
PROOF_SCRIPT_LEAN_WASM_PREFIX=/path/to/lean-wasm-prefix \
  node /path/to/ProofScript/scripts/build-computations.mjs

# 3. 内容寻址发布和页面回填
node /path/to/ProofScript/scripts/finalize-computations.mjs
```

前端只应部署 finalize 之后的 pages 和 resources，不应部署 `computations/pending` 或 bundles 中间目录。
