import html

from pygments.lexers import get_lexer_by_name
from pygments.token import Comment, Error, Generic, Keyword, Name, Number, Operator, Punctuation, String
from pygments.util import ClassNotFound


LANGUAGE_ALIASES = {
    "lean4": "lean",
    "py": "python",
    "js": "javascript",
    "ts": "typescript",
    "sh": "bash",
}

TOKEN_CLASSES = (
    (Comment, "code-comment"),
    (Keyword.Type, "code-type"),
    (Keyword, "code-keyword"),
    (Name.Builtin, "code-builtin"),
    (Name.Function, "code-function"),
    (Name.Class, "code-type"),
    (Name.Decorator, "code-attribute"),
    (Name.Namespace, "code-namespace"),
    (Name.Constant, "code-constant"),
    (Name.Tag, "code-tag"),
    (Name.Attribute, "code-attribute"),
    (String, "code-string"),
    (Number, "code-number"),
    (Operator, "code-operator"),
    (Punctuation, "code-punctuation"),
    (Generic.Heading, "code-heading"),
    (Generic.Subheading, "code-heading"),
    (Generic.Emph, "code-emphasis"),
    (Generic.Strong, "code-strong"),
    (Generic.Inserted, "code-inserted"),
    (Generic.Deleted, "code-deleted"),
    (Error, "code-error"),
)


def highlight_code(source: str, language: str, theme: str = "dark") -> tuple[str, bool]:
    if not language or get_lexer_by_name is None:
        return html.escape(source), False
    try:
        alias = language.strip().lower()
        lexer = get_lexer_by_name(LANGUAGE_ALIASES.get(alias, alias))
        rendered = []
        for _index, token_type, value in lexer.get_tokens_unprocessed(source):
            escaped = html.escape(value)
            token_class = _token_class(token_type)
            css_class = f"{token_class} code-theme-{theme}" if token_class else None
            rendered.append(f'<span class="{css_class}">{escaped}</span>' if css_class else escaped)
        return "".join(rendered), True
    except (ClassNotFound, ValueError):
        return html.escape(source), False


def _token_class(token_type) -> str | None:
    for parent, token_class in TOKEN_CLASSES:
        if token_type in parent:
            return token_class
    return None
