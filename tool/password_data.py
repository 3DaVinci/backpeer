#!/usr/bin/env python3
"""Данные для оценки стойкости пароля (задача 2.4.4, crypto.md, раздел 4.3).

Записывает два файла Dart в packages/core/lib/src/password/:

- dictionaries.g.dart — словари с рангами: списки zxcvbn 4.4.2 (MIT,
  Dan Wheeler и Dropbox; файл src/frequency_lists.coffee закреплённого
  коммита, SHA-256 проверяется) и русский список tool/password-ru.txt
  с транслитерацией;
- unicode.g.dart — диапазоны кодов, которые пароль содержать не может:
  не назначенные в Unicode версии модуля unicodedata (Cn), управляющие
  (Cc) и суррогаты (Cs).

Запуск из корня репозитория:

    python3 -I tool/password_data.py [<frequency_lists.coffee>]

Без аргумента файл скачивается с GitHub. Версия Unicode — та, что в
Python, которым запущен скрипт; она записывается в unicode.g.dart.
"""

import hashlib
import os
import re
import sys
import unicodedata
import urllib.request

ZXCVBN_COMMIT = "67c4ece9efc40c9d0a1d7d995b2b22a91be500c2"
ZXCVBN_URL = (
    "https://raw.githubusercontent.com/dropbox/zxcvbn/"
    f"{ZXCVBN_COMMIT}/src/frequency_lists.coffee"
)
ZXCVBN_SHA256 = "664d32190713e42b7726072a5cf7533bd4a469e5588c7c1bd2ff9485cdf83276"
# Порядок словарей zxcvbn сохраняется: от него зависит, какой словарь
# выигрывает при равном ранге.
ZXCVBN_LISTS = [
    "passwords",
    "english_wikipedia",
    "female_names",
    "surnames",
    "us_tv_and_film",
    "male_names",
]
RU_LIST = os.path.join("tool", "password-ru.txt")
OUT_DIR = os.path.join("packages", "core", "lib", "src", "password")

TRANSLIT = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e",
    "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "h", "ц": "c", "ч": "ch", "ш": "sh", "щ": "sch",
    "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
}


def load_zxcvbn(path):
    if path is None:
        with urllib.request.urlopen(ZXCVBN_URL, timeout=60) as r:
            data = r.read()
    else:
        with open(path, "rb") as f:
            data = f.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != ZXCVBN_SHA256:
        sys.exit(f"frequency_lists.coffee: SHA-256 {digest}, ждали {ZXCVBN_SHA256}")
    text = data.decode("utf-8")
    lists = dict(re.findall(r'^\s*(\w+): "([^"]*)"', text, re.M))
    assert list(lists) == ZXCVBN_LISTS, list(lists)
    return {name: lists[name].split(",") for name in ZXCVBN_LISTS}


def load_russian():
    words = []
    with open(RU_LIST, encoding="utf-8") as f:
        for line in f:
            w = line.strip().lower()
            if not w or w.startswith("#"):
                continue
            assert re.fullmatch(r"[а-яё]+", w), w
            words.append(w)
            if "ё" in w:
                words.append(w.replace("ё", "е"))
    return dedupe(words)


def dedupe(words):
    seen = set()
    out = []
    for w in words:
        if w not in seen:
            seen.add(w)
            out.append(w)
    return out


def dart_string(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def write_dictionaries(lists):
    lines = [
        "// Сгенерировано tool/password_data.py — не править вручную.",
        "//",
        f"// Списки zxcvbn 4.4.2 (коммит {ZXCVBN_COMMIT[:12]}), лицензия MIT:",
        "// Copyright (c) 2012-2016 Dan Wheeler and Dropbox, Inc. Русский",
        "// список — tool/password-ru.txt. Слова через запятую, по рангу.",
        "",
        "/// Словари по имени: слова через запятую, первое — ранг 1.",
        "const Map<String, String> passwordDictionaries = {",
    ]
    for name, words in lists.items():
        for w in words:
            assert w and "," not in w, (name, w)
        lines.append(f"  '{name}': {dart_string(','.join(words))},")
    lines.append("};")
    write(os.path.join(OUT_DIR, "dictionaries.g.dart"), "\n".join(lines) + "\n")


def write_unicode():
    ranges = []
    start = None
    for cp in range(0x110001):
        bad = cp <= 0x10FFFF and unicodedata.category(chr(cp)) in ("Cn", "Cc", "Cs")
        if bad and start is None:
            start = cp
        elif not bad and start is not None:
            ranges.append((start, cp - 1))
            start = None
    packed = ",".join(f"{a:X}" if a == b else f"{a:X}-{b:X}" for a, b in ranges)
    lines = [
        "// Сгенерировано tool/password_data.py — не править вручную.",
        "",
        "/// Версия Unicode, по которой построена таблица.",
        f"const String passwordUnicodeVersion = '{unicodedata.unidata_version}';",
        "",
        "/// Запрещённые в пароле коды: не назначенные (Cn), управляющие (Cc),",
        "/// суррогаты (Cs). Диапазоны в hex через запятую, «начало-конец»",
        "/// включительно или один код, по возрастанию.",
        "const String passwordForbiddenRanges =",
        f"    '{packed}';",
    ]
    write(os.path.join(OUT_DIR, "unicode.g.dart"), "\n".join(lines) + "\n")
    return len(ranges)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    lists = load_zxcvbn(sys.argv[1] if len(sys.argv) > 1 else None)
    ru = load_russian()
    lists["russian"] = ru
    lists["russian_translit"] = dedupe(
        "".join(TRANSLIT[c] for c in w) for w in ru
    )
    write_dictionaries(lists)
    count = write_unicode()
    total = sum(len(w) for w in lists.values())
    print(f"Словари: {total} слов; Unicode {unicodedata.unidata_version}: {count} запрещённых диапазонов")


if __name__ == "__main__":
    main()
