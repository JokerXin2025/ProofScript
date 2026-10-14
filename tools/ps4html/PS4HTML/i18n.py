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
        "strategy.calculation": "计算",
        "strategy.inference": "推导",
        "strategy.contradiction_text": "假设结论不成立, 即{hypothesis}",
        "page.mobile_title": "请使用平板或电脑访问",
        "page.mobile_desc": "为了保证最佳阅读体验<br>本页面暂不支持窄屏浏览",
        "page.references": "参考文献",
        "page.reference_info": "文献信息",
        "page.module_directory": "模块目录",
        "page.current_location": "当前位置",
        "page.nearby_modules": "当前模块附近的项目树",
        "page.project_index": "查看完整项目索引",
        "page.project_home": "项目首页",
        "language.switch": "切换语言",
        "language.zh": "中文",
        "language.en": "English",
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
        "strategy.calculation": "By calculation,",
        "strategy.inference": "By inference,",
        "strategy.contradiction_text": "suppose the conclusion is false, namely {hypothesis}.",
        "page.mobile_title": "Please use a tablet or computer",
        "page.mobile_desc": "For the best reading experience,<br>narrow screens are not currently supported",
        "page.references": "References",
        "page.reference_info": "Reference information",
        "page.module_directory": "Module directory",
        "page.current_location": "Current location",
        "page.nearby_modules": "Project tree near the current module",
        "page.project_index": "View complete project index",
        "page.project_home": "Project home",
        "language.switch": "Switch language",
        "language.zh": "中文",
        "language.en": "English",
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
