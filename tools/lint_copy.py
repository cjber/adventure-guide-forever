"""Keep the player's copy in ns.L, and keep ns.L free of the words the design bans."""

import argparse
import re
from pathlib import Path

from lint_multivalue import Token, tokenize
from typecheck_coverage import runtime_files

# A percent sign is only ever a format specifier; "%%" would print one.
STRAY_PERCENT = re.compile(r"%(?![-0-9.]*[dsfgi])|%%")
BANNED_WORDS = re.compile(r"\b(?:XP|fastest|fast|optimal|you must)\b", re.IGNORECASE)
# The call, and which argument (1-based, top level) is the text the player reads: frames, menus, the tracker, chat
# and the Settings page's category, checkbox names and tooltips.
TEXT_ARGUMENT = {
    "SetText": 1,
    "SetFormattedText": 1,
    "SetTitle": 1,
    "CreateButton": 1,
    "CreateCheckbox": 1,
    "CreateTitle": 1,
    "AddObjective": 2,
    "AddLine": 1,
    "AddDoubleLine": 1,
    "AddMessage": 1,
    "Print": 1,
    "RegisterVerticalLayoutCategory": 1,
    "RegisterAddOnSetting": 6,
    "CreateCheckboxInitializer": 3,
}
TOOLTIP_PREFIX = "GameTooltip_"
# Colour codes, atlas and texture markup carry no words, so a literal of only those is not copy.
MARKUP = re.compile(r"\|c[0-9a-fA-F]{8}|\|r|\|A[^|]*\|a|\|T[^|]*\|t")
ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}
# Shared byte for byte by the Forever addons, so it can't use this addon's constant keys: its copy goes through its own
# L, keyed by the English phrase (L["Close"]), which falls back to the phrase. Those lookups are its ns.L.
PHRASE_KEYED = {"ForeverFamily.lua"}


def unquote(literal: str) -> str:
    if literal.startswith("["):
        return literal[literal.index("[", 1) + 1 : literal.rindex("]", 0, -1)]
    return re.sub(r"\\(.)", lambda m: ESCAPES.get(m[1], m[1]), literal[1:-1])


def value_problems(value: str) -> list[str]:
    problems = []
    if value.strip() == "?":
        problems.append('"?" as a value')
    if STRAY_PERCENT.search(value):
        problems.append("a literal percent sign")
    problems += [f"banned word {m[0]!r}" for m in BANNED_WORDS.finditer(value)]
    return problems


def matching(tokens: list[Token], start: int) -> int:
    """The index of the bracket closing the one at start."""
    depth = 0
    for index in range(start, len(tokens)):
        text = tokens[index].text
        if tokens[index].kind == "symbol" and text in "([{":
            depth += 1
        elif tokens[index].kind == "symbol" and text in ")]}":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError(f"{tokens[start].line}: unclosed {tokens[start].text!r}")


def split(tokens: list[Token], separator: str) -> list[list[Token]]:
    """Top-level pieces of a token run, split on a symbol or keyword."""
    pieces: list[list[Token]] = [[]]
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token.kind == "symbol" and token.text in "([{":
            end = matching(tokens, index)
            pieces[-1] += tokens[index : end + 1]
            index = end + 1
            continue
        if token.text == separator and token.kind != "string":
            pieces.append([])
        else:
            pieces[-1].append(token)
        index += 1
    return pieces


def ns_l_entries(tokens: list[Token]) -> list[tuple[Token, list[Token]]]:
    """(key, value tokens) for each entry of the ns.L = { ... } table; raises on a missing table or an entry not shaped
    NAME = value."""
    texts = [t.text for t in tokens]
    for index in range(len(texts) - 4):
        if texts[index : index + 5] == ["ns", ".", "L", "=", "{"]:
            break
    else:
        raise ValueError("no ns.L = { ... } table")
    entries = []
    for entry in split(tokens[index + 5 : matching(tokens, index + 4)], ","):
        if not entry:
            continue
        if len(entry) < 3 or entry[0].kind != "name" or entry[1].text != "=":
            raise ValueError(f"{entry[0].line}: an ns.L entry not shaped NAME = value; the copy checks cannot read it")
        entries.append((entry[0], entry[2:]))
    return entries


def strings_table(tokens: list[Token]) -> list[tuple[int, str, str]]:
    """(line, key, value) for each alternative of each ns.L entry; "a" .. "b" joins, "X or 'b'" gives 'b'."""
    entries = []
    for key, value in ns_l_entries(tokens):
        for alternative in split(value, "or"):
            literals = [unquote(t.text) for t in alternative if t.kind == "string"]
            if literals:
                entries.append((key.line, key.text, "".join(literals)))
    return entries


def phrase_lookup(tokens: list[Token], index: int) -> bool:
    """The string at index is the key of an L["phrase"] lookup."""
    return (
        2 <= index < len(tokens) - 1
        and tokens[index - 1].text == "["
        and tokens[index - 2].text == "L"
        and tokens[index + 1].text == "]"
    )


def phrases(tokens: list[Token]) -> list[tuple[int, str]]:
    """(line, phrase) for each L["phrase"] lookup."""
    return [
        (token.line, unquote(token.text))
        for index, token in enumerate(tokens)
        if token.kind == "string" and phrase_lookup(tokens, index)
    ]


def literal_calls(tokens: list[Token], keyed: bool = False) -> list[tuple[int, str]]:
    """(line, call) for each string literal with words in it in a call's text argument; with `keyed`, an L["phrase"]
    lookup is copy, not a literal."""
    positions = {id(token): index for index, token in enumerate(tokens)}
    hits = []
    for index, token in enumerate(tokens[:-1]):
        if token.kind != "name" or tokens[index + 1].text != "(":
            continue
        position = TEXT_ARGUMENT.get(token.text, 2 if token.text.startswith(TOOLTIP_PREFIX) else None)
        if position is None:
            continue
        arguments = split(tokens[index + 2 : matching(tokens, index + 1)], ",")
        if len(arguments) >= position:
            for part in arguments[position - 1]:
                if keyed and part.kind == "string" and phrase_lookup(tokens, positions[id(part)]):
                    continue
                if part.kind == "string" and re.search(r"[^\W\d_]", MARKUP.sub("", unquote(part.text))):
                    hits.append((part.line, token.text))
    return hits


def check(core: Path, files: list[Path]) -> list[str]:
    report = []
    for line, key, value in strings_table(tokenize(core.read_text())[0]):
        report += [f"{core}:{line}: L.{key}: {problem}" for problem in value_problems(value)]
    for path in files:
        tokens = tokenize(path.read_text())[0]
        keyed = path.name in PHRASE_KEYED
        for line, call in literal_calls(tokens, keyed):
            report.append(f"{path}:{line}: a string literal passed to {call}; put the copy in ns.L")
        for line, phrase in phrases(tokens) if keyed else []:
            report += [f"{path}:{line}: L[{phrase!r}]: {problem}" for problem in value_problems(phrase)]
    return report


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("files", nargs="*", type=Path)
    root = Path(__file__).resolve().parent.parent
    files = args.parse_args().files or [p for p in runtime_files(root) if p.parent.name != "Data"]
    report = check(root / "Locales" / "enUS.lua", files)
    print("\n".join(report) or "copy: no literals outside L, no banned tokens in L")
    return int(bool(report))


if __name__ == "__main__":
    raise SystemExit(main())
