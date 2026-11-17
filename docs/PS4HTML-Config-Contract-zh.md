# PS4HTML 项目配置契约

本文描述 `ps4html-config.toml` 的输入及语义。PS4HTML 在渲染时读取此文件；ProofScript 不再管理项目展示元数据。

## 职责与位置

PS4HTML 从当前 Lake 项目根目录读取唯一的 `ps4html-config.toml`，即与 `lakefile.lean` 或 `lakefile.toml` 同级的文件；不向父目录查找或合并依赖包的文件。所有 `lean_lib` 共用这份配置，不存在 library 或 module 覆盖表。ProofScript 编译、Info 固化、导出及其缓存不读取此文件；仅 PS4HTML 渲染和 `ps4html config check` 使用它。

没有配置文件或文件为空时使用默认值；已有文件无法读取、TOML 语法错误或字段不合法时报告错误，不回退到默认值。文件没有版本字段，也不进行配置格式的版本选择或迁移。

## 示例

最小文件可以是：

```toml
[site]
title = "Formal Mathematics Notes"
```

包含首版所有字段的示例：

```toml
[site]
title = "Formal Mathematics Notes"
authors = ["Alice", "Bob"]
keywords = ["Lean", "formal proofs"]
description = "Mathematical notes written with Lean and ProofScript."
year = "2026"
license = "CC-BY-4.0"
base_url = "https://example.org/notes/"

[site.extra]
edition = "First edition"

[render]
default_language = "en"
```

根表只允许 `site`、`render`；`[site]` 只允许下列元数据字段及 `extra`；`[render]` 首版只允许 `default_language`。未知字段或表（包括 `[libraries]`）报错，不能静默忽略。自定义元数据必须放入 `[site.extra]`。

## 字段与默认值

| 字段 | TOML 类型 | 缺省值与语义 |
| --- | --- | --- |
| `site.title` | 字符串 | 当前导出目标的 package 名；显式空字符串也回退至 package 名。所有 library 的项目标题一致。 |
| `site.authors` | 字符串数组 | `[]`；整体替换，无自动去重。 |
| `site.keywords` | 字符串数组 | `[]`；整体替换，无自动去重。 |
| `site.description` | 字符串 | `""`。 |
| `site.year` | 字符串 | `""`；可以表示年份或年份区间，不自动转换为整数。 |
| `site.license` | 字符串 | `""`；不强制 SPDX 标识符。 |
| `site.base_url` | 字符串 | `""`；不提供公开分享地址。 |
| `site.extra` | 键值表 | 空表；供引用等元数据展示使用。 |
| `render.default_language` | 字符串 | `"en"`；只接受 `"en"`、`"zh"`。 |

数组元素必须全部是字符串；不能把字符串自动包装为数组，也不能把整数自动转换成 `year`。`site.extra` 的值只允许 JSON 兼容的 TOML 字符串、布尔值、整数、有限浮点数、数组和表（可嵌套）；日期、时间和非有限浮点数报错。HTML 展示时对自定义键和值转义。TOML 没有 `null`，清空可选文本用空字符串，清空数组用 `[]`。

所有站点页面、库首页、目录页、模块页和引用中的**本 package** 项目元数据都来自同一份 `[site]`。库名称仍作为实际导出路径和链接身份，不是另一个配置层；引用中的外部 package 不套用当前站点的标题、作者或许可，缺少外部元数据时按构建身份回退。现有 `decl_info`、`theorem_info` 和 `script_info` 的模块视图及 imports 可见性保持原样。

## 公开地址

`site.base_url` 表示 `.PS4HTML/build/` 的公开部署根地址，而不是某一个 library 的地址。例如：

```text
site.base_url = "https://example.org/notes/"
package 首页    https://example.org/notes/index.html
Test 库首页    https://example.org/notes/Test/index.html
Test.A 页面    https://example.org/notes/Test/Test/A.html
```

配置值非空时须为绝对 `http` 或 `https` URL，包含主机名，不允许 query、fragment、用户名或密码；解析时规范化末尾的 `/`。从既有 HTML 输出路径计算公开地址，路径组件按 URL 规则编码；不得用 URL 解析器直接拼接未编码的模块名。空字符串禁用公开分享地址，不影响站内相对链接。页面的相对资源与导航路径继续由实际输出位置决定。

## 校验与生效时机

`ps4html config check` 在 Lake 项目根目录发现配置文件，完整解析并校验上述字段；文件缺失时成功并说明正在使用默认值。错误信息应包含文件路径和字段路径；TOML 语法错误还应包含解析器提供的位置。检查不需要 ProofScript 导出物，也不编译 Lean、不渲染 HTML。

PS4HTML 渲染时使用相同的读取和校验入口。修改 TOML 后，下次渲染生效，不改变 `.ProofScript` 导出内容；一轮 `make --cache` 的所有 library 共用一次配置快照。配置校验失败应发生在发布新 HTML 之前，保留已有成功输出。单模块目标继续使用现有 `.PS4HTML/build/<库名>/` 输出位置。

## 迁移边界

Lean `project_info`、`reset project_info`、`#preview project_info`、`ProjectInfo`、项目 Info 事件重绑定和 frozen project 记录已经移除。格式变化后应重新导出。原先按模块 imports 得到的不同项目元数据无法无损自动合并为全库统一配置，迁移时须为整站选定一份值。

Info 剩余的目标都是 Lean `Name`；项目专用的字符串 target 分支和没有业务调用的 context/renderer-dependency 注册机制已经移除。声明及脚本的事件、覆盖、冲突、reset、按需固化与依赖处理仍保留。构建所需的 `(package, library)` 归属身份继续保留，不作为项目元数据配置管理。
