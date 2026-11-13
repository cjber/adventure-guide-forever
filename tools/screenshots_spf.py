"""Fetch the pinned Shortest Path sources and draw its route and stop pins."""

import io
import json
import math
import os
import subprocess
import sys
from pathlib import Path

import screenshots_art as drawing
from screenshots_resolver import map_point

ROOT = Path(__file__).resolve().parent.parent
NUMBER_DIR = drawing.FOREVER_CORE / "media" / "Numbers"
NUMBER_IMAGES = {}

# SPF #52's stock quest POIs. Its geometry is SPF's own Path.FindSync, run by LuaJIT in an extracted copy.
# The API contract fixture keeps its independent compatibility pin in tests/contract_spec.lua.
SPF_SHA = "9c2d86bad8418ee07c74b54e2757568b9d5aff3f"
SPF_TARBALL = f"https://codeload.github.com/cjber/shortest-path-forever/tar.gz/{SPF_SHA}"
SPF_CACHE = ROOT / "tools/.cache" / f"spf-{SPF_SHA}"
# Route.lua: walks are DOT 4 breadcrumbs every SPACING 9, each over a dark dot RIM 1 wider at UNDER_ALPHA .5; the walk
# colour is NORMAL_FONT_COLOR.
SPF_DOT, SPF_RIM, SPF_SPACING, SPF_UNDER = 4, 1, 9, (0.04, 0.04, 0.04, 0.5)

SPF_PROGRAM = r"""
local ns = {}
local files = {
    "Data/Routes", "Data/Transports", "Data/Portals", "Data/Taxi",
    "Transport/Model", "Routing/PathGrid", "Routing/Path", "Routing/Planner",
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

# A whole journey as Shortest Path plans and words it: its own planner and LegStep/LegTime strings, run offline by its
# journey test driver on the same pinned sources. The driver answers C_Map from its fixture, so the two facts it cannot
# take from the client are named here: the flight points this character has flown, and the zone each boat pier this
# route can touch stands in (C_Map.GetMapInfo in game, Data/Zones.lua's box otherwise).
SPF_ITINERARY_PROGRAM = r"""
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, file in ipairs({
	"Data/Routes.lua", "Data/Transports.lua", "Data/Taxi.lua", "Data/Portals.lua", "Data/Walks.lua",
	"Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua",
}) do driver.load(file) end
for _, map in ipairs({ 0, 1 }) do assert(loadfile("tools/load_nav.lua"))(map) end
ns.NowMs = function() return 123456 end
local nextFrame
ns.Path.after = function(fn) nextFrame = fn end
ns.faction, ns.speed, ns.water = "Horde", 7, false
-- Booty Bay (both flight masters) and Grom'gol: the points a character who has been to Redridge has flown.
ns.known = {}
for _, id in ipairs({ 18, 19, 20 }) do ns.known[id] = true end
local DOCK_ZONE = { [1] = "The Barrens", [2] = "Stranglethorn Vale" }
local SCHEDULED = { boat = true, zeppelin = true, lift = true, tram = true }
-- JourneySteps.lua's own words, so a step names the same place in both addons' trackers.
local STEP = {
	walk = "Walk to %s", flight = "Fly to %s", boat = "Boat to %s", zeppelin = "Zeppelin to %s", lift = "Lift to %s",
	tram = "Tram to %s", portal = "Portal to %s", passage = "Go through to %s", teleport = "Teleport to %s",
}
local function dockPlace(id)
	local dock = ns.Docks[id]
	local name, best = nil, math.huge
	for _, taxi in pairs(ns.TaxiNodes) do
		if taxi.map == dock.map then
			local distance = (taxi.x - dock.x) ^ 2 + (taxi.y - dock.y) ^ 2
			if distance < best then name, best = taxi.name:match("^[^,]+"), distance end
		end
	end
	return name or "dock"
end
-- Map.lua's DockPierName for a pier with no other of its kind within 800 yards: "Ratchet dock", "Booty Bay dock".
local function dockTitle(id)
	local dock = ns.Docks[id]
	if dock.site then return dock.site .. ", " .. dock.name end
	return dockPlace(id) .. " dock"
end
local function label(leg)
	if leg.to.kind == "dock" then
		if leg.mode == "walk" then return dockTitle(leg.to.id) end
		return assert(DOCK_ZONE[leg.to.id], "no zone for dock " .. leg.to.id)
	end
	if leg.to.kind == "taxi" then return ns.TaxiName(leg.to.id) end
	return ns.LegStep(leg)
end
local function countdown(ms)
	local seconds = math.max(0, math.ceil(ms / 1000))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function legTime(leg)
	local text = countdown(leg.arrive - leg.depart)
	if leg.wait and leg.wait > 0 then
		local lead = leg.mode == "teleport" and "ready in %s"
			or leg.estimated and SCHEDULED[leg.mode] and "leaves in about %s"
			or "leaves in %s"
		text = string.format("%s · %s", string.format(lead, countdown(leg.wait)), text)
	end
	return text
end
local function drain()
	local frames = 0
	while nextFrame do
		local fn = nextFrame
		nextFrame = nil
		fn()
		frames = frames + 1
		assert(frames < 20000, "the journey search did not settle")
	end
