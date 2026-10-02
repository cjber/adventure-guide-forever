#!/usr/bin/env python3
# sift-scope: all
# sift-fix: Use a colon in generated-file banners and ASCII punctuation in tools and data; regenerate outputs.
# The generator banners contain four occurrences in Python and three in Data, with no false positives.

import os
import sys
from pathlib import Path


def main():
    root = Path(os.environ["SIFT_ROOT"])
    failed = False
    for name in Path(os.environ["SIFT_FILES"]).read_text().splitlines():
        path = Path(name)
        if (path.parent.as_posix(), path.suffix) not in {
            ("tools", ".py"),
            ("Data", ".lua"),
        }:
            continue
        for line, text in enumerate(
            (root / path).read_text(encoding="utf-8").splitlines(), 1
        ):
            if "\u2014" in text:
                print(
                    f"{name}:{line}: {os.environ['SIFT_RULE']} U+2014 is forbidden in tools and generated data"
                )
                failed = True
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
