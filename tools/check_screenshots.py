#!/usr/bin/env python3
"""Fail when a screenshot is older than what it shows (WFA-9, forever_tools.screens).

Each image's dump is the part of tests/scenes.lua's headless run (no input, so no Pillow and no wago.tools) that
tools/screenshots.py draws it from, plus the screenshot code itself. docs/screenshots/scenes.sha256 holds each
image's hash beside its dump's; tools/screenshots.py rewrites it after a render.

    python3 tools/check_screenshots.py           # CI: fail on a stale image
    python3 tools/check_screenshots.py --record  # after a render, if tools/screenshots.py did not
"""

import functools
import json
import subprocess
import sys
from pathlib import Path

try:
    from tools.forever_tools import screens
except ModuleNotFoundError:
    from forever_tools import screens

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/screenshots"
CODE = ("tools/screenshots*.py", "tools/screenshot_loot.lua")
# Each image and the tests/scenes.lua scenes tools/screenshots.py reads for it ("panel" carries the map and pins
# every quest-log image sits on).
IMAGES = {
    "panel.png": ("journeys", "panel"),
    "chosen.png": ("panel",),
    "panel_four.png": ("journeys_four", "panel"),
    "panel_overflow.png": ("journeys_overflow", "panel"),
    "search.png": ("search", "panel"),
    "restedxp.png": ("restedxp", "panel"),
    "guide_setup.png": ("guide_setup",),
    "map.png": ("map", "panel"),
    "tooltip.png": ("tooltip", "panel"),
    "tracker.png": ("tracker",),
    "menu.png": ("menu", "tracker"),
    "loot.png": ("loot_menu",),
    "story_complete.png": ("story_complete",),
    "demo.gif": ("journeys", "panel", "map"),
}


@functools.cache
def scenes_run() -> dict:
    result = subprocess.run(["luajit", "tests/scenes.lua"], cwd=ROOT, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    if data["errors"]:
        sys.exit("tests/scenes.lua raised:\n" + "\n".join(data["errors"]))
    return data


def dump(keys: tuple[str, ...]) -> bytes:
    data = scenes_run()
    return screens.dump_json({key: data[key] for key in keys}) + screens.files(ROOT, CODE)


SCENES = {image: functools.partial(dump, keys) for image, keys in IMAGES.items()}


if __name__ == "__main__":
    sys.exit(screens.main(OUT, SCENES))
