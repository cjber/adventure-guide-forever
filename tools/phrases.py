"""Write Locales/phrases.txt, the template the translations follow, or check it and the tree with --check.

A translation is Locales/<locale>.lua: the guard lines below, then `L["KEY"] = "text"` for each line it translates.
The keys are AGF's constant names, and the English phrase of a shared Forever file that reads ns.L by phrase, and the
template gives each one's English. A line that is a Blizzard GlobalString with an English fallback
(`ITEM_RACES_ALLOWED or "Races: %s"`) is left out: the client already translates it.
"""

import argparse
import subprocess
import sys
from pathlib import Path

from forever_tools import pkgmeta
from gen_quests import lua
from lint_copy import ns_l_entries, split, unquote
from lint_multivalue import Token, tokenize

ROOT = Path(__file__).resolve().parent.parent
STRINGS = ROOT / "Locales" / "enUS.lua"
PHRASES = ROOT / "Locales" / "phrases.txt"
HEADER = """\
-- Every line Adventure Guide Forever shows, by key, with its English text: the template the Locales/<locale>.lua
-- files follow. Each client language already has its file; to correct a line, edit that file (Locales/README.md).
-- Regenerate with: python3 tools/phrases.py > Locales/phrases.txt
local _, ns = ...
if GetLocale() ~= "deDE" then
\treturn
end
local L = ns.L
"""
# CurseForge's localization export is gone; the packager fails a release on a file that still asks for it.
KEYWORD = "@" + "localization"


def assigned(tokens: list[Token]) -> dict[str, str]:
    """KEY -> English line for each `ns.L["key"] = "line"` after the table, where a shared file reads ns.L by phrase."""
    found = {}
    texts = [token.text for token in tokens]
    for index in range(len(tokens) - 7):
        if (
            texts[index : index + 4] == ["ns", ".", "L", "["]
            and tokens[index + 4].kind == "string"
            and texts[index + 5 : index + 7] == ["]", "="]
            and tokens[index + 7].kind == "string"
        ):
            found[unquote(tokens[index + 4].text)] = unquote(tokens[index + 7].text)
    return found


def phrases(source: str) -> dict[str, str]:
    """KEY -> English line for each ns.L entry made only of string literals ("a" .. "b" joined), plus each phrase
    assigned after the table, which a shared file reads by the phrase itself."""
    tokens = tokenize(source)[0]
    found = {}
    for key, value in ns_l_entries(tokens):
        parts = split(value, "..")
        if all(len(part) == 1 and part[0].kind == "string" for part in parts):
            found[key.text] = "".join(unquote(part[0].text) for part in parts)
    found.update(assigned(tokens))
    return found


def render(found: dict[str, str]) -> str:
    return HEADER + "".join(f"L[{lua(key)}] = {lua(found[key])}\n" for key in sorted(found))


def keyword_files() -> list[str]:
    tracked = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    names = [name for name in tracked.decode().split("\0") if name]
    manifest = pkgmeta.read(ROOT)
    project_tocs = set(pkgmeta.localization_toc_files(ROOT))
    return [
        name
        for name in names
        if (Path(name).suffix == ".lua" or (ROOT / name).resolve() in project_tocs)
        and (manifest is None or (manifest.keeps(name) and not manifest.kept_bytes(name)))
        and (ROOT / name).is_file()
        and KEYWORD.encode() in (ROOT / name).read_bytes()
    ]


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
