"""Reject accidental expansion of select() in Lua 5.1 expression lists."""

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Token:
    text: str
    line: int
    kind: str = "symbol"


class LuaSyntaxError(ValueError):
    pass


LONG_OPEN = re.compile(r"\[(=*)\[")
NUMBER = re.compile(r"(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)")
NAME = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
KEYWORDS = set(
    "and break do else elseif end false for function if in local nil not or repeat return then true until while".split()
)


def tokenize(source: str) -> tuple[list[Token], dict[int, str]]:
    tokens, comments = [], {}
    offset, line = 0, 1
    while offset < len(source):
        start, start_line = offset, line
        char = source[offset]
        if char.isspace():
            line += char == "\n"
            offset += 1
            continue
        comment = source.startswith("--", offset)
        if comment:
            offset += 2
        long = LONG_OPEN.match(source, offset)
        if long:
            close = "]" + long[1] + "]"
            end = source.find(close, long.end())
            if end < 0:
                raise LuaSyntaxError(f"{line}: unterminated long string/comment")
            offset = end + len(close)
        elif comment:
            end = source.find("\n", offset)
            offset = len(source) if end < 0 else end
            comments[start_line] = source[start + 2 : offset].strip()
        elif char in "\"'":
            offset += 1
            while offset < len(source) and source[offset] != char:
                if source[offset] == "\\":
                    offset += 1
                elif source[offset] == "\n":
                    raise LuaSyntaxError(f"{line}: newline in quoted string")
                offset += 1
            if offset >= len(source):
                raise LuaSyntaxError(f"{line}: unterminated quoted string")
            offset += 1
        else:
            match = NUMBER.match(source, offset) or NAME.match(source, offset)
            if match:
                offset = match.end()
                text = match[0]
                kind = "number" if text[0].isdigit() or text[0] == "." else "keyword" if text in KEYWORDS else "name"
            else:
                text = next((s for s in ("...", "..", "==", "~=", "<=", ">=") if source.startswith(s, offset)), char)
                offset += len(text)
                kind = "symbol"
            tokens.append(Token(text, line, kind))
            continue
        line += source[start:offset].count("\n")
        if not comment:
            tokens.append(Token(source[start:offset], start_line, "string"))
    tokens.append(Token("<eof>", line))
    return tokens, comments


# Pratt precedence preserves the distinction between select() and (select()):
# only a bare call can expand, including across newlines and inside nested calls.
PRECEDENCE = {
    "or": 1,
    "and": 2,
    "<": 3,
    ">": 3,
    "<=": 3,
    ">=": 3,
    "~=": 3,
    "==": 3,
    "..": 4,
    "+": 5,
    "-": 5,
    "*": 6,
    "/": 6,
    "%": 6,
    "^": 8,
}
BLOCK_END = {"end", "else", "elseif", "until", "<eof>"}


