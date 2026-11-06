#!/usr/bin/env python3
"""Check the rules this repository holds that no linter covers. CI runs it in the `project-rules` job.

- `no-em-dash`: no U+2014 in `tools/*.py` or `Data/*.lua`. Generator banners use a colon, and the generated data
  takes its punctuation from them, so an em dash in a generator reaches every output it writes.
"""

import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
SCOPE = {("tools", ".py"), ("Data", ".lua")}
EM_DASH = "\u2014"


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


def main() -> int:
    files = subprocess.run(["git", "-C", str(ROOT), "ls-files"], capture_output=True, text=True, check=True).stdout
    hits = []
    for path in files.splitlines():
        if (ROOT / path).is_file():
            hits += em_dashes(path, (ROOT / path).read_text(encoding="utf-8", errors="replace"))
    for hit in hits:
        print(hit)
    return int(bool(hits))


if __name__ == "__main__":
    sys.exit(main())
