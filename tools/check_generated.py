"""Regenerate AGF's pinned data in a scratch tree and reject stale or unstable output."""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import diff_forever
import gen_quests
import gen_zoneart

ROOT = Path(__file__).resolve().parent.parent
DATA = tuple(
    path.relative_to(ROOT).as_posix()
    for path in (gen_quests.OUTPUT, gen_quests.FIXTURE, diff_forever.OUTPUT, gen_zoneart.OUTPUT)
) + ("Locales/phrases.txt",)


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
    with (root / "Locales/phrases.txt").open("wb") as stream:
        subprocess.run([sys.executable, "tools/phrases.py"], cwd=root, stdout=stream, check=True)


def compare(expected, actual, label):
    changed = sorted(name for name in expected.keys() | actual.keys() if expected.get(name) != actual.get(name))
    if changed:
        raise SystemExit(f"{label}:\n" + "\n".join(changed))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="require existing tools/.cache inputs")
    args = parser.parse_args()
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    with tempfile.TemporaryDirectory(prefix="agf-regenerate-") as temporary:
        scratch = Path(temporary)
        for name in filter(None, tracked):
            source = ROOT / name
            if source.is_file():
                target = scratch / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        cache = ROOT / "tools/.cache"
        if cache.exists():
            shutil.copytree(cache, scratch / "tools/.cache", dirs_exist_ok=True)
        expected = outputs(scratch)
        regenerate(scratch, args.offline)
        if not args.offline:
            shutil.copytree(scratch / "tools/.cache", ROOT / "tools/.cache", dirs_exist_ok=True)
        generated = outputs(scratch)
        compare(expected, generated, "Stale generated files; run the canonical generators")
        regenerate(scratch, True)
        compare(generated, outputs(scratch), "Regeneration is not byte-for-byte reproducible")
    print("AGF generated data and phrases are current and reproducible.")


if __name__ == "__main__":
    main()
