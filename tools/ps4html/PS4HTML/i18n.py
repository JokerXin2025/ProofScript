"""Shared language selection and small UI/strategy translations."""

from __future__ import annotations

import html


SUPPORTED_LANGUAGES = ("zh", "en")
DEFAULT_LANGUAGE = "zh"

TRANSLATIONS = {
    "zh": {
        "proof.indent_title": "调整当前证明的层级缩进",
        "proof.indent_label": "证明缩进",
        "proof.source_title": "查看 Lean 源代码",
        "proof.lines": "行",
        "strategy.induction": "数学归纳法",
        "strategy.complete_induction": "强数学归纳法",
        "strategy.induction_object": "归纳对象",
        "strategy.base_case": "基础情形",
        "strategy.inductive_step": "归纳步骤",
        "strategy.cases": "分类讨论",
        "strategy.case_basis": "分类依据",
        "strategy.case": "情形 {case}",
        "strategy.contradiction": "反证法",
        "strategy.assumption": "假设",
        "strategy.have": "我们有",
        "strategy.decompose": "目标拆解",
        "strategy.unknown": "未知策略",
        "script.unrecorded": "未导出数据",
        "strategy.calculation": "计算",
        "strategy.inference": "推导",
        "strategy.contradiction_text": "假设结论不成立, 即{hypothesis}",
        "page.mobile_title": "请使用平板或电脑访问",
        "page.mobile_desc": "为了保证最佳阅读体验<br>本页面暂不支持窄屏浏览",
        "page.references": "参考文献",
        "page.reference_info": "文献信息",
        "page.module_directory": "模块目录",
        "page.resize_sidebar": "调整侧栏宽度",
        "page.current_location": "当前位置",
        "page.nearby_modules": "当前模块附近的项目树",
        "page.project_index": "查看完整项目索引",
        "page.project_home": "项目首页",
        "language.switch": "切换语言",
        "language.zh": "中文",
        "language.en": "English",
        "display_options.label": "显示选项",
        "display_options.wrappers": "展示工程细节",
        "expression.title.freeVariable": "自由变量",
        "expression.title.boundVariable": "绑定变量",
        "expression.title.binder": "绑定子",
        "expression.title.unknownVariable": "未知变量",
        "expression.title.universe": "类型宇宙",
        "expression.title.localDefinition": "局部定义",
        "expression.title.constant": "常量",
        "expression.title.lambda": "λ函数",
        "expression.title.implication": "蕴涵式",
        "expression.title.forall": "全称量词",
        "expression.title.exists": "存在量词",
        "expression.title.number": "数字",
        "expression.title.string": "字符串",
        "expression.title.projection": "投影",
        "expression.title.application": "应用",
        "expression.title.operator": "运算符",
        "expression.title.relation": "关系",
        "expression.title.wrapper": "包装器",
        "expression.title.expression": "表达式",
        "expression.field.display": "显示名称",
        "expression.field.literal": "内容",
        "expression.field.expression": "表达式",
        "expression.field.type": "类型",
        "expression.field.variableKind": "变量类别",
        "expression.field.value": "定义值",
        "expression.field.index": "de Bruijn 索引",
        "expression.field.binderInfo": "绑定方式",
        "expression.field.binderKind": "绑定所属表达式",
        "expression.field.level": "宇宙层级",
        "expression.field.leanName": "Lean 中的声明名",
        "expression.field.declarationKind": "声明类别",
        "expression.field.declarationType": "声明类型",
        "expression.field.argumentCount": "参数数量",
        "expression.field.ownerType": "所属类型",
        "expression.field.fieldIndex": "字段索引",
        "expression.field.rawData": "原始数据",
        "expression.empty": "暂无可展示的信息",
        "expression.value.parameter": "参数",
        "expression.value.let": "局部定义",
        "expression.value.default": "显式参数",
        "expression.value.implicit": "隐式参数",
        "expression.value.strictImplicit": "严格隐式参数",
        "expression.value.instImplicit": "类型类实例",
        "expression.value.forall": "全称量词",
        "expression.value.lam": "λ函数",
        "expression.value.axiom": "公理",
        "expression.value.definition": "定义",
        "expression.value.theorem": "定理",
        "expression.value.opaque": "不透明定义",
        "expression.value.quotient": "商类型",
        "expression.value.inductive": "归纳类型",
        "expression.value.constructor": "构造子",
        "expression.value.recursor": "递归器",
    },
    "en": {
        "proof.indent_title": "Adjust the nesting indentation of this proof",
        "proof.indent_label": "Proof indentation",
        "proof.source_title": "View Lean source code",
        "proof.lines": "lines",
        "strategy.induction": "By induction,",
        "strategy.complete_induction": "By strong induction,",
        "strategy.induction_object": "On the induction variable,",
        "strategy.base_case": "In the base case,",
        "strategy.inductive_step": "In the inductive step,",
        "strategy.cases": "By cases,",
        "strategy.case_basis": "As the case distinction,",
        "strategy.case": "In Case {case},",
        "strategy.contradiction": "By contradiction,",
        "strategy.assumption": "For the contrary assumption,",
        "strategy.have": "In particular,",
        "strategy.decompose": "To decompose the goal,",
        "strategy.unknown": "For an unknown strategy,",
        "script.unrecorded": "Data not exported",
        "strategy.calculation": "By calculation,",
        "strategy.inference": "By inference,",
        "strategy.contradiction_text": "suppose the conclusion is false, namely {hypothesis}.",
        "page.mobile_title": "Please use a tablet or computer",
        "page.mobile_desc": "For the best reading experience,<br>narrow screens are not currently supported",
        "page.references": "References",
        "page.reference_info": "Reference information",
        "page.module_directory": "Module directory",
        "page.resize_sidebar": "Resize sidebar",
        "page.current_location": "Current location",
        "page.nearby_modules": "Project tree near the current module",
        "page.project_index": "View complete project index",
        "page.project_home": "Project home",
        "language.switch": "Switch language",
        "language.zh": "中文",
        "language.en": "English",
        "display_options.label": "Display options",
        "display_options.wrappers": "Show technical details",
        "expression.title.freeVariable": "Free variable",
        "expression.title.boundVariable": "Bound variable",
        "expression.title.binder": "Binder",
        "expression.title.unknownVariable": "Unknown variable",
        "expression.title.universe": "Type universe",
        "expression.title.localDefinition": "Local definition",
        "expression.title.constant": "Constant",
        "expression.title.lambda": "Lambda function",
        "expression.title.implication": "Implication",
        "expression.title.forall": "Universal quantifier",
        "expression.title.exists": "Existential quantifier",
        "expression.title.number": "Number",
        "expression.title.string": "String",
        "expression.title.projection": "Projection",
        "expression.title.application": "Application",
        "expression.title.operator": "Operator",
        "expression.title.relation": "Relation",
        "expression.title.wrapper": "Wrapper",
        "expression.title.expression": "Expression",
        "expression.field.display": "Displayed name",
        "expression.field.literal": "Value",
        "expression.field.expression": "Expression",
        "expression.field.type": "Type",
        "expression.field.variableKind": "Variable kind",
        "expression.field.value": "Definition value",
        "expression.field.index": "de Bruijn index",
        "expression.field.binderInfo": "Binder style",
        "expression.field.binderKind": "Binding expression",
        "expression.field.level": "Universe level",
        "expression.field.leanName": "Lean declaration name",
        "expression.field.declarationKind": "Declaration kind",
        "expression.field.declarationType": "Declaration type",
        "expression.field.argumentCount": "Number of arguments",
        "expression.field.ownerType": "Owning type",
        "expression.field.fieldIndex": "Field index",
        "expression.field.rawData": "Raw data",
        "expression.empty": "No information available",
        "expression.value.parameter": "Parameter",
        "expression.value.let": "Local definition",
        "expression.value.default": "Explicit parameter",
        "expression.value.implicit": "Implicit parameter",
        "expression.value.strictImplicit": "Strict implicit parameter",
        "expression.value.instImplicit": "Typeclass instance",
        "expression.value.forall": "Universal quantifier",
        "expression.value.lam": "Lambda function",
        "expression.value.axiom": "Axiom",
        "expression.value.definition": "Definition",
        "expression.value.theorem": "Theorem",
        "expression.value.opaque": "Opaque definition",
        "expression.value.quotient": "Quotient",
        "expression.value.inductive": "Inductive type",
        "expression.value.constructor": "Constructor",
        "expression.value.recursor": "Recursor",
    },
}


def normalize_language(language: str | None) -> str:
    return language if language in SUPPORTED_LANGUAGES else DEFAULT_LANGUAGE


def language_fallbacks(language: str | None) -> tuple[str, ...]:
    language = normalize_language(language)
    return (language,) + tuple(item for item in SUPPORTED_LANGUAGES if item != language)


def tr(key: str, language: str | None = None, **values) -> str:
    for candidate in language_fallbacks(language):
        value = TRANSLATIONS.get(candidate, {}).get(key)
        if value is not None:
            return value.format(**values)
    return key


def localized(text: str | dict[str, str], language: str | None = None) -> str:
    if isinstance(text, str):
        return text
    for candidate in language_fallbacks(language):
        if isinstance(text.get(candidate), str):
            return text[candidate]
    return ""


def language_spans(values: dict[str, str]) -> str:
    return "".join(
        f'<span class="language-text" data-language="{html.escape(language, quote=True)}">{value}</span>'
        for language, value in values.items()
    )
