"""Parse native JSON integers beyond Python's decimal conversion guard."""

import json


def _integer(token: str) -> int:
    try:
        return int(token)
    except ValueError:
        negative = token.startswith("-")
        digits = token[1:] if negative else token
        number = 0
        for offset in range(0, len(digits), 1000):
            chunk = digits[offset:offset + 1000]
            number = number * (10 ** len(chunk)) + int(chunk)
        return -number if negative else number


def loads(content: str, **kwargs):
    return json.loads(content, parse_int=_integer, **kwargs)