class Parser:
    def __init__(self, source: str):
        self.tokens, self.comments = tokenize(source)
        self.pos = 0
        self.hits: list[tuple[int, str]] = []

    @property
    def current(self) -> Token:
        return self.tokens[self.pos]

    def take(self, expected: str | None = None) -> Token:
        token = self.current
        if expected is not None and token.text != expected:
            raise LuaSyntaxError(f"{token.line}: expected {expected!r}, got {token.text!r}")
        self.pos += 1
        return token

    def accept(self, text: str) -> bool:
        if self.current.text != text:
            return False
        self.take()
        return True

    def name(self) -> None:
        if self.current.kind != "name":
            raise LuaSyntaxError(f"{self.current.line}: expected a name")
        self.take()

    def flag(self, select: Token | None, context: str, end_line: int, value_line: int | None = None) -> None:
        if select is None:
            return
        # Permit a reason beside the final value or the closing delimiter.
        if any(re.fullmatch(r"multi-value:\s*\S.*", self.comments.get(line, "")) for line in (end_line, value_line)):
            return
        self.hits.append(
            (select.line, f"select() expands as the last {context}; parenthesize it or add -- multi-value: <reason>")
        )

    def expressions(self) -> Token | None:
        last = self.expression()
        while self.accept(","):
            last = self.expression()
        return last

    def function_body(self) -> None:
        self.take("(")
        if not self.accept(")"):
            while True:
                if self.accept("..."):
                    break
                self.name()
                if not self.accept(","):
                    break
            self.take(")")
        self.block()
        self.take("end")

    def table(self) -> None:
        self.take("{")
        last = None
        value_line = None
        while self.current.text != "}":
            if self.accept("["):
                self.expression()
                self.take("]")
                self.take("=")
                self.expression()
                last = None
            elif self.current.kind == "name" and self.tokens[self.pos + 1].text == "=":
                self.take()
                self.take("=")
                self.expression()
                last = None
            else:
                last = self.expression()
            value_line = self.tokens[self.pos - 1].line
            if not (self.accept(",") or self.accept(";")):
                break
        end = self.take("}")
        self.flag(last, "table element", end.line, value_line)

    def expression(self, minimum: int = 0) -> Token | None:
        token = self.current
        last = None
        callee = None
        if token.text in {"not", "#", "-"}:
            self.take()
            self.expression(7)
        elif token.text == "function":
            self.take()
            self.function_body()
        elif token.text == "{":
            self.table()
        elif token.kind in {"number", "string"} or token.text in {"nil", "true", "false", "..."}:
            self.take()
        elif token.kind == "name" or token.text == "(":
            if self.accept("("):
                start = self.pos
                self.expression()
                inner = self.tokens[start : self.pos]
                while len(inner) >= 3 and inner[0].text == "(" and inner[-1].text == ")":
                    inner = inner[1:-1]
                if len(inner) == 1 and inner[0].text == "select":
                    callee = inner[0]
                self.take(")")
            else:
                callee = self.take() if token.text == "select" else None
                if callee is None:
                    self.take()
            while True:
                if self.accept(".") or self.accept(":"):
                    self.name()
                    callee, last = None, None
                elif self.accept("["):
                    self.expression()
                    self.take("]")
                    callee, last = None, None
                elif self.accept("("):
                    argument = None if self.current.text == ")" else self.expressions()
                    value_line = self.tokens[self.pos - 1].line
                    end = self.take(")")
                    self.flag(argument, "call argument", end.line, value_line)
                    last, callee = callee, None
                elif self.current.text == "{" or self.current.kind == "string":
                    if self.current.text == "{":
                        self.table()
                    else:
                        self.take()
                    last, callee = callee, None
                else:
                    break
        else:
            raise LuaSyntaxError(f"{token.line}: expected an expression, got {token.text!r}")
        while (precedence := PRECEDENCE.get(self.current.text, -1)) >= minimum:
            operator = self.take().text
            self.expression(precedence if operator in {"^", ".."} else precedence + 1)
            last = None
        return last

    def block(self) -> None:
        while self.current.text not in BLOCK_END:
            if self.accept(";") or self.accept("break"):
                continue
            if self.accept("return"):
                if self.current.text not in BLOCK_END | {";"}:
                    last = self.expressions()
                    self.accept(";")
                    self.flag(last, "return value", self.tokens[self.pos - 1].line)
                continue
            if self.accept("do"):
                self.block()
                self.take("end")
            elif self.accept("while"):
                self.expression()
                self.take("do")
                self.block()
                self.take("end")
            elif self.accept("repeat"):
                self.block()
                self.take("until")
                self.expression()
            elif self.accept("if"):
                self.expression()
                self.take("then")
                self.block()
                while self.accept("elseif"):
                    self.expression()
                    self.take("then")
                    self.block()
                if self.accept("else"):
                    self.block()
                self.take("end")
            elif self.accept("for"):
                self.name()
                while self.accept(","):
                    self.name()
                if not self.accept("="):
                    self.take("in")
                self.expressions()
                self.take("do")
                self.block()
                self.take("end")
            elif self.accept("function"):
                self.name()
                while self.accept("."):
                    self.name()
                if self.accept(":"):
                    self.name()
                self.function_body()
            elif self.accept("local"):
                if self.accept("function"):
                    self.name()
                    self.function_body()
                else:
                    self.name()
                    while self.accept(","):
                        self.name()
                    if self.accept("="):
                        self.expressions()
            else:
                self.expressions()
                if self.accept("="):
                    self.expressions()


def check(source: str) -> list[tuple[int, str]]:
    parser = Parser(source)
    parser.block()
    parser.take("<eof>")
    return parser.hits


def runtime_files(root: Path) -> list[Path]:
    # The TOC is the runtime contract, including generated data and future subfolders.
    files = set()
    for toc in root.glob("*.toc"):
        for line in toc.read_text().splitlines():
            line = line.strip()
            # XML templates are listed too; only Lua can expand select().
            if line.endswith(".lua") and not line.startswith("#"):
                files.add(root / line.replace("\\", "/"))
    if not files:
        raise ValueError("No runtime files found in the TOC")
    return sorted(files)


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("files", nargs="*", type=Path)
    paths = args.parse_args().files or runtime_files(Path(__file__).resolve().parent.parent)
    failed = False
    for path in paths:
        try:
            hits = check(path.read_text())
        except (OSError, LuaSyntaxError) as error:
            print(f"{path}: {error}")
            failed = True
            continue
        for line, message in hits:
            print(f"{path}:{line}: multi-value: {message}")
        failed |= bool(hits)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
