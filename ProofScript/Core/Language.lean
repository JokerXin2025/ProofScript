/-
    ProofScript.Core.Language
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean

open Lean


namespace ProofScript

/-- A language with an English name, a local name, and a code. Includes the 100
Wikipedia languages with the most users (6 November 2026). Use `Language.custom`
to provide information for custom language. -/
inductive Language where
| en | es | fr | de | zh | ru | pt | it | ar | ja | tr | simple | id | pl | nl
| fa | he | vi | sv | ko | uk | hi | cs | ro | no | fi | hu | sr | ca | da | th
| bn | el | ms | bg | sh | hr | az | zh_yue | uz | sk | arz | ta | wuu | sl | eo
| et | lt | ur | af | la | ml | eu | sq | ku | ka | mr | bs | kk | gl | hy | be
| tl | tg | nn | ast | te | lv | ceb | my | ang | sco | mk | als | zh_classical
| is | ban | cy | mn | gan | kn | be_tarask | br | crh | an | sw | gu | bar | si
| ne | ckb | ga | zh_min_nan | jv | lb | war | oc | azb | nds | tly
| custom (englishName localName code : String)
deriving Inhabited, BEq

namespace Language

private def info : Language → String × String × String
| .en           => ("English", "English", "en")
| .es           => ("Spanish", "español", "es")
| .fr           => ("French", "français", "fr")
| .de           => ("German", "Deutsch", "de")
| .zh           => ("Chinese", "中文", "zh")
| .ru           => ("Russian", "русский", "ru")
| .pt           => ("Portuguese", "português", "pt")
| .it           => ("Italian", "italiano", "it")
| .ar           => ("Arabic", "العربية", "ar")
| .ja           => ("Japanese", "日本語", "ja")
| .tr           => ("Turkish", "Türkçe", "tr")
| .simple       => ("Simple English", "Simple English", "simple")
| .id           => ("Indonesian", "Bahasa Indonesia", "id")
| .pl           => ("Polish", "polski", "pl")
| .nl           => ("Dutch", "Nederlands", "nl")
| .fa           => ("Persian", "فارسی", "fa")
| .he           => ("Hebrew", "עברית", "he")
| .vi           => ("Vietnamese", "Tiếng Việt", "vi")
| .sv           => ("Swedish", "svenska", "sv")
| .ko           => ("Korean", "한국어", "ko")
| .uk           => ("Ukrainian", "українська", "uk")
| .hi           => ("Hindi", "हिन्दी", "hi")
| .cs           => ("Czech", "čeština", "cs")
| .ro           => ("Romanian", "română", "ro")
| .no           => ("Norwegian", "norsk", "no")
| .fi           => ("Finnish", "suomi", "fi")
| .hu           => ("Hungarian", "magyar", "hu")
| .sr           => ("Serbian", "српски / srpski", "sr")
| .ca           => ("Catalan", "català", "ca")
| .da           => ("Danish", "dansk", "da")
| .th           => ("Thai", "ไทย", "th")
| .bn           => ("Bangla", "বাংলা", "bn")
| .el           => ("Greek", "Ελληνικά", "el")
| .ms           => ("Malay", "Bahasa Melayu", "ms")
| .bg           => ("Bulgarian", "български", "bg")
| .sh           => ("Serbo-Croatian", "srpskohrvatski / српскохрватски", "sh")
| .hr           => ("Croatian", "hrvatski", "hr")
| .az           => ("Azerbaijani", "azərbaycanca", "az")
| .zh_yue       => ("Cantonese", "粵語", "zh-yue")
| .uz           => ("Uzbek", "oʻzbekcha / ўзбекча", "uz")
| .sk           => ("Slovak", "slovenčina", "sk")
| .arz          => ("Egyptian Arabic", "مصرى", "arz")
| .ta           => ("Tamil", "தமிழ்", "ta")
| .wuu          => ("Wu", "吴语", "wuu")
| .sl           => ("Slovenian", "slovenščina", "sl")
| .eo           => ("Esperanto", "Esperanto", "eo")
| .et           => ("Estonian", "eesti", "et")
| .lt           => ("Lithuanian", "lietuvių", "lt")
| .ur           => ("Urdu", "اردو", "ur")
| .af           => ("Afrikaans", "Afrikaans", "af")
| .la           => ("Latin", "Latina", "la")
| .ml           => ("Malayalam", "മലയാളം", "ml")
| .eu           => ("Basque", "euskara", "eu")
| .sq           => ("Albanian", "shqip", "sq")
| .ku           => ("Kurdish", "kurdî", "ku")
| .ka           => ("Georgian", "ქართული", "ka")
| .mr           => ("Marathi", "मराठी", "mr")
| .bs           => ("Bosnian", "bosanski", "bs")
| .kk           => ("Kazakh", "қазақша", "kk")
| .gl           => ("Galician", "galego", "gl")
| .hy           => ("Armenian", "հայերեն", "hy")
| .be           => ("Belarusian", "беларуская", "be")
| .tl           => ("Tagalog", "Tagalog", "tl")
| .tg           => ("Tajik", "тоҷикӣ", "tg")
| .nn           => ("Norwegian Nynorsk", "norsk nynorsk", "nn")
| .ast          => ("Asturian", "asturianu", "ast")
| .te           => ("Telugu", "తెలుగు", "te")
| .lv           => ("Latvian", "latviešu", "lv")
| .ceb          => ("Cebuano", "Cebuano", "ceb")
| .my           => ("Burmese", "မြန်မာဘာသာ", "my")
| .ang          => ("Old English", "Ænglisc", "ang")
| .sco          => ("Scots", "Scots", "sco")
| .mk           => ("Macedonian", "македонски", "mk")
| .als          => ("Alemannic", "Alemannisch", "als")
| .zh_classical => ("Literary Chinese", "文言", "zh-classical")
| .is           => ("Icelandic", "íslenska", "is")
| .ban          => ("Balinese", "Basa Bali", "ban")
| .cy           => ("Welsh", "Cymraeg", "cy")
| .mn           => ("Mongolian", "монгол", "mn")
| .gan          => ("Gan", "贛語", "gan")
| .kn           => ("Kannada", "ಕನ್ನಡ", "kn")
| .be_tarask    => ("Belarusian (Taraškievica orthography)",
                    "беларуская (тарашкевіца)", "be-tarask")
