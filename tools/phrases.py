"""Write Locales/phrases.txt, the template a translation starts from, or check it and the tree with --check.

A translation is Locales/<locale>.lua: the guard lines below, then `L["KEY"] = "text"` for each line it translates.
The keys are AGF's constant names and the template gives each one's English. A line that is a Blizzard GlobalString
with an English fallback (`ITEM_RACES_ALLOWED or "Races: %s"`) is left out: the client already translates it.
"""

import argparse
import subprocess
import sys
from pathlib import Path

from lint_copy import matching, split, unquote
from lint_multivalue import tokenize

ROOT = Path(__file__).resolve().parent.parent
STRINGS = ROOT / "Locales" / "enUS.lua"
PHRASES = ROOT / "Locales" / "phrases.txt"
HEADER = """\
-- Adventure Guide Forever's lines, to translate. Copy this file to Locales/deDE.lua (or esES, esMX, frFR, itIT,
-- koKR, ptBR, ruRU, zhCN, zhTW), change "deDE" below to match, translate the text on the right of each line and
-- keep the %d and %s in it. Delete a line you leave in English. Then add the file to AdventureGuideForever.toc,
-- after Locales\\enUS.lua. Regenerate with: python3 tools/phrases.py > Locales/phrases.txt
local _, ns = ...
if GetLocale() ~= "deDE" then
\treturn
end
local L = ns.L
"""
# CurseForge's localization export is gone; the packager fails a release on a file that still asks for it.
KEYWORD = "@" + "localization"


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
    return HEADER + "".join(f"L[{quote(key)}] = {quote(found[key])}\n" for key in sorted(found))


def keyword_files() -> list[str]:
    tracked = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    names = [name for name in tracked.decode().split("\0") if name]
    return [name for name in names if (ROOT / name).is_file() and KEYWORD.encode() in (ROOT / name).read_bytes()]


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--check", action="store_true", help="fail on a stale phrases.txt or a packager keyword")
    text = render(phrases(STRINGS.read_text()))
    if not args.parse_args().check:
        sys.stdout.write(text)
        return 0
    status = 0
    if PHRASES.read_text() != text:
        print(f"{PHRASES.relative_to(ROOT)} is stale: python3 tools/phrases.py > {PHRASES.relative_to(ROOT)}")
        status = 1
    for name in keyword_files():
        print(f"{name}: {KEYWORD} would fail the release; CurseForge no longer exports translations")
        status = 1
    if not status:
        print(f"phrases: {text.count(chr(10)) - HEADER.count(chr(10))} lines, current; no {KEYWORD}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
