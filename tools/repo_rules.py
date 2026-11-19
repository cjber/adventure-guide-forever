#!/usr/bin/env python3
"""Check the rules this repository holds that no linter covers. CI runs it in the `project-rules` job.

- `no-em-dash`: no U+2014 in `tools/*.py` or `Data/*.lua`. Generator banners use a colon, and the generated data
  takes its punctuation from them, so an em dash in a generator reaches every output it writes.
- `item-info-outside-core`: only `Core/ItemInfo.lua` names `GET_ITEM_INFO_RECEIVED` or `ITEM_DATA_LOAD_RESULT`. They
  fire for every item any addon asks about, in bursts, so a feature awaits its own items through `ns.ItemInfo`.
"""

import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
SCOPE = {("tools", ".py"), ("Data", ".lua")}
EM_DASH = "\u2014"
ITEM_EVENTS = ("GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT")
ITEM_INFO = "Core/ItemInfo.lua"


def em_dashes(path: str, text: str) -> list[str]:
    """One finding per line of an in-scope file that holds an em dash."""
    name = PurePosixPath(path)
    if (name.parent.as_posix(), name.suffix) not in SCOPE:
        return []
    return [
        f"{path}:{number}: no-em-dash: U+2014 is forbidden in tools and generated data; use a colon or ASCII"
        for number, line in enumerate(text.splitlines(), 1)
        if EM_DASH in line
    ]


def item_events(path: str, text: str) -> list[str]:
    """One finding per line of addon Lua or XML, outside Core/ItemInfo.lua, naming an item data event."""
    name = PurePosixPath(path)
    if name.suffix not in (".lua", ".xml") or path == ITEM_INFO or name.parts[0] in ("tests", "tools", "types"):
        return []
    return [
        f"{path}:{number}: item-info-outside-core: await items through ns.ItemInfo, not the event"
        for number, line in enumerate(text.splitlines(), 1)
        if any(event in line for event in ITEM_EVENTS)
    ]


def main() -> int:
    files = subprocess.run(["git", "-C", str(ROOT), "ls-files"], capture_output=True, text=True, check=True).stdout
    hits = []
    for path in files.splitlines():
        if (ROOT / path).is_file():
            text = (ROOT / path).read_text(encoding="utf-8", errors="replace")
            hits += em_dashes(path, text) + item_events(path, text)
    for hit in hits:
        print(hit)
    return int(bool(hits))


if __name__ == "__main__":
    sys.exit(main())
