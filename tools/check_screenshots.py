#!/usr/bin/env python3
"""Fail when a screenshot is older than what it shows (WFA-9, forever_tools.screens).

Each image's dump is the part of tests/scenes.lua's headless run (no input, so no Pillow and no wago.tools) that
tools/screenshots.py draws it from, plus the screenshot code itself. docs/screenshots/scenes.sha256 holds each
image's hash beside its dump's; tools/screenshots.py rewrites it after a render.

    python3 tools/check_screenshots.py           # CI: fail on a stale image
    python3 tools/check_screenshots.py --record  # after a render, if tools/screenshots.py did not

On the daily data PR's branch (`data/refresh`) a stale image is a GitHub `::warning::` and the check passes: new
client data can move what a scene shows, the bot that opens that PR cannot render (no Pillow or WOWMOCK), and
the images are re-rendered by hand after it merges. On every other branch it still fails.
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

# The branch .github/workflows/refresh-data.yml opens its PR from.
REFRESH_BRANCH = "data/refresh"


def branch(env: dict[str, str]) -> str:
    """The branch CI checks: a pull request's head (GITHUB_HEAD_REF), else the pushed or dispatched ref."""
    return env.get("GITHUB_HEAD_REF") or env.get("GITHUB_REF_NAME") or ""


def main(argv: list[str], env: dict[str, str]) -> int:
    if argv or branch(env) != REFRESH_BRANCH:
        return screens.main(OUT, SCENES, argv)
    problems = screens.check(OUT, SCENES)
    for problem in problems:
        print(f"::warning title=Stale screenshot::{problem}")
    if problems:
        print(f"Screenshots: {len(problems)} stale on {REFRESH_BRANCH}; re-render after the data PR merges")
    else:
        print(f"Screenshots: {len(SCENES)} images match what they are drawn from")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], dict(os.environ)))
