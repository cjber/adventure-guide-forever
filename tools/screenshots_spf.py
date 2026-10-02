"""Fetch the pinned Shortest Path sources and draw its route and stop pins."""

import io
import json
import os
import subprocess
import sys
from pathlib import Path

import screenshots_art as drawing
from screenshots_art import draw_font_string, texture
from screenshots_resolver import map_point

ROOT = Path(__file__).resolve().parent.parent

# SPF #52's stock quest POIs. Its geometry is SPF's own Path.FindSync, run by LuaJIT in an extracted copy.
# The API contract fixture keeps its independent compatibility pin in tests/contract_spec.lua.
SPF_SHA = "061f0b1041f85d02084c25a27edbbf3db3ae7ec7"
SPF_TARBALL = f"https://codeload.github.com/cjber/shortest-path-forever/tar.gz/{SPF_SHA}"
SPF_CACHE = ROOT / "tools/.cache" / f"spf-{SPF_SHA}"
# Route.lua: THICKNESS 2 over UNDER_THICKNESS 4 at UNDER_ALPHA .5; walks are DOT 4 breadcrumbs every SPACING 9, each
# over a dark dot RIM 1 wider; the walk colour is NORMAL_FONT_COLOR.
SPF_DOT, SPF_RIM, SPF_SPACING, SPF_UNDER = 4, 1, 9, (0.04, 0.04, 0.04, 0.5)

SPF_PROGRAM = r"""
local ns = {}
local files = {
    "Data/Routes", "Data/Transports", "Data/Portals", "Data/Taxi",
    "Model", "PathGrid", "Path", "Planner",
}
for _, name in ipairs(files) do
	local chunk = assert(loadfile(name .. ".lua"))
	chunk("ShortestPathForever", ns)
end
local walks = {}
for index, leg in ipairs(LEGS) do
	assert(loadfile("tools/load_nav.lua"))(leg.map)
	local points, why = ns.Path.FindSync(leg.map, leg.from, leg.to)
	assert(points, tostring(why))
	local out = {}
	for i, point in ipairs(points) do
		out[i] = string.format("[%.3f,%.3f]", point.x, point.y)
	end
	walks[index] = "[" .. table.concat(out, ",") .. "]"
end
print("[" .. table.concat(walks, ",") .. "]")
"""


def spf_sources():
    """SPF_CACHE, extracted from a local clone ($SPF, else a sibling of this checkout or of its main worktree) with
    `git archive`, else from GitHub's tarball of the sha."""
    if (SPF_CACHE / "Path.lua").is_file():
        return SPF_CACHE
    import tarfile
    import urllib.request

    candidates = [os.environ.get("SPF"), ROOT.parent / "shortest-path-forever", sibling("shortest-path-forever")]
    archive = None
    for candidate in filter(None, candidates):
        result = subprocess.run(["git", "-C", str(candidate), "archive", SPF_SHA], capture_output=True)
        if result.returncode == 0:
            archive, strip = result.stdout, 0
            break
    if archive is None:
        with urllib.request.urlopen(SPF_TARBALL, timeout=300) as response:
            archive, strip = response.read(), 1
    staging = SPF_CACHE.with_name(SPF_CACHE.name + ".tmp")
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        members = []
        for member in tar.getmembers():
            parts = Path(member.name).parts[strip:]
            if parts:
                member.name = str(Path(*parts))
                members.append(member)
        tar.extractall(staging, members, filter="data")
    staging.rename(SPF_CACHE)
    return SPF_CACHE


def assignment(ui, map_id):
    """The UiMapAssignment row placing a uiMap on its world map, as SPF's own screenshots.py picks it."""
    rows = [
        r
        for r in ui.table("UiMapAssignment").values()
        if r["UiMapID"] == str(map_id) and r["WMODoodadPlacementID"] == "0"
    ]
    return min(rows, key=lambda row: (int(row["OrderIndex"]), int(row["ID"])))


def world_point(ui, map_id, x, y):
    """A uiMap position in world coordinates (x north, y west), inverting SPF's projection; ns.WorldPoint needs the
    client's C_Map."""
    r = assignment(ui, map_id)
    nx = (x - float(r["UiMin_0"])) / (float(r["UiMax_0"]) - float(r["UiMin_0"]))
    ny = (y - float(r["UiMin_1"])) / (float(r["UiMax_1"]) - float(r["UiMin_1"]))
    west = float(r["Region_4"]) - nx * (float(r["Region_4"]) - float(r["Region_1"]))
    north = float(r["Region_3"]) - ny * (float(r["Region_3"]) - float(r["Region_0"]))
    return {"map": int(r["MapID"]), "x": north, "y": west}


def map_position(ui, map_id, point):
    r = assignment(ui, map_id)
    nx = (float(r["Region_4"]) - point[1]) / (float(r["Region_4"]) - float(r["Region_1"]))
    ny = (float(r["Region_3"]) - point[0]) / (float(r["Region_3"]) - float(r["Region_0"]))
    return tuple(
        float(r[f"UiMin_{i}"]) + n * (float(r[f"UiMax_{i}"]) - float(r[f"UiMin_{i}"])) for i, n in enumerate((nx, ny))
    )


