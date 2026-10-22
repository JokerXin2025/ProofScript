"""Lean2TeX 变量分配器（对应原 `Variable.lean` + `VariableToml.lean`）。

为 Lean 表达式中的变量（fvar / bvar）分配**全局唯一、人类可读**的符号名。
命名策略与原设计三级优先级一致：

1. **名字池** —— 从 Lean `var_info` 导出的配置中按顺序选择（如 Real→x,y,z）；
2. **池耗尽回退** —— 使用 `{default}_{n}` 格式（如 x_1, n_8）；
3. **未知类型回退** —— 无该类型配置时使用 `{typeName}{n}`（如 Real1, Nat2）。

全局唯一性：`allocated` 列表跨类型共享——若 ℕ 先占了 `n`，ℤ 后续分配时 `n` 已被占，
自动跳过取池中下一个名字（与原 `Var_AllocatedNames` 语义一致）。

由于 Python 端每个渲染器需要独立的分配状态（原 Lean 用全局 `IO.Ref`），
这里用 `VariableAllocator` **实例**承载状态；`Expr2TeX` 渲染器持有一个实例，
`reset()` 对应原 `resetVarAllocator`（每个定理渲染开始前调用）。
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class VarTypeConfig:
    """一个类型的变量命名配置（对应原 `VarTypeConfig` structure）。

    - `name`：Lean 常量名，如 "Real"、"Nat"、"Int"；
    - `default`：池耗尽后的回退前缀；
    - `var_names`：按顺序取用的人类可读名字池。
    """
    name: str
    default: str
    var_names: list[str] = field(default_factory=list)


class VariableAllocator:
    """全局变量分配器（有状态，需在定理间 `reset()`）。"""

    def __init__(self, configs: list[VarTypeConfig] | None = None):
        self.configs: list[VarTypeConfig] = configs or []
        # 已分配名字集合（跨类型共享，保证无重名）
        self.allocated: list[str] = []
        # Naming depends on the occurrence's explicit declaration and category.
        # The same structural fvar ID may have different or absent Display hints.
        self.cache: dict[tuple[str, str | None, str, str | None], str] = {}

    # ─────────────────────────────────────────────────────────────────────────
    # 重置 / 释放
    # ─────────────────────────────────────────────────────────────────────────
    def reset(self) -> None:
        """清空分配器状态（对应 `resetVarAllocator`，每定理开头调用）。"""
        self.allocated.clear()
        self.cache.clear()

    def release_var(self, name: str) -> None:
        """归还名字（对应 `releaseVar`，局部作用域结束时调用）。"""
        if name in self.allocated:
            self.allocated.remove(name)

    def reserve(self, name: str) -> str:
        """Reserve a user-written name, adding a TeX subscript on shadowing."""
        candidate = name
        index = 1
        while candidate in self.allocated:
            candidate = f"{name}_{index}"
            index += 1
        if candidate:
            self.allocated.append(candidate)
        return candidate

    # ─────────────────────────────────────────────────────────────────────────
    # 查询配置
    # ─────────────────────────────────────────────────────────────────────────
    def find_config(self, type_name: str) -> VarTypeConfig | None:
        """查找类型配置（对应 `findTypeConfig`）。"""
        for cfg in self.configs:
            if cfg.name == type_name:
                return cfg
        return None

    # ─────────────────────────────────────────────────────────────────────────
    # 分配
    # ─────────────────────────────────────────────────────────────────────────
    def allocate_var(self, type_name: str) -> str:
        """为指定类型分配一个全局唯一的名字（对应 `allocateVar`）。

        三级策略：
        ① 有配置 → 遍历 `var_names` 池选第一个未被占用的；
        ② 池耗尽 → 回退 `{default}_{n}`；
        ③ 无配置 → 回退 `{type_name}{n}`。
        """
        cfg = self.find_config(type_name)
        if cfg is not None:
            for name in cfg.var_names:
                if name not in self.allocated:
                    self.allocated.append(name)
                    return name
            # ② 池耗尽 → {default}_{n}
            idx = 1
            fallback = f"{cfg.default}_{idx}"
            while fallback in self.allocated:
                idx += 1
                fallback = f"{cfg.default}_{idx}"
            self.allocated.append(fallback)
            return fallback
        else:
            # ③ 未知类型 → {type_name}{n}
            idx = 1
            fallback = f"{type_name}{idx}"
            while fallback in self.allocated:
                idx += 1
                fallback = f"{type_name}{idx}"
            self.allocated.append(fallback)
            return fallback

    def allocate_fvar(self, fvar_id: str, type_name: str, *,
                      display_name: str | None = None,
                      classification: str | None = None) -> str:
        """Reuse a name only for an equivalent occurrence naming context."""
        key = (fvar_id, display_name, type_name, classification)
        if key in self.cache:
            return self.cache[key]
        name = self.reserve(display_name) if display_name else self.allocate_var(type_name)
        self.cache[key] = name
        return name

    # ─────────────────────────────────────────────────────────────────────────
    # 类型节点 → 类型短名（对应 `typeExprToTypeStr`）
    # ─────────────────────────────────────────────────────────────────────────
    def type_to_name(self, type_node: dict | None) -> str:
        """从 JSON 类型节点提取短名，用于查找 `var_info` 命名配置。

        对应原 `typeExprToTypeStr`：
        - `.const cname` → 返回 `cname.toString`（如 "Real"、"Nat"）；
        - `.sort level.zero` → 返回 `"Prop"`（命题变量 `P : Prop` 走 Prop 名字池）；
        - `.sort level.succ` → 返回 `"Type"`（类型变量 `α : Type` 走 Type 名字池）；
        - `.forall` → `"Function"`，使用函数变量命名池；
        - 其他（如 `.app` 的 `Fin 5`、`P ∧ Q`）→ 返回空串。
        """
        if not isinstance(type_node, dict):
            return ""
        kind = type_node.get("kind")
        if kind == "const":
            return type_node.get("name", "")
        if kind == "sort":
            level = type_node.get("level", {})
            if isinstance(level, dict) and level.get("kind") == "level.zero":
                return "Prop"
            return "Type"
        if kind == "forall":
            return "Function"
        return ""
