#!/usr/bin/env python3
"""Check the packager's output before an upload (forever_tools.package): every file the TOC and XML load ships,
nothing from development does, a licence file and THIRD_PARTY.md do (with README's `## Credits` and THIRD_PARTY's
`## Ideas and contributors`, WFA-10 and WFA-31), and the smoke spec passes on the packaged files.

    printf 'Package check\\n' > .release-notes.md
    <BigWigs packager release.sh> -d -z    # CI: the package job, with the release workflow's pinned packager
    python3 tools/check_package.py
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import package
except ModuleNotFoundError:
    from forever_tools import package

ROOT = Path(__file__).resolve().parent.parent
# tests/forever_core.lua reads ForeverCore's TOC with the shared reader under tools/forever_sim, which the package
# never ships, so the smoke spec needs that one folder beside tests/.
POLICY = package.Policy(
    addons=("AdventureGuideForever",),
    specs=("tests/smoke_spec.lua",),
    support=("tests", "tools/forever_sim"),
)

if __name__ == "__main__":
    sys.exit(package.main(ROOT, POLICY))
