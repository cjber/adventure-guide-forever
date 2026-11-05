"""Fingerprint the inputs that produce AGF's saved Questie catalogue.

The saved catalogue's key carries this fingerprint in place of the addon's version, so it must cover every file the
build reads. The build also calls Planning/Model.lua's ValidPlace and EXPLORE_SLOT, a range check and a constant, which
are left out so that a planner change does not throw every player's catalogue away.
"""

import argparse
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Integrations/QuestieSource.lua"
PATTERN = re.compile(r'local CACHE_REVISION = "[a-f0-9]+"')
INPUTS = (
    "Integrations/QuestieSource.lua",
    "Integrations/QuestieTowns.lua",
    "Integrations/QuestieObjectives.lua",
    "Data/Geometry.lua",
    "Data/Forever.lua",
)


def revision():
    digest = hashlib.sha256()
    for name in INPUTS:
        content = (ROOT / name).read_text()
        if name == INPUTS[0]:
            content = PATTERN.sub('local CACHE_REVISION = ""', content)
        digest.update(name.encode() + b"\0" + content.encode() + b"\0")
    return digest.hexdigest()


def check():
    expected = f'local CACHE_REVISION = "{revision()}"'
    if expected not in SOURCE.read_text():
        raise ValueError("Catalogue inputs changed: run python3 tools/catalogue_revision.py --write")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    if parser.parse_args().write:
        content, count = PATTERN.subn(f'local CACHE_REVISION = "{revision()}"', SOURCE.read_text())
        if count != 1:
            raise ValueError("Expected one catalogue revision")
        SOURCE.write_text(content)
    check()