end
local from = { map = FROM_MAP, x = FROM_X, y = FROM_Y, z = 0 }
local goal = { map = TO_MAP, x = TO_X, y = TO_Y, z = 0 }
driver.begin(from, goal)
drain()
local plan = assert(driver.shown(), "Shortest Path found no route")
local rows, total, yards = {}, 0, 0
for index, leg in ipairs(plan.legs) do
	local ride, wait = (leg.arrive - leg.depart) / 1000, (leg.wait or 0) / 1000
	total = total + math.ceil(ride) + math.ceil(wait)
	local place = index == #plan.legs and leg.mode == "walk" and GOAL or label(leg)
	local text = string.format("%d. %s", index, string.format(STEP[leg.mode], place))
	if leg.mode == "walk" and leg.to.undiscovered then text = string.format("%s (new flight path)", text) end
	rows[index] = { text = text .. "   " .. legTime(leg), current = index == 1 }
	local ok, points = pcall(ns.PlanContext.LegPoints, leg)
	if ok and points and leg.mode == "walk" then
		for at = 2, #points do
			local a, b = points[at - 1], points[at]
			if a.map == b.map and not a.jump then
				yards = yards + math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
			end
		end
	end
end
local lines = {}
for index, row in ipairs(rows) do
	lines[index] = string.format('{"text": %q, "current": %s}', row.text, tostring(row.current))
end
local pattern = '{"seconds": %d, "yards": %d, "rows": [%s]}'
print(string.format(pattern, total, math.floor(yards + 0.5), table.concat(lines, ",")))
"""


def spf_sources():
    """SPF_CACHE, extracted from a local clone ($SPF, else a sibling of this checkout or of its main worktree) with
    `git archive`, else from GitHub's tarball of the sha."""
    if (SPF_CACHE / "Routing/Path.lua").is_file():
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


def spf_walk(ui, map_id, a, b):
    """Path.FindSync's points for the walk from `a` to `b` on a uiMap, in world coordinates."""
    root = spf_sources()
    start, goal = world_point(ui, map_id, *a), world_point(ui, map_id, *b)
    assert start["map"] == goal["map"]
    leg = (
        f"{{ map = {start['map']}, from = {{ x = {start['x']:.4f}, y = {start['y']:.4f} }}, "
        f"to = {{ x = {goal['x']:.4f}, y = {goal['y']:.4f} }} }}"
    )
    program = "local LEGS = { " + leg + " }\n" + SPF_PROGRAM
    result = subprocess.run(["luajit", "-"], input=program, text=True, cwd=root, capture_output=True)
    if result.returncode:
        sys.exit("Shortest Path's Path.FindSync failed:\n" + result.stderr)
    (walk,) = json.loads(result.stdout)
    return walk


def countdown(seconds):
    """Whole seconds as Shortest Path's tracker shows them (Transport/Model.lua's FormatCountdown)."""
    seconds = max(0, math.ceil(seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


def distance(yards):
    """Yards as Shortest Path's tracker shows them (Core/Distance.lua's FormatDistance, compact)."""
    return f"{yards / 1000:.1f}k yd" if yards >= 999.5 else f"{round(yards)} yd"


def spf_itinerary(ui, start, goal, goal_label):
    """Shortest Path's own plan from `start` to `goal` (uiMap positions) with its rows as its tracker words them:
    the numbered steps, the boat's wait and the flight. `goal_label` is the zone its destination node names, which
    the offline driver cannot resolve."""
    a, b = world_point(ui, start["map"], start["x"], start["y"]), world_point(ui, goal["map"], goal["x"], goal["y"])
    program = SPF_ITINERARY_PROGRAM
    for name, value in (
        ("FROM_MAP", a["map"]),
        ("FROM_X", f"{a['x']:.4f}"),
        ("FROM_Y", f"{a['y']:.4f}"),
        ("TO_MAP", b["map"]),
        ("TO_X", f"{b['x']:.4f}"),
        ("TO_Y", f"{b['y']:.4f}"),
        ("GOAL", json.dumps(goal_label)),
    ):
        program = program.replace(name, str(value))
    result = subprocess.run(["luajit", "-"], input=program, text=True, cwd=spf_sources(), capture_output=True)
    if result.returncode:
        sys.exit("Shortest Path's planner failed:\n" + result.stderr)
    plan = json.loads(result.stdout)
    plan["header"] = f"Journey  {countdown(plan['seconds'])} · {distance(plan['yards'])}"
    return plan


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
    "trainer": "Class",
    "battlemaster": "BattleMaster",
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


def marker(number):
    """The gold numbered marker art ForeverCore ships (media/Numbers in the core checkout)."""
    number = max(1, min(number, 10))
    if number not in NUMBER_IMAGES:
        NUMBER_IMAGES[number] = drawing.wm.Image.open(NUMBER_DIR / f"{number}.tga").convert("RGBA")
    return NUMBER_IMAGES[number]


def goal_pins(canvas, stops, marks):
    """SPF StopPin.lua and Map.xml: our numbered marker and action badge. A later stop's marker fades to 0.7."""
    ui = canvas.ui
    for cx, cy, group in marks:
        number, alpha = group[0] + 1, 0.7 if group[0] else 1
        canvas.draw(marker(number), cx - 12, cy - 12, 24, 24, (1, 1, 1, alpha))
        kind = stops[group[0]].get("kind")
        if kind in STOP_ATLASES:
            art = ui.atlas(STOP_ATLASES[kind])
            scale = 16 / max(art.width, art.height)
            width, height = art.width * scale, art.height * scale
            canvas.draw(art, cx + 14 - width, cy + 14 - height, width, height, (1, 1, 1, alpha))


def sibling(repository):
    """A clone beside this repository's main worktree, when this checkout is a linked worktree."""
    common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True)
    if common.returncode:
        return None
    return (ROOT / common.stdout.strip()).resolve().parent.parent / repository
