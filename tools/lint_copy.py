"""Keep the player's copy in ns.L, and keep ns.L free of the words the design bans (docs/plan.md F14)."""

import argparse
import re
from pathlib import Path

from lint_multivalue import Token, runtime_files, tokenize

# A percent sign is only ever a format specifier; "%%" would print one.
STRAY_PERCENT = re.compile(r"%(?![-0-9.]*[dsfgi])|%%")
BANNED_WORDS = re.compile(r"\b(?:XP|fastest|fast|optimal|you must)\b", re.IGNORECASE)
# The call, and which argument (1-based, top level) is the text the player reads.
TEXT_ARGUMENT = {"SetText": 1, "CreateButton": 1, "AddObjective": 2}
TOOLTIP_PREFIX = "GameTooltip_"
ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}


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


def strings_table(tokens: list[Token]) -> list[tuple[int, str, str]]:
    """(line, key, value) for each alternative of each ns.L entry; "a" .. "b" joins, "X or 'b'" gives 'b'."""
    texts = [t.text for t in tokens]
    for index in range(len(texts) - 4):
        if texts[index : index + 5] == ["ns", ".", "L", "=", "{"]:
            break
    else:
        raise ValueError("no ns.L = { ... } table")
    body = tokens[index + 5 : matching(tokens, index + 4)]
    entries = []
    for entry in split(body, ","):
        if len(entry) < 3 or entry[1].text != "=":
            continue
        for alternative in split(entry[2:], "or"):
            literals = [unquote(t.text) for t in alternative if t.kind == "string"]
            if literals:
                entries.append((entry[0].line, entry[0].text, "".join(literals)))
    return entries


def literal_calls(tokens: list[Token]) -> list[tuple[int, str]]:
    """(line, call) for each non-empty string literal in a call's text argument."""
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
                if part.kind == "string" and unquote(part.text):
                    hits.append((part.line, token.text))
    return hits


def check(core: Path, files: list[Path]) -> list[str]:
    report = []
    for line, key, value in strings_table(tokenize(core.read_text())[0]):
        report += [f"{core}:{line}: L.{key}: {problem}" for problem in value_problems(value)]
    for path in files:
        for line, call in literal_calls(tokenize(path.read_text())[0]):
            report.append(f"{path}:{line}: a string literal passed to {call}; put the copy in ns.L")
    return report


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("files", nargs="*", type=Path)
    root = Path(__file__).resolve().parent.parent
    files = args.parse_args().files or [p for p in runtime_files(root) if p.parent.name != "Data"]
    report = check(root / "Core.lua", files)
    print("\n".join(report) or "copy: no literals outside L, no banned tokens in L")
    return int(bool(report))


if __name__ == "__main__":
    raise SystemExit(main())
