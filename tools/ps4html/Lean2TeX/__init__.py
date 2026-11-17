"""Lean2TeX —— PS4HTML 页面生成器的 TeX 直译接口。

Lean2TeX 是 PS4HTML 的 Python 语义渲染模块。ProofScript 导出原生表达式与 MData 注解，
由文档根清单解析出具体表达式 occurrence，本模块将其转换为 DisplayTree，再渲染为 TeX：

    **接收已解析的表达式 occurrence，输出对应的 TeX 代码。**

渲染配置由 Lean 固化并按模块导出到 `.ProofScript/info/<模块路径>.json`。

典型用法（作为 PS4HTML 的接口）：

    from Lean2TeX import load

    renderer = load(export_root, proof_module)
    tex = renderer.render(node)                # node 由 ExpressionResolver 解析
    display = renderer.convert(node)
    tex = renderer.render_display(display)

每个页面模块拥有独立的最终配置视图。
每个定理渲染前应调用 `renderer.reset()` 清空变量分配状态。
"""

from __future__ import annotations

from .core import Expr2TeX, load
from .expr import flatten_app, unwrap_mdata
from .macros import MacroRegistry
from .model import DisplayNode, DisplayTemplate, Macro, TemplateInstruction, RenderTarget, Unwrap, RenderDiagnostic, RenderLimitError
from .semantic import SemanticConverter
from .variable import VariableAllocator

__all__ = [
    # 核心接口
    "Expr2TeX",
    "load",
    "DisplayNode",
    "RenderDiagnostic",
    "RenderLimitError",
    "SemanticConverter",
    "Macro",
    "TemplateInstruction",
    "DisplayTemplate",
    "RenderTarget",
    "Unwrap",
    "MacroRegistry",
    "flatten_app",
    "unwrap_mdata",
    # 变量系统
    "VariableAllocator",
]
