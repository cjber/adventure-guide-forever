"""Reject art drawn outside the Art helpers, where nothing keeps its shape.

An icon, atlas or texture is drawn at its own aspect, never pulled to a box of another shape. `UI/Art.lua` holds the
ways to do that (Art.Fit, Art.Icon, Art.Cover, Art.Markup, Art.Highlight, the slices), each under spec. A raw setter
anywhere else, in Lua or XML, is refused unless it takes the atlas's own size (`SetAtlas(atlas, true)`,
`useAtlasSize="true"`) or its line, or the line above, says why its shape is right: `-- art-ok: <reason>` in Lua,
`<!-- art-ok: <reason> -->` in XML. An `art-ok` that excuses nothing is refused too, so none outlives its call.
"""

import argparse
import re
import sys
from pathlib import Path

try:
    from tools.typecheck_coverage import runtime_files
except ModuleNotFoundError:
    from typecheck_coverage import runtime_files

__all__ = ["check", "main"]

HELPERS = "UI/Art.lua"
# Texture and button setters that take art, the markup builder, and inline `|A` and `|T` markup.
RAW_LUA = re.compile(
    r":Set(?:Atlas|Texture|(?:Normal|Pushed|Highlight|Disabled|Checked|DisabledChecked)(?:Atlas|Texture))\s*\("
    r"|\bCreateAtlasMarkup\s*\(|\bCreateTextureMarkup\s*\(|\|[AT][^|\"']*:\d"
)
NATIVE_LUA = re.compile(r":SetAtlas\s*\([^()]*,\s*true\s*\)")
RAW_XML = re.compile(r"<\w*Texture\b[^>]*\b(?:atlas|file)\s*=")
NATIVE_XML = re.compile(r'useAtlasSize\s*=\s*"true"')
WAIVER = re.compile(r"art-ok:\s*\S")
MARK = re.compile(r"art-ok")


def check(source: str, xml: bool = False) -> list[tuple[int, str]]:
    """Each finding as (line, message)."""
    raw, native = (RAW_XML, NATIVE_XML) if xml else (RAW_LUA, NATIVE_LUA)
    lines = source.splitlines()
    findings, excused = [], set()
    for number, line in enumerate(lines, 1):
        code = line if xml else line.split("--", 1)[0]
        if not raw.search(code) or native.search(code):
            continue
        for at in (number, number - 1):
            if at >= 1 and WAIVER.search(lines[at - 1]):
                excused.add(at)
                break
        else:
            findings.append((number, "art-raw: draw art through Art.lua, or say why its shape is right with art-ok"))
    for number, line in enumerate(lines, 1):
        if MARK.search(line) and number not in excused:
            reason = "names no reason" if not WAIVER.search(line) else "excuses no art call"
            findings.append((number, f"art-unused: this art-ok {reason}"))
    return sorted(findings)


def paths(root: Path) -> list[Path]:
    lua = [path for path in runtime_files(root) if path.relative_to(root).as_posix() != HELPERS]
    return sorted(lua + list((root / "UI").rglob("*.xml")))


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("files", nargs="*", type=Path)
    root = Path(__file__).resolve().parent.parent
    failed = False
    for path in args.parse_args().files or paths(root):
        for number, message in check(path.read_text(encoding="utf-8"), path.suffix == ".xml"):
            print(f"{path}:{number}: {message}", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