| .br           => ("Breton", "brezhoneg", "br")
| .crh          => ("Crimean Tatar", "qırımtatarca", "crh")
| .an           => ("Aragonese", "aragonés", "an")
| .sw           => ("Swahili", "Kiswahili", "sw")
| .gu           => ("Gujarati", "ગુજરાતી", "gu")
| .bar          => ("Bavarian", "Boarisch", "bar")
| .si           => ("Sinhala", "සිංහල", "si")
| .ne           => ("Nepali", "नेपाली", "ne")
| .ckb          => ("Central Kurdish", "کوردی", "ckb")
| .ga           => ("Irish", "Gaeilge", "ga")
| .zh_min_nan   => ("Minnan", "閩南語 / Bân-lâm-gí", "zh-min-nan")
| .jv           => ("Javanese", "Jawa", "jv")
| .lb           => ("Luxembourgish", "Lëtzebuergesch", "lb")
| .war          => ("Waray", "Winaray", "war")
| .oc           => ("Occitan", "occitan", "oc")
| .azb          => ("South Azerbaijani", "تۆرکجه", "azb")
| .nds          => ("Low German", "Plattdüütsch", "nds")
| .tly          => ("Talysh", "tolışi", "tly")
| .custom englishName localName code => (englishName, localName, code)

/-- The language's name in English. -/
def englishName (lang : Language) : String := lang.info.1

/-- The language's name in itself. -/
def localName (lang : Language) : String := lang.info.2.1

/-- The language's code in Wikipedia. -/
def code (lang : Language) : String := lang.info.2.2

end Language

instance : ToJson Language where
  toJson lang := toJson lang.code

end ProofScript
