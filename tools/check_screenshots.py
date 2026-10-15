#!/usr/bin/env python3
"""Fail when a screenshot is older than what it shows (WFA-9, forever_tools.screens).

Each image's dump is the part of tests/scenes.lua's headless run (no input, so no Pillow and no wago.tools) that
tools/screenshots.py draws it from, plus the screenshot code itself. docs/screenshots/scenes.sha256 holds each
image's hash beside its dump's; tools/screenshots.py rewrites it after a render.

    python3 tools/check_screenshots.py           # CI: fail on a stale image
    python3 tools/check_screenshots.py --record  # after a render, if tools/screenshots.py did not
"""

import functools
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


if __name__ == "__main__":
    sys.exit(screens.main(OUT, SCENES))
