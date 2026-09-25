"""Print ns.L's lines for CurseForge's "Import localization" page, or check Locales/phrases.txt against them.

The keys stay AGF's constant names and each value is its English line, as `L["KEY"] = "text"`; the packager puts
the translations back under the same keys (Locales/Translations.lua). A line that is a Blizzard GlobalString with
an English fallback (`ITEM_RACES_ALLOWED or "Races: %s"`) is left out: the client already translates it.
"""

import argparse
import sys
from pathlib import Path

from lint_copy import matching, split, unquote
from lint_multivalue import tokenize

ROOT = Path(__file__).resolve().parent.parent
STRINGS = ROOT / "Locales" / "enUS.lua"
PHRASES = ROOT / "Locales" / "phrases.txt"


def phrases(source: str) -> dict[str, str]:
    """KEY -> English line for each ns.L entry made only of string literals ("a" .. "b" joined)."""
    tokens = tokenize(source)[0]
    texts = [t.text for t in tokens]
    start = next(i for i in range(len(texts) - 4) if texts[i : i + 5] == ["ns", ".", "L", "=", "{"])
    found = {}
    for entry in split(tokens[start + 5 : matching(tokens, start + 4)], ","):
        if len(entry) < 3 or entry[1].text != "=":
            continue
        value = split(entry[2:], "..")
        if all(len(part) == 1 and part[0].kind == "string" for part in value):
            found[entry[0].text] = "".join(unquote(part[0].text) for part in value)
    return found


def quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def render(found: dict[str, str]) -> str:
    return "".join(f"L[{quote(key)}] = {quote(found[key])}\n" for key in sorted(found))


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--check", action="store_true", help=f"fail unless {PHRASES.relative_to(ROOT)} is current")
    text = render(phrases(STRINGS.read_text()))
    if not args.parse_args().check:
        sys.stdout.write(text)
        return 0
    if PHRASES.read_text() != text:
        print(f"{PHRASES.relative_to(ROOT)} is stale: python3 tools/phrases.py > {PHRASES.relative_to(ROOT)}")
        return 1
    print(f"phrases: {text.count(chr(10))} lines, current")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
