#!/usr/bin/env python3
"""Move the generators' pins to the newest upstream data, without regenerating (stdlib only).

    python3 tools/refresh_pins.py    # then run the generators, as tools/check_generated.py does

BUILD (gen_quests.py) follows the newest WoW: Forever client build on wago.tools, and ERA (diff_forever.py) the
newest Classic Era build there. A pin never moves backwards. Under GitHub Actions the step outputs `changed` and
`summary` say what moved.
"""

import json
import os
import re
import urllib.request
from pathlib import Path

import diff_forever
import gen_quests

TOOLS = Path(__file__).resolve().parent
# wago.tools product and version prefix: wow_classic_beta carries other Classic betas too, and Forever's are 1.6x.
FOREVER = ("wow_classic_beta", "1.6")
ERA = ("wow_classic_era", "1.15.")


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def latest(builds, product, prefix, pinned):
    """The newest `product` build whose version starts with `prefix`, or `pinned` when that is newer."""
    versions = [build["version"] for build in builds.get(product, ()) if build["version"].startswith(prefix)]
    if not versions:
        raise SystemExit(f"no {product} {prefix}x build listed on wago.tools")
    return max([*versions, pinned], key=version_key)


def fetch_builds():
    request = urllib.request.Request(
        "https://wago.tools/api/builds", headers={"User-Agent": "AdventureGuideForever/1.0"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def pin(text, name, value):
    """`text` with its one `NAME = "..."` assignment set to `value`."""
    replaced, count = re.subn(rf'^{name} = "[^"\n]*"$', f'{name} = "{value}"', text, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"expected one {name} pin, found {count}")
    return replaced


def main():
    builds = fetch_builds()
    pins = (
        ("gen_quests.py", "BUILD", gen_quests.BUILD, latest(builds, *FOREVER, gen_quests.BUILD)),
        ("diff_forever.py", "ERA", diff_forever.ERA, latest(builds, *ERA, diff_forever.ERA)),
    )
    moved = []
    for filename, name, old, new in pins:
        if new != old:
            path = TOOLS / filename
            path.write_text(pin(path.read_text(encoding="utf-8"), name, new), encoding="utf-8")
            moved.append(f"{name} {old} -> {new}")
    summary = ", ".join(moved)
    print(summary or f"already on {gen_quests.BUILD}, Classic Era {diff_forever.ERA}")
    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"changed={'true' if moved else 'false'}\nsummary={summary}\n")


if __name__ == "__main__":
    main()