def spf_walks(ui, legs):
    """Path.FindSync's points for each (uiMap, from, to) leg, in world coordinates."""
    root = spf_sources()
    entries = []
    for map_id, a, b in legs:
        start, goal = world_point(ui, map_id, *a), world_point(ui, map_id, *b)
        assert start["map"] == goal["map"]
        entries.append(
            f"{{ map = {start['map']}, from = {{ x = {start['x']:.4f}, y = {start['y']:.4f} }}, "
            f"to = {{ x = {goal['x']:.4f}, y = {goal['y']:.4f} }} }}"
        )
    program = "local LEGS = { " + ", ".join(entries) + " }\n" + SPF_PROGRAM
    result = subprocess.run(["luajit", "-"], input=program, text=True, cwd=root, capture_output=True)
    if result.returncode:
        sys.exit("Shortest Path's Path.FindSync failed:\n" + result.stderr)
    return json.loads(result.stdout)


def breadcrumbs(canvas, rects, lines, marks):
    """Route.lua's walk: breadcrumbs every SPF_SPACING along each polyline (normalised map points), the distance
    carried across its bends, each dot over a larger dark rim, every rim beneath every dot (ARTWORK -1)."""
    import math

    dots = []
    for index, line in enumerate(lines):
        points = [map_point(rects, x, y) for x, y in line]
        walked = 0.0
        for (ax, ay), (bx, by) in zip(points, points[1:], strict=False):
            length = math.hypot(bx - ax, by - ay)
            distance = math.ceil(walked / SPF_SPACING) * SPF_SPACING - walked
            while length and distance <= length:
                x, y = ax + (bx - ax) * distance / length, ay + (by - ay) * distance / length
                # Route.lua: a 10-unit stop radius, a 2-unit gap, and the dot's radius plus rim.
                margin = 10 + 2 + SPF_DOT / 2 + SPF_RIM
                if all((x - cx) ** 2 + (y - cy) ** 2 >= margin**2 for cx, cy, _ in marks):
                    dots.append((x, y, 0.4 if index else 1))
                distance += SPF_SPACING
            walked += length
    k = canvas.ui.scale
    for radius, color in ((SPF_DOT / 2 + SPF_RIM, SPF_UNDER), (SPF_DOT / 2, (*drawing.wm.NORMAL, 1))):
        layer = drawing.wm.Image.new("RGBA", canvas.image.size)
        draw = drawing.wm.ImageDraw.Draw(layer)
        for x, y, alpha in dots:
            draw.ellipse(
                ((x - radius) * k, (y - radius) * k, (x + radius) * k, (y + radius) * k),
                fill=drawing.wm.rgba255((*color[:3], color[3] * alpha)),
            )
        canvas.image.alpha_composite(layer)


# A stop's kind as SPF's Looks.lua draws it, fitted within a 16-unit badge.
STOP_ATLASES = {
    "pickup": "QuestNormal",
    "turnin": "QuestTurnin",
    "objective": "questobjective",
    "dungeon": "dungeon",
    "innkeeper": "innkeeper",
}
STOP_FILES = {
    "trainer": "Interface\\Minimap\\Tracking\\Class",
    "battlemaster": "Interface\\Minimap\\Tracking\\BattleMaster",
}


def stop_groups(rects, stops):
    """Map.lua's OverlapGroups with StopPin.lua's 20-unit button and the map's 0.8 overlap factor."""
    points = [map_point(rects, stop["x"], stop["y"]) for stop in stops]
    groups = []
    for number, (x, y) in enumerate(points):
        touching = [
            group for group in groups if any(abs(x - points[i][0]) < 16 and abs(y - points[i][1]) < 16 for i in group)
        ]
        for group in touching:
            groups.remove(group)
        groups.append(sorted([number, *(i for group in touching for i in group)]))
    marks = []
    for group in sorted(groups):
        # Route.lua: the current stop stays put; later shared buttons sit at their group's middle.
        x, y = points[0] if group[0] == 0 else (sum(points[i][a] for i in group) / len(group) for a in (0, 1))
        marks.append((x, y, group))
    return marks


def goal_pins(canvas, stops, marks):
    """SPF StopPin.lua and Map.xml: warm gold stock quest disc, numeral and action badge.
    Later foreground art fades to 0.9 over an opaque black silhouette."""
    ui = canvas.ui
    button = ui.atlas("UI-QuestPoi-QuestNumber")
    numerals = ui.texture("interface/worldmap/ui-questpoi-numbericons.blp")
    for cx, cy, group in marks:
        number, alpha = group[0] + 1, 0.9 if group[0] else 1
        canvas.draw(button, cx - 16, cy - 16, 32, 32, (0, 0, 0, 1))
        canvas.draw(button, cx - 16, cy - 16, 32, 32, (1, 0.9, 0.7, alpha))
        if number <= 25:
            left, top = (number - 1) % 8 * 0.125, 0.5 + (number - 1) // 8 * 0.125
            numeral = drawing.wm.crop_coords(numerals, left, left + 0.125, top, top + 0.125)
            canvas.draw(numeral, cx - 16, cy - 16, 32, 32, (1, 0.9, 0.7, alpha))
        else:
            draw_font_string(canvas, {"text": str(number), "font": "GameFontNormal"}, (cx - 16, cy - 16, 32, 32), alpha)
        kind = stops[group[0]].get("kind")
        if kind in STOP_ATLASES or kind in STOP_FILES:
            art = ui.atlas(STOP_ATLASES[kind]) if kind in STOP_ATLASES else texture(ui, STOP_FILES[kind])
            scale = 16 / max(art.width, art.height)
            width, height = art.width * scale, art.height * scale
            canvas.draw(art, cx + 14 - width, cy + 14 - height, width, height, (1, 1, 1, alpha))


def sibling(repository):
    """A clone beside this repository's main worktree, when this checkout is a linked worktree."""
    common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True)
    if common.returncode:
        return None
    return (ROOT / common.stdout.strip()).resolve().parent.parent / repository
