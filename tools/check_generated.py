"""Regenerate AGF's pinned data in a scratch tree and reject stale or unstable output."""

import argparse
import subprocess
import sys
from pathlib import Path

import diff_forever
import gen_quests
import gen_zoneart
import phrases
from forever_tools import generated

ROOT = Path(__file__).resolve().parent.parent
DATA = tuple(
    path.relative_to(ROOT).as_posix()
    for path in (
        gen_quests.OUTPUT,
        gen_quests.FIXTURE,
        gen_quests.TOWN_FIXTURE,
        diff_forever.OUTPUT,
        gen_zoneart.OUTPUT,
        phrases.PHRASES,
    )
)


compare = generated.compare


def run(root, *command):
    subprocess.run(command, cwd=root, check=True)


def outputs(root):
    return {name: (root / name).read_bytes() for name in DATA}


def regenerate(root, offline):
    for name in DATA:
        (root / name).unlink()
    mode = ["--offline"] if offline else []
    run(root, sys.executable, "tools/gen_quests.py", *mode)
    run(root, sys.executable, "tools/diff_forever.py", *mode)
    run(root, sys.executable, "tools/gen_zoneart.py", *mode)
    with (root / DATA[-1]).open("wb") as stream:
        subprocess.run([sys.executable, "tools/phrases.py"], cwd=root, stdout=stream, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="require existing tools/.cache inputs")
    generated.check_generated(
        ROOT,
        outputs=outputs,
        regenerate=regenerate,
        offline=parser.parse_args().offline,
        success="AGF generated data and phrases are current and reproducible.",
        prefix="agf-regenerate-",
    )


if __name__ == "__main__":
    main()
