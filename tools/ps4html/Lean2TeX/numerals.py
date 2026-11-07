"""Render natural literals without converting the whole decimal input to an int."""

from .builtin_styles import NUMERAL_SYSTEMS


_UNITS = ("", "万", "亿", "兆", "京", "垓", "秭", "穰", "沟", "涧", "正", "载")
_TRAD_UNITS = ("", "萬", "億", "兆", "京", "垓", "秭", "穰", "溝", "澗", "正", "載")
_GREEK = ("", "α", "β", "γ", "δ", "ε", "ϛ", "ζ", "η", "θ")
_GREEK_TENS = ("", "ι", "κ", "λ", "μ", "ν", "ξ", "ο", "π", "ϟ")
_GREEK_HUNDREDS = ("", "ρ", "σ", "τ", "υ", "φ", "χ", "ψ", "ω", "ϡ")


def signed_decimal_digits(value: int) -> str:
    """Encode any JSON integer without Python's int-to-string digit limit."""
    if type(value) is not int:
        raise ValueError("Expected an integer")
    negative = value < 0
    value = abs(value)
    try:
        digits = str(value)
    except ValueError:
        chunks = []
        base = 10 ** 1000
        while value:
            value, remainder = divmod(value, base)
            chunks.append(str(remainder).zfill(1000) if value else str(remainder))
        digits = "".join(reversed(chunks)) or "0"
    return "-" + digits if negative else digits


def decimal_digits(value: int | str) -> str:
    """Accept a native natural literal or a losslessly parsed decimal token."""
    if type(value) is int:
        if value < 0:
            raise ValueError("Natural literal must not be negative")
        return signed_decimal_digits(value)
    if not isinstance(value, str) or not value or not value.isascii() or not value.isdecimal() or (len(value) > 1 and value[0] == "0"):
        raise ValueError("Invalid natural literal decimal digits")
    return value


def _chinese_group(group: str, *, leading_ten: bool = False) -> str:
    digits = "零一二三四五六七八九"
    places = ("千", "百", "十", "")
    text = ""
    gap = False
    for char, unit in zip(group.zfill(4), places):
        digit = ord(char) - 48
        if digit:
            if gap and text:
                text += "零"
            if not (leading_ten and not text and unit == "十" and digit == 1):
                text += digits[digit]
            text += unit
            gap = False
        else:
            gap = True
    return text


def _chinese(value: str, traditional: bool) -> str:
    units = _TRAD_UNITS if traditional else _UNITS
    groups = []
    while value:
        groups.append(value[-4:])
        value = value[:-4]
    out = ""
    pending_zero = False
    for index in range(len(groups) - 1, -1, -1):
        group = groups[index]
        if int(group) == 0:
            pending_zero = bool(out)
            continue
        if out and (pending_zero or int(group) < 1000):
            out += "零"
        out += _chinese_group(group, leading_ten=not out) + units[index]
        pending_zero = False
    return out or "零"


def _greek(value: str) -> str:
    digits = value.zfill(4)
    thousands, hundreds, tens, ones = (ord(char) - 48 for char in digits)
    return ("͵" + _GREEK[thousands] if thousands else "") + _GREEK_HUNDREDS[hundreds] + _GREEK_TENS[tens] + _GREEK[ones] + "ʹ"


def _roman(value: str) -> str:
    digits = value.zfill(4)
    places = (
        ("", "M", "MM", "MMM"),
        ("", "C", "CC", "CCC", "CD", "D", "DC", "DCC", "DCCC", "CM"),
        ("", "X", "XX", "XXX", "XL", "L", "LX", "LXX", "LXXX", "XC"),
        ("", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"),
    )
    return r"\mathrm{" + "".join(place[ord(digit) - 48] for place, digit in zip(places, digits)) + "}"


def numeral_styles(value: int | str) -> dict[str, str]:
    digits = decimal_digits(value)
    result = {}
    for system in NUMERAL_SYSTEMS:
        maximum = system.maximum_decimal
        if digits == "0":
            result[system.label] = system.zero
            continue
        if maximum is not None and (len(digits) > len(maximum) or (len(digits) == len(maximum) and digits > maximum)):
            rendered = (_greek(maximum) if system.label == "greek-ionian" else
                        _roman(maximum) if system.label == "roman" else
                        _chinese(maximum, system.label == "chinese-traditional"))
            result[system.label] = ">" + rendered
        elif system.label == "decimal":
            result[system.label] = digits
        elif system.label == "greek-ionian":
            result[system.label] = _greek(digits)
        elif system.label == "roman":
            result[system.label] = _roman(digits)
        else:
            result[system.label] = _chinese(digits, system.label == "chinese-traditional")
    return result
