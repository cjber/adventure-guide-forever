#!/usr/bin/env python3
"""Fail when a screenshot is older than what it shows (WFA-9, forever_tools.screens).

Each image's dump is the part of tests/scenes.lua's headless run (no input, so no Pillow and no wago.tools) that
tools/screenshots.py draws it from, plus the screenshot code itself. docs/screenshots/scenes.sha256 holds each
image's hash beside its dump's; tools/screenshots.py rewrites it after a render.

    python3 tools/check_screenshots.py           # CI: fail on a stale image (see below for the data PR)
    python3 tools/check_screenshots.py --record  # after a render, if tools/screenshots.py did not

On the daily data PR (`data/refresh`, opened by .github/workflows/refresh-data.yml), ci.yml sets
SCREENSHOTS_STALE_WARN=true. Then an image whose scene moved while the image itself is as recorded (what new client
data does) is a GitHub `::warning::` rather than a failure, since the bot that opens that PR can't render (no Pillow
or FOREVER_CORE). Re-render after it merges. Every other problem still fails there, and everything fails everywhere
else.
"""

import functools
import os
import sys
from pathlib import Path

try:
    from tools.forever_tools import screens
except ModuleNotFoundError:
    from forever_tools import screens

sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/screenshots"
# The render modules (not screenshots_test.py, and never an untracked scratch file).
CODE = (
    "tools/screenshots.py",
    "tools/screenshots_art.py",
    "tools/screenshots_resolver.py",
    "tools/screenshots_spf.py",
    "tools/screenshots_stock.py",
    "tools/screenshot_loot.lua",
)
# Each image and the parts of tests/scenes.lua's run tools/screenshots.py reads for it: a scene, or one of its
# fields ("panel.map" is the zone every quest-log image is drawn on).
IMAGES = {
    "panel.png": ("journeys", "panel.map"),
    "chosen.png": ("panel",),
    "panel_four.png": ("journeys_four", "panel.map"),
    "panel_overflow.png": ("journeys_overflow", "panel.map"),
    "search.png": ("search", "panel.map", "panel.pins"),
    "restedxp.png": ("restedxp", "panel.map"),
    "guide_setup.png": ("guide_setup",),
    "map.png": ("map", "panel.map"),
    "tooltip.png": ("tooltip", "panel.map"),
    "tracker.png": ("tracker",),
    "menu.png": ("menu", "tracker"),
    "loot.png": ("loot_menu",),
    "story_complete.png": ("story_complete",),
    "micro-menu-adventure-guide.png": ("menu", "tracker"),
    "micro-menu-adventure-guide-additive.png": ("menu", "tracker"),
    "micro-menu-options.png": ("menu", "tracker"),
    "demo.gif": ("journeys", "panel", "map"),
}


@functools.cache
def scenes_run() -> dict:
    """tests/scenes.lua with no input, as tools/screenshots.py's first layout pass runs it (no Pillow needed)."""
    import screenshots

    return screenshots.run_scenes()


def part(data: dict, key: str) -> object:
    scene, _, field = key.partition(".")
    return data[scene][field] if field else data[scene]


def dump(keys: tuple[str, ...]) -> bytes:
    data = scenes_run()
    return screens.dump_json({key: part(data, key) for key in keys}) + screens.files(ROOT, CODE)


SCENES = {image: functools.partial(dump, keys) for image, keys in IMAGES.items()}


def stale_by_data(name: str, recorded: dict[str, tuple[str, str]]) -> bool:
    """Whether `name` is stale only because what it shows moved: the image is as recorded, its scene dump is not."""
    path = OUT / name
    if name not in recorded or name not in SCENES or not path.is_file():
        return False
    image_was, dump_was = recorded[name]
    return screens.sha256(path.read_bytes()) == image_was and screens.sha256(SCENES[name]()) != dump_was


def annotation(text: str) -> str:
    """`text` escaped for a GitHub workflow command's message."""
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main(argv: list[str], env: dict[str, str]) -> int:
    if argv or env.get("SCREENSHOTS_STALE_WARN") != "true":
        return screens.main(OUT, SCENES, argv)
    recorded = screens.read(OUT)
    problems = screens.check(OUT, SCENES)
    stale = [problem for problem in problems if stale_by_data(problem.partition(":")[0], recorded)]
    failing = [problem for problem in problems if problem not in stale]
    for problem in stale:
        print(f"::warning title=Stale screenshot::{annotation(problem)}")
    for problem in failing:
        print(problem, file=sys.stderr)
    if failing:
        return 1
    if stale:
        print(f"Screenshots: {len(stale)} stale after a data refresh; re-render after this PR merges")
    else:
        print(f"Screenshots: {len(SCENES)} images match what they are drawn from")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], dict(os.environ)))
