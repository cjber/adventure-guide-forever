#!/usr/bin/env python3
"""Generate conservative Classic quest recommendations for Forever (stdlib only).

CMaNGOS prerequisite semantics: positive PrevQuestId requires completion; negative
requires an active parent and is deliberately unsupported. NextQuestId contributes
reverse prerequisites (including its sign). NextQuestInChain is display-only.
Positive ExclusiveGroup closes siblings; a negative group on a predecessor requires
all its members. Alternatives of different all-of groups cannot be represented by
AGFQuest and are suppressed, never flattened into an easier requirement.
https://github.com/cmangos/issues/wiki/Quest_template
"""

import argparse
import csv
import gzip
import io
import json
import math
import re
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

BUILD = "1.60.1.69913"
# The last build with WorldMapArea: quest_poi's mapAreaId is one of its IDs, which UiMap replaced in 8.0.
LEGACY_MAP_BUILD = "7.3.5.26972"
CLASSICDB_COMMIT = "22b51464f1625f6ef6275771de1f5466c6f5d19e"
CLASSICDB_URL = (
    f"https://raw.githubusercontent.com/cmangos/classic-db/{CLASSICDB_COMMIT}/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
)
ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
OUTPUT = ROOT / "Data" / "Quests.lua"
ZONE_SOURCE = "https://warcraft.wiki.gg/wiki/Zones_by_level_(original)"
# Same published ranges as tweaks-forever/tools/gen_zonelevels.py. Cities have no range.
PUBLISHED = {
    1411: (1, 10),
    1412: (1, 10),
    1413: (10, 25),
    1416: (30, 40),
    1417: (30, 40),
    1418: (35, 45),
    1419: (45, 55),
    1420: (1, 10),
    1421: (10, 20),
    1422: (51, 58),
    1423: (53, 60),
    1424: (20, 30),
    1425: (40, 50),
    1426: (1, 10),
    1427: (45, 50),
    1428: (50, 58),
    1429: (1, 10),
    1430: (55, 60),
    1431: (18, 30),
    1432: (10, 20),
    1433: (15, 25),
    1434: (30, 45),
    1435: (35, 45),
    1436: (10, 20),
    1437: (20, 30),
    1438: (1, 10),
    1439: (10, 20),
    1440: (18, 30),
    1441: (25, 35),
    1442: (15, 27),
    1443: (30, 40),
    1444: (40, 50),
    1445: (35, 45),
    1446: (40, 50),
    1447: (45, 55),
    1448: (48, 55),
    1449: (48, 55),
    1450: (55, 60),
    1451: (55, 60),
    1452: (53, 60),
}
TABLES = {
    "game_event_creature",
    "game_event_gameobject",
    "game_event_quest",
    "quest_template",
    "creature",
    "gameobject",
    "creature_template",
    "gameobject_template",
    "creature_questrelation",
    "gameobject_questrelation",
    "creature_involvedrelation",
    "gameobject_involvedrelation",
    "npc_trainer",
    "npc_trainer_template",
    "battlemaster_entry",
    "quest_poi",
    "quest_poi_points",
    "areatrigger_involvedrelation",
    "creature_loot_template",
    "gameobject_loot_template",
    "reference_loot_template",
}
TOKEN = re.compile(r"\s*('(?:[^'\\]|\\.|'')*'|NULL|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[(),;])", re.DOTALL)
ESCAPES = {"0": "\0", "n": "\n", "r": "\r", "t": "\t", "b": "\b", "Z": "\x1a"}


def download(url, filename, refresh=False, offline=False):
    path = CACHE / filename
    if path.exists() and not refresh:
        return path.read_bytes()
    if offline:
        raise ValueError(f"Missing cached source: {path}")
    request = urllib.request.Request(url, headers={"User-Agent": "AdventureGuideForever/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        content = response.read()
    if content.lstrip().startswith(b"<"):
        raise ValueError(f"Expected data, received HTML: {url}")
    CACHE.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(content)
    temporary.replace(path)
    return content


def db2(name, columns, build=BUILD, **options):
    content = download(f"https://wago.tools/db2/{name}/csv?build={build}", f"{name}-{build}.csv", **options)
    reader = csv.DictReader(io.StringIO(content.decode("utf-8-sig")), strict=True)
    if not set(columns) <= set(reader.fieldnames or []):
        raise ValueError(f"{name}: missing required columns {columns}")
    rows = list(reader)
    if not rows:
        raise ValueError(f"{name}: empty export")
    return rows


def parse_values(text):
    """Read mysqldump VALUES literals, including MySQL string escapes; never execute SQL."""
    position, row, expect = 0, [], "("
    length = len(text.rstrip())
    while position < length:
        match = TOKEN.match(text, position)
        if not match:
            raise ValueError(f"Invalid SQL literal near {text[position : position + 40]!r}")
        token, position = match[1], match.end()
        if expect == "(":
            if token != "(":
                raise ValueError("Expected SQL row")
            row, expect = [], "value"
        elif expect == "value":
            if token.startswith("'"):
                value = re.sub(r"\\(.)|''", lambda m: ESCAPES.get(m[1], m[1]) if m[1] else "'", token[1:-1])
            elif token == "NULL":
                value = None
            elif token in "(),;":
                raise ValueError("Expected SQL value")
            else:
                value = float(token) if any(c in token for c in ".eE") else int(token)
            row.append(value)
            expect = ",)"
        elif expect == ",)":
            if token == ")":
                yield row
                expect = ",;"
            elif token == ",":
                expect = "value"
            else:
                raise ValueError("Expected SQL value separator")
        elif token == ",":
            expect = "("
        elif token == ";" and not text[position:].strip():
            return
        else:
            raise ValueError("Expected SQL row separator")
    raise ValueError("Truncated SQL VALUES")


def read_tables(lines):
    columns, tables, current = {}, defaultdict(list), None
    for line in lines:
        create = re.match(r"CREATE TABLE `(\w+)`", line)
        if create:
            current = create[1] if create[1] in TABLES else None
            if current:
                columns[current] = []
        elif current and (column := re.match(r"\s+`([^`]+)`", line)):
            columns[current].append(column[1])
        elif line.startswith(") ENGINE"):
            current = None
        elif insert := re.match(r"INSERT INTO `(\w+)` VALUES ", line):
            table = insert[1]
            if table in TABLES:
                for values in parse_values(line[insert.end() :]):
                    tables[table].append(dict(zip(columns[table], values, strict=True)))
    if TABLES - tables.keys():
        raise ValueError(f"Missing SQL tables: {sorted(TABLES - tables.keys())}")
    return tables


def prerequisite_index(quests):
    incoming, groups = defaultdict(set), defaultdict(set)
    for qid, row in quests.items():
        if row["NextQuestId"]:
            target = row["NextQuestId"]
            incoming[abs(target)].add(qid if target > 0 else -qid)
        if row["ExclusiveGroup"]:
            groups[row["ExclusiveGroup"]].add(qid)
    return incoming, groups


def prerequisites(qid, quests, incoming, groups):
    """Return (all, any, unknown). Negative requirements must never become completions."""
    previous = quests[qid]["PrevQuestId"]
    candidates = set(incoming.get(qid, ()))
    if previous:
        candidates.add(previous)
    if any(q < 0 or q not in quests for q in candidates):
        return [], [], True
    alternatives = set()
    for q in candidates:
        group = quests[q]["ExclusiveGroup"]
        alternatives.add(tuple(sorted(groups[group])) if group < 0 else (q,))
    if not alternatives:
        return [], [], False
    if len(alternatives) == 1:
        return list(next(iter(alternatives))), [], False
    if all(len(a) == 1 for a in alternatives):
        return [], sorted(a[0] for a in alternatives), False
    return [], [], True


def project(row, world_x, world_y, world_z=0):
    """World north/west axes -> normalized UI east/south axes, respecting the UI sub-rectangle."""
    low_x, low_y, low_z, high_x, high_y, high_z = (float(row[f"Region_{i}"]) for i in range(6))
    if not (low_x <= world_x <= high_x and low_y <= world_y <= high_y and low_z <= world_z <= high_z):
        return None
    if high_x == low_x or high_y == low_y:
        return None
    fractions = ((high_y - world_y) / (high_y - low_y), (high_x - world_x) / (high_x - low_x))
    result = tuple(
        float(row[f"UiMin_{i}"]) + fraction * (float(row[f"UiMax_{i}"]) - float(row[f"UiMin_{i}"]))
        for i, fraction in enumerate(fractions)
    )
    return result if all(0 <= value <= 1 for value in result) else None


def map_indexes(ui_maps, assignments):
    maps = {int(r["ID"]): r for r in ui_maps}
    world, areas = defaultdict(list), defaultdict(set)
    for row in assignments:
        ui_map = int(row["UiMapID"])
        if ui_map not in maps:
            continue
        if int(row["AreaID"]):
            areas[int(row["AreaID"])].add(ui_map)
        if int(maps[ui_map]["Type"]) == 3 and int(row["WMODoodadPlacementID"]) == 0:
            world[int(row["MapID"])].append(row)
    return maps, world, areas


def span(row, axis):
    """Yards per unit of UI axis 0 (east, from world y) or 1 (south, from world x), as `project` maps them."""
    low, high = (float(row[f"Region_{i}"]) for i in ((1, 4) if axis == 0 else (0, 3)))
    return (high - low) / (float(row.get(f"UiMax_{axis}", 1)) - float(row.get(f"UiMin_{axis}", 0)))


def geometry(assignments, wanted, names):
    """Each map's name, continent (the world MapID), the world-coordinate centre of its rectangle and its size in
    yards along map x (`sx`) and map y (`sy`), so the planner can measure between steps on different maps without
    asking Shortest Path. A map without exactly one whole-map row is left out.
    """
    rows = defaultdict(list)
    for row in assignments:
        if int(row["UiMapID"]) in wanted and int(row["WMODoodadPlacementID"]) == 0:
            rows[int(row["UiMapID"])].append(row)
    result = {}
    for ui_map, found in sorted(rows.items()):
        if len(found) == 1:
            row = found[0]
            result[ui_map] = {
                "name": names[ui_map],
                "continent": int(row["MapID"]),
                "cx": round((float(row["Region_0"]) + float(row["Region_3"])) / 2, 1),
                "cy": round((float(row["Region_1"]) + float(row["Region_4"])) / 2, 1),
                "sx": round(span(row, 0), 1),
                "sy": round(span(row, 1), 1),
            }
    return result


def continents(ui_maps, assignments, wanted):
    """Where each continent sits on the world map (UiMap Type 1, Azeroth), so steps an ocean apart get a distance.

    A continent's world frame is shifted onto the world map's: x = shift x - world y and y = shift y - world x, in
    yards, with map x and y growing the same way as on a zone map. Only a continent with exactly one whole-continent
    row on one world map is emitted.
    """
    world_maps = {int(r["ID"]) for r in ui_maps if int(r["Type"]) == 1}
    rows = defaultdict(list)
    for row in assignments:
        if int(row["UiMapID"]) in world_maps and int(row["WMODoodadPlacementID"]) == 0:
            rows[int(row["MapID"])].append(row)
    result = {}
    for continent, found in sorted(rows.items()):
        if continent in wanted and len(found) == 1:
            row = found[0]
            result[continent] = {
                "x": round(float(row["Region_4"]) + span(row, 0) * float(row["UiMin_0"]), 1),
                "y": round(float(row["Region_3"]) + span(row, 1) * float(row["UiMin_1"]), 1),
            }
    return result


DOCK_REACH = 600  # yards from a dock to the flight masters that say which side it serves (Orgrimmar's: 496)


def crossings(templates, path_nodes, taxi_nodes, wanted):
    """Every boat or zeppelin between two continents: where it docks on each (its path's two stops) and the sides
    it serves, so the planner measures an ocean crossing from the dock it leaves from to the one it lands at.

    A transport (gameobject type 15) follows the TaxiPath in data0; its stops are the nodes with a delay. A dock
    serves the sides whose flight masters (TaxiNodes Flags 1 Alliance, 2 Horde) stand within DOCK_REACH of it, and
    the transport serves the sides both docks do. Positions are world coordinates on each dock's continent.
    """
    stops = defaultdict(list)
    for node in sorted(path_nodes, key=lambda n: (int(n["PathID"]), int(n["NodeIndex"]))):
        if int(node["Delay"]) > 0:
            dock = {"continent": int(node["ContinentID"]), "x": float(node["Loc_0"]), "y": float(node["Loc_1"])}
            stops[int(node["PathID"])].append(dock)

    def sides(dock):
        mask = 0
        for node in taxi_nodes:
            near = (float(node["Pos_0"]) - dock["x"]) ** 2 + (float(node["Pos_1"]) - dock["y"]) ** 2
            if int(node["ContinentID"]) == dock["continent"] and near <= DOCK_REACH**2:
                mask |= int(node["Flags"]) & 3
        return mask

    result = []
    for row in sorted(templates, key=lambda r: r["entry"]):
        docks = stops.get(row["data0"], []) if row["type"] == 15 else []
        if len(docks) != 2 or docks[0]["continent"] == docks[1]["continent"]:
            continue
        side = sides(docks[0]) & sides(docks[1])
        if side and {d["continent"] for d in docks} <= wanted:
            a, b = ({**d, "x": round(d["x"], 1), "y": round(d["y"], 1)} for d in docks)
            result.append({"transport": row["entry"], "side": side, "a": a, "b": b})
    return result


LINK = 100  # yards: two givers this close stand in one town
CAP = 400  # yards: a town wider than this is split again at a shorter link (only the capitals are)


def world_point(centre, place):
    """A place's world x and y in yards: the inverse of `project`, through its map's `geometry` rectangle."""
    return centre["cx"] - (place["y"] - 0.5) * centre["sy"], centre["cy"] - (place["x"] - 0.5) * centre["sx"]


def link(points, reach):
    """Single linkage: the groups of `points` (x, y, key) joined by chains of steps of at most `reach` yards."""
    parent = list(range(len(points)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    cells = defaultdict(list)
    for i, (x, y, _) in enumerate(points):
        cells[math.floor(x / reach), math.floor(y / reach)].append(i)
    for (cx, cy), members in cells.items():
        for other in (cells.get((cx + dx, cy + dy), ()) for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            for j in other:
                for i in members:
                    a, b = points[i], points[j]
                    if i < j and (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 <= reach**2:
                        parent[find(i)] = find(j)
    groups = defaultdict(list)
    for i, point in enumerate(points):
        groups[find(i)].append(point)
    return list(groups.values())


def diameter(points):
    return max((math.dist(a[:2], b[:2]) for a in points for b in points), default=0)


def split(points, reach):
    """Groups at `reach`; each one wider than CAP is grouped again at `reach` - 10, recursively. One shorter cut for
    the whole world would break towns apart (at 60 yards Darkshire loses its crier), so only wide groups are cut.
    """
    result = []
    for group in link(points, reach):
        if reach > 10 and diameter(group) > CAP:
            result.extend(split(group, reach - 10))
        else:
            result.append(group)
    return result


def town_hubs(points):
    """Towns from quest places: `points` maps a key to (continent, x, y) in world yards. Each continent is grouped
    apart. Returns every hub as (continent, members), members being (x, y, key), in ID order from 1: by continent,
    then the hub's least x, then its least y.
    """
    by_continent = defaultdict(list)
    for key, (continent, x, y) in sorted(points.items()):
        by_continent[continent].append((x, y, key))
    hubs = [(continent, group) for continent, members in by_continent.items() for group in split(members, LINK)]
    return sorted(hubs, key=lambda h: (h[0], min(p[0] for p in h[1]), min(p[1] for p in h[1]), sorted(h[1])))


NAME_REACH = 150  # yards from a town's nearest giver to the flight master that names it
# Copied from shortest-path-forever/tools/gen_transit.py RESTRICTED_NODES: Nighthaven is druid-only, and the
# Plaguewood towers' flights depend on PvP control, so neither is a town's flight master for every player.
RESTRICTED_NODES = {62, 63, 84, 85, 86, 87}


def flight_masters(taxi_nodes):
    """The flight-map nodes any player of a side can use, by shortest-path-forever/tools/gen_transit.py `taxis`'
    filter: the side bits (or Powderfuse's 3275), the three continents, no obsolete or quest node, no condition, a
    mount set. Each as (ID, continent, world x, world y, name).
    """
    result = []
    for row in taxi_nodes:
        node, name = int(row["ID"]), row["Name_lang"]
        if (
            node in RESTRICTED_NODES
            or (not int(row["Flags"]) & 3 and node != 3275)
            or int(row["ContinentID"]) not in (0, 1, 2991)
            or "zzOLD" in name
            or name.startswith("Quest ")
            or int(row["ConditionID"])
            or int(row["VisibilityConditionID"])
            or not (int(row["MountCreatureID_0"]) or int(row["MountCreatureID_1"]))
        ):
            continue
        result.append((node, int(row["ContinentID"]), float(row["Pos_0"]), float(row["Pos_1"]), name))
    return result


def hub_names(hubs, nodes):
    """Each hub's name: its flight master's, the node nearest any of its givers within NAME_REACH (the lower ID on
    a tie), verbatim. The data names no other town, so a hub without one has none.
    """
    names = {}
    for hub, (continent, members) in enumerate(hubs, 1):
        near = [
            (min(math.dist((x, y), member[:2]) for member in members), node, name)
            for node, where, x, y, name in nodes
            if where == continent
        ]
        best = min((n for n in near if n[0] <= NAME_REACH), default=None)
        if best:
            names[hub] = {"name": best[2]}
    return names


def spawns(tables, kind, wanted, world):
    """Every spawn of the `wanted` entries of `kind`, with each zone map whose rectangle contains it.

    Zone rectangles overlap (Durotar's covers the eastern Barrens), so the map is chosen in `pick`, not here. `at` is
    the spawn's continent and world x, y.
    """
    names = {r.get("Entry", r.get("entry")): r.get("Name", r.get("name")) for r in tables[f"{kind}_template"]}
    # A positive event spawns the row only while that event (Midsummer, Hallow's End...) runs.
    seasonal = {r["guid"] for r in tables[f"game_event_{kind}"] if r["event"] > 0}
    result = defaultdict(list)
    for spawn in tables[kind]:
        entry = spawn["id"]
        if entry not in wanted or not names.get(entry) or spawn["guid"] in seasonal:
            continue
        if options := options_at(world[spawn["map"]], spawn["position_x"], spawn["position_y"], spawn["position_z"]):
            at = (spawn["map"], spawn["position_x"], spawn["position_y"])
            result[entry].append({"entry": (kind, entry), "name": names[entry], "options": options, "at": at})
    return result


def options_at(rows, x, y, z=0):
    """Each zone map of `rows` (one world map's) whose rectangle holds world point x, y, z, smallest first, as
    (area, order, UiMap ID, projected x and y)."""
    options = []
    for row in rows:
        xy = project(row, x, y, z)
        if xy is not None:
            area = (float(row["Region_3"]) - float(row["Region_0"])) * (float(row["Region_4"]) - float(row["Region_1"]))
            options.append((area, int(row["OrderIndex"]), int(row["UiMapID"]), xy))
    return sorted(options)


def places(tables, world):
    """Every spawn of a quest giver or ender, by quest; the map is chosen per quest in `pick`."""
    result = {}
    for kind in ("creature", "gameobject"):
        wanted = {r["id"] for suffix in ("questrelation", "involvedrelation") for r in tables[f"{kind}_{suffix}"]}
        found = spawns(tables, kind, wanted, world)
        for suffix in ("questrelation", "involvedrelation"):
            relations = defaultdict(list)
            for relation in tables[f"{kind}_{suffix}"]:
                relations[relation["quest"]].extend(found[relation["id"]])
            result[kind, suffix] = relations
    return result


def homes(locations, quests, areas):
    """Each giver's home map: the zone most of its quests are filed under, among the maps it stands in."""
    votes = defaultdict(Counter)
    for (_, _), relations in locations.items():
        for qid, spawns in relations.items():
            zone_maps = areas.get(quests[qid]["ZoneOrSort"], set()) if qid in quests else set()
            for spawn in spawns:
                for _, _, ui_map, _ in spawn["options"]:
                    if ui_map in zone_maps:
                        votes[spawn["entry"]][ui_map] += 1
    return {entry: max(sorted(counter), key=counter.__getitem__) for entry, counter in votes.items()}


def pick(spawn, zone_maps, home):
    """The quest's own zone first, then the giver's home zone, then the smallest containing map."""
    _, _, ui_map, (x, y) = choose(spawn["options"], zone_maps, home)
    return {"map": ui_map, "x": round(x, 4), "y": round(y, 4), "name": spawn["name"]}


def choose(options, zone_maps, home=None):
    """Of `options_at`'s maps: the quest's own zone first, then `home` (one map, or a set of them), then the
    smallest."""
    homes = home if isinstance(home, set) else {home}
    return (
        next((o for o in options if o[2] in zone_maps), None)
        or next((o for o in options if o[2] in homes), None)
        or options[0]
    )


def legacy_maps(legacy_rows, areas):
    """Each WorldMapArea ID (quest_poi's mapAreaId) to the UiMaps of its area (`map_indexes`' `areas`)."""
    return {int(r["ID"]): areas[int(r["AreaID"])] for r in legacy_rows if int(r["AreaID"]) in areas}


def quest_place(spawn, zone_maps, home):
    """A quest's start or finish at `spawn`: `pick`'s place, plus `npc`, the creature entry, for an NPC (an object's
    entry is no unit's, so it has none)."""
    place = pick(spawn, zone_maps, home)
    kind, entry = spawn["entry"]
    return {**place, "npc": entry} if kind == "creature" else place


EXPLORE = 16  # quest_poi objIndex of an explore objective; 0-3 are ReqCreatureOrGOId1-4 and 4-7 ReqItemId1-4
SLOTS = {*range(8), EXPLORE}  # the objIndex values kept: -1 is the turn-in, and 9-13 are of unknown meaning
SHARE = 0.8  # r: the distance within which this share of a shape's points, or a cluster's spawns, lie
SPAWN_LINK = 100  # yards: spawns this close stand in one fallback area
AREAS = 3  # the most areas for one objective
MIN_DROP = 5  # percent: an item that drops less often than this is not collected from that source
GAMEOBJECT_LOOT = (3, 25)  # gameobject_template type whose data1 is its loot: a chest, a fishing hole
EVENT = 2  # SpecialFlags QUEST_SPECIAL_FLAG_EXPLORATION_OR_EVENT


def objectives(row, explore):
    """A quest's objectives, each slot (the quest_poi objIndex numbering) to the count it needs, in slot order: a kill
    or use target of ReqCreatureOrGOId, an item of ReqItemId other than the one the quest gives at pickup (SrcItemId: a
    delivery, done at the turn-in), and an explore objective when an area trigger completes the quest
    (areatrigger_involvedrelation).
    """
    result = {}
    for i in range(4):
        if row[f"ReqCreatureOrGOId{i + 1}"] and row[f"ReqCreatureOrGOCount{i + 1}"]:
            result[i] = row[f"ReqCreatureOrGOCount{i + 1}"]
    for i in range(4):
        if row[f"ReqItemId{i + 1}"] not in (0, row["SrcItemId"]) and row[f"ReqItemCount{i + 1}"]:
            result[4 + i] = row[f"ReqItemCount{i + 1}"]
    if explore:
        result[EXPLORE] = 1
    return result


def quest_flags(row, explore):
    """`event` for a quest a script completes (SpecialFlags EXPLORATION_OR_EVENT, not an explore quest): an escort, a
    spell cast, a summoned fight; the data cannot tell these apart. `timed`, the seconds it allows (LimitTime)."""
    flags = {}
    if row["SpecialFlags"] & EVENT and not explore:
        flags["event"] = True
    if row["LimitTime"]:
        flags["timed"] = row["LimitTime"]
    return flags


def full_xp(row):
    """The XP a quest gives a player at most 5 levels above it: CMaNGOS Quest::XPValue, RewMoneyMaxLevel / 0.6 rounded
    up for a quest of level 1 to 60 (in whole numbers, which float32's ceilf matches). None for any other level."""
    if 0 < row["QuestLevel"] <= 60 and row["RewMoneyMaxLevel"] > 0:
        return -(-row["RewMoneyMaxLevel"] * 5 // 3)
    return None


def inside(point, polygon):
    """Whether `point` lies inside `polygon` (even-odd rule); fewer than three vertices enclose nothing."""
    if len(polygon) < 3:
        return False
    x, y = point
    result = False
    for (x1, y1), (x2, y2) in zip(polygon, polygon[1:] + polygon[:1], strict=True):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            result = not result
    return result


def reach(centre, points):
    """The distance from `centre` within which SHARE of `points` lie (nearest rank), in whole yards."""
    distances = sorted(math.dist(centre, p) for p in points)
    return round(distances[math.ceil(SHARE * len(distances)) - 1])


def shape_area(points):
    """A quest POI shape's point and reach, in world yards: the mean of its vertices when that lies inside the shape,
    else the vertex nearest it, so the point is always the shape's."""
    mean = (sum(x for x, _ in points) / len(points), sum(y for _, y in points) / len(points))
    point = mean if inside(mean, points) else min(points, key=lambda p: (math.dist(p, mean), p))
    return point, reach(point, points)


def medoid(points):
    """The point of `points` with the least total distance to the rest: always one of them."""
    return min(points, key=lambda p: (sum(math.dist(p[:2], q[:2]) for q in points), p))


def spawn_areas(found, zone):
    """Up to AREAS areas of spawns (`spawns`' entries) on map `zone`, biggest first: each the medoid spawn of a
    group linked at SPAWN_LINK yards, with its reach, as (x, y, r) on the map."""
    at = {}
    for spawn in found:
        if option := next((o for o in spawn["options"] if o[2] == zone), None):
            at[spawn["at"][1:]] = option[3]
    groups = link([(x, y, xy) for (x, y), xy in sorted(at.items())], SPAWN_LINK)
    result = []
    for group in groups:
        centre = medoid(group)
        result.append((len(group), centre[2], reach(centre[:2], [p[:2] for p in group])))
    return [(*xy, r) for _, xy, r in sorted(result, key=lambda a: (-a[0], a[1]))[:AREAS]]


def objective_sources(tables):
    """What to find an objective among: `credit`, the creatures whose kill counts for a creature (KillCredit1-2), and
    `drops`, the (kind, entry) of each creature or game object that drops an item at least MIN_DROP percent of the time
    (a grouped entry of chance 0 shares its group's), following one level of reference loot."""
    credit = defaultdict(set)
    for row in tables["creature_template"]:
        for column in ("KillCredit1", "KillCredit2"):
            if row[column]:
                credit[row[column]].add(row["Entry"])
    owners = {"creature": defaultdict(set), "gameobject": defaultdict(set)}
    for row in tables["creature_template"]:
        if row["LootId"]:
            owners["creature"][row["LootId"]].add(row["Entry"])
    for row in tables["gameobject_template"]:
        if row["type"] in GAMEOBJECT_LOOT and row["data1"] > 0:
            owners["gameobject"][row["data1"]].add(row["entry"])
    references = defaultdict(list)
    for row in tables["reference_loot_template"]:
        references[row["entry"]].append(row)

    def likely(row):
        chance = abs(row["ChanceOrQuestChance"])
        return chance >= MIN_DROP or (chance == 0 and row["groupid"] > 0)

    drops = defaultdict(set)
    for kind, loot in owners.items():
        for row in tables[f"{kind}_loot_template"]:
            items = references[-row["mincountOrRef"]] if row["mincountOrRef"] < 0 else [row]
            for item in (i for i in items if likely(row) and i["mincountOrRef"] >= 0 and likely(i)):
                drops[item["item"]] |= {(kind, entry) for entry in loot[row["entry"]]}
    return credit, drops


def objective_targets(row, slot, credit, drops):
    """The (kind, entry) of whatever an objective slot is done at: its creature and those that give kill credit for
    it, its game object, or its item's sources."""
    if slot < 4:
        target = row[f"ReqCreatureOrGOId{slot + 1}"]
        if target < 0:
            return {("gameobject", -target)}
        return {("creature", entry) for entry in {target} | credit[target]}
    if slot < 8:
        return drops[row[f"ReqItemId{slot - 3}"]]
    return set()


def quest_shapes(tables):
    """Each quest's quest_poi objective shapes as (slot, world map, points in world x, y, WorldMapArea ID), in poiId
    order; a shape of an objIndex outside SLOTS is left out."""
    points = defaultdict(list)
    for row in tables["quest_poi_points"]:
        points[row["questId"], row["poiId"]].append((row["x"], row["y"]))
    result = defaultdict(list)
    for row in sorted(tables["quest_poi"], key=lambda r: (r["questId"], r["poiId"])):
        if row["objIndex"] in SLOTS and (shape := points[row["questId"], row["poiId"]]):
            result[row["questId"]].append((row["objIndex"], row["mapId"], shape, row["mapAreaId"]))
    return result


def objective_areas(slots, shapes, found, world, zone_maps, zone, legacy):
    """Where a quest's objectives are done, as [i, x, y, r] or [i, x, y, r, map]: `i` the slot, x and y on the map in
    thousandths, r in yards; the map is left out when it is `zone`, the quest's zone.

    Each quest_poi shape (Blizzard's objective area, (slot, world map, points, WorldMapArea ID)) of one of the quest's
    `slots` gives its `shape_area`, on `zone` or one of the quest's zone maps where one holds it, else on the map its
    WorldMapArea names (`legacy`), else the smallest (`choose`); shapes on the quest's own maps come first, then the
    widest. A slot without a shape falls back to `spawn_areas` of its `found` spawns on `zone`. A slot keeps at most
    AREAS areas, and one with neither source has none.
    """
    own = zone_maps | {zone} if zone is not None else zone_maps
    placed = defaultdict(list)
    for slot, world_map, points, area_map in shapes:
        (x, y), r = shape_area(points)
        if slot in slots and (options := options_at(world[world_map], x, y)):
            _, _, ui_map, (px, py) = choose(options, own, legacy.get(area_map, set()))
            placed[slot].append((ui_map not in own, -r, ui_map, px, py, r))
    areas = []
    for slot in slots:
        if placed[slot]:
            chosen = [a[2:] for a in sorted(placed[slot])[:AREAS]]
        else:
            chosen = [(zone, x, y, r) for x, y, r in spawn_areas(found[slot], zone)] if zone is not None else []
        for ui_map, x, y, r in chosen:
            areas.append([slot, round(x * 1000), round(y * 1000), r] + ([] if ui_map == zone else [ui_map]))
    return areas


def faction(mask):
    return 3 if mask == 0 else (1 if mask & 77 else 0) + (2 if mask & 178 else 0)


def instance_index(area_rows, map_rows):
    """Each area inside a dungeon (InstanceType 1) or raid (2): its instance Map.ID; and each such map's name."""
    kinds = {int(r["ID"]): (int(r["InstanceType"]), r["MapName_lang"]) for r in map_rows}
    by_area, names = {}, {}
    for row in area_rows:
        map_id = int(row["ContinentID"])
        kind, name = kinds.get(map_id, (0, ""))
        if kind in (1, 2):
            by_area[int(row["ID"])] = map_id
            names[map_id] = {"name": name, "raid": kind == 2}
    return by_area, names


RAID_TYPES = (62, 88)  # quest_template Type (QuestInfo): Raid, Raid (10)


def instance_fields(row, instance_of, instances):
    """A quest's `dungeon`, the instance its ZoneOrSort area lies in, and `raid`: filed in a raid, or typed one wherever
    it is filed. Zul'Gurub's Paragons of Power are filed under the outdoor Zul'Gurub area and given on Yojamba Isle,
    yet each asks for the raid's drops: only their Type says so."""
    fields = {}
    if (instance := instance_of.get(row["ZoneOrSort"])) is not None:
        fields["dungeon"] = instance
    if row["Type"] in RAID_TYPES or (instance is not None and instances[instance]["raid"]):
        fields["raid"] = True
    return fields


TRAINER, INNKEEPER = 16, 128  # creature_template NpcFlags (CMaNGOS UNIT_NPC_FLAG_TRAINER, _INNKEEPER)
SKILL_STEP = 44  # SpellEffect.Effect: teaches rank EffectBasePointsF of skill line EffectMiscValue_0
SECONDARY = 9  # SkillLine.CategoryID: secondary skills (First Aid, Cooking, Fishing, and riding and racial lines)
PROFESSIONS = {SECONDARY, 11}  # SkillLine.CategoryID: secondary skills and professions


def skill_steps(effects, skill_lines):
    """Each rank-granting spell (a SKILL_STEP effect) of a profession or secondary skill line the client has: its
    (skill line, rank), rank 1 Apprentice to 4 Artisan. CMaNGOS's old Lockpicking line 242 is not in SkillLine.
    """
    lines = {int(r["ID"]) for r in skill_lines if int(r["CategoryID"]) in PROFESSIONS}
    steps = ((r, int(r["EffectMiscValue_0"])) for r in effects if int(r["Effect"]) == SKILL_STEP)
    return {int(r["SpellID"]): (line, int(float(r["EffectBasePointsF"]))) for r, line in steps if line in lines}


def gate_names(skill_lines, reputations):
    """The names of the skill lines and factions a quest gate can name: each profession or secondary skill line
    (SkillLine.DisplayName_lang), and each faction with a reputation (Faction.ReputationIndex 0 or more), by ID.
    """
    skills = {int(r["ID"]): r["DisplayName_lang"] for r in skill_lines if int(r["CategoryID"]) in PROFESSIONS}
    factions = {int(r["ID"]): r["Name_lang"] for r in reputations if int(r["ReputationIndex"]) >= 0}
    return skills, factions


def requirements(row, skills, factions):
    """A quest's skill and reputation gates as CMaNGOS Player::SatisfyQuestSkill and SatisfyQuestReputation check
    them: `skill` {id, value}, the skill line's rank at least `value`; `rep` {faction, min, max}, the reputation at
    least `min` and below `max`. Reputation is base plus earned, 0 at the start of Neutral, 3000 Friendly, 9000
    Honored, 21000 Revered, 42000 Exalted (ReputationMgr::GetReputation), the scale of the client's
    FactionData.currentStanding. A skill value of 0 asks nothing, since an unlearned line's rank is 0.

    None when a gate names a skill line or faction outside `skills` or `factions` (`gate_names`), or its minimum
    and maximum name two factions: AGFQuest cannot hold that quest's eligibility.
    """
    fields = {}
    if row["RequiredSkill"] and row["RequiredSkillValue"]:
        if row["RequiredSkill"] not in skills:
            return None
        fields["skill"] = {"id": row["RequiredSkill"], "value": row["RequiredSkillValue"]}
    low, high = row["RequiredMinRepFaction"], row["RequiredMaxRepFaction"]
    if low or high:
        if (low and high and low != high) or (low or high) not in factions:
            return None
        fields["rep"] = {"faction": low or high}
        if low:
            fields["rep"]["min"] = row["RequiredMinRepValue"]
        if high:
            fields["rep"]["max"] = row["RequiredMaxRepValue"]
    return fields


def trainer_spells(tables):
    """Each trainer's spells: its npc_trainer rows plus its TrainerTemplateId's npc_trainer_template rows, less any
    behind a condition, by creature entry.
    """
    taught, templates = defaultdict(list), defaultdict(list)
    for row in tables["npc_trainer"]:
        if not row["condition_id"]:
            taught[row["entry"]].append(row)
    for row in tables["npc_trainer_template"]:
        if not row["condition_id"]:
            templates[row["entry"]].append(row)
    return {
        row["Entry"]: taught[row["Entry"]] + (templates[row["TrainerTemplateId"]] if row["TrainerTemplateId"] else [])
        for row in tables["creature_template"]
    }


def roles(tables, steps, spells):
    """Each role NPC's fields: `class` and `upto` (its highest spell's level) for a class trainer, and `from` (its
    lowest) when that is above 1, so a trainer of only part of the class's spells (a mage's portals) is told apart;
    `pet` for a hunter pet trainer, `riding` and its `race` for a riding trainer, `skill` and `ranks` (each rank it
    teaches, ascending: a Journeyman-only trainer teaches no Apprentice) for a profession trainer, `bg`
    (battlemaster_entry.bg_template) for a battlemaster, `inn` for an innkeeper.

    A trainer teaches its `trainer_spells`. One that teaches nothing, a profession trainer with no rank spell or ranks
    of several skills, and a TrainerType 0 trainer with no class (weapon masters and the like) are no trainer here.
    """
    battles = {r["entry"]: r["bg_template"] for r in tables["battlemaster_entry"]}
    result = {}
    for row in sorted(tables["creature_template"], key=lambda r: r["Entry"]):
        entry, kind, fields = row["Entry"], row["TrainerType"], {}
        taught = spells[entry]
        if row["NpcFlags"] & TRAINER and taught:
            if kind == 0 and row["TrainerClass"]:
                levels = [s["reqlevel"] for s in taught]
                fields.update({"class": row["TrainerClass"], "upto": max(levels)})
                if min(levels) > 1:
                    fields["from"] = min(levels)
            elif kind == 1:
                fields["riding"] = True
                if row["TrainerRace"]:
                    fields["race"] = row["TrainerRace"]
            elif kind == 2:
                ranks = {steps[s["spell"]] for s in taught if s["spell"] in steps}
                if len({skill for skill, _ in ranks}) == 1:
                    fields.update({"skill": min(ranks)[0], "ranks": sorted(rank for _, rank in ranks)})
            elif kind == 3:
                fields["pet"] = True
        if entry in battles:
            fields["bg"] = battles[entry]
        if row["NpcFlags"] & INNKEEPER:
            fields["inn"] = True
        if fields:
            result[entry] = fields
    return result


def professions(npcs, steps, spells, skill_lines, counts):
    """Each skill line an emitted profession trainer teaches: its `name` (SkillLine.DisplayName_lang), `secondary`
    for a secondary skill (CategoryID 9: First Aid, Cooking, Fishing), and `ranks`, ascending, each rank a trainer
    teaches with the `level` and `skill` (npc_trainer reqlevel and reqskillvalue) its rank spell asks. Where trainers
    ask differently, the most any asks, so a rank is never offered before every trainer would teach it. A rank no
    trainer teaches (Expert Cooking comes from a book) is absent.
    """
    lines = {int(r["ID"]): r for r in skill_lines}
    asks = defaultdict(dict)
    for entry, npc in npcs.items():
        for row in spells[entry] if "skill" in npc else ():
            skill, rank = steps.get(row["spell"], (None, None))
            if skill == npc["skill"]:
                need = (row["reqlevel"], row["reqskillvalue"])
                known = asks[skill].setdefault(rank, need)
                if known != need:
                    counts["profession ranks asked differently"] += 1
                    asks[skill][rank] = tuple(map(max, known, need))
    return {
        skill: {
            "name": lines[skill]["DisplayName_lang"],
            **({"secondary": True} if int(lines[skill]["CategoryID"]) == SECONDARY else {}),
            "ranks": [{"rank": r, "level": asks[skill][r][0], "skill": asks[skill][r][1]} for r in sorted(asks[skill])],
        }
        for skill in sorted(asks)
    }


def reaction(template):
    """The sides an NPC of this FactionTemplate serves: 1 Alliance, 2 Horde, 3 both, 0 none or unknown.

    EnemyGroup bit 2 is the Alliance, 4 the Horde, 1 every player; an NPC is usable by a side it is not hostile to.
    The template's own Enemies_N list names reputations (the Stormpike Guard, the Defilers), not sides.
    """
    if not template:
        return 0
    enemies = int(template["EnemyGroup"])
    return 0 if enemies & 1 else (0 if enemies & 2 else 1) | (0 if enemies & 4 else 2)


def nearest_hub(point, grid):
    """The hub of the quest place nearest `point` (continent, world x, world y) within LINK yards, or None. `grid` maps
    a (continent, cell x, cell y) cell of LINK yards to its places as (x, y, hub).
    """
    continent, x, y = point
    cx, cy = math.floor(x / LINK), math.floor(y / LINK)
    near = [
        (math.dist((x, y), (mx, my)), hub)
        for dx in (-1, 0, 1)
        for dy in (-1, 0, 1)
        for mx, my, hub in grid.get((continent, cx + dx, cy + dy), ())
    ]
    best = min((n for n in near if n[0] <= LINK), default=None)
    return None if best is None else best[1]


def role_npcs(tables, world, faction_rows, role, grid, town_maps, maps, counts):
    """Each role NPC (`roles`) with its side (`reaction`) and place: a spawn projected as a quest giver's is. Within
    LINK yards of a quest place it takes that place's hub and the map most of the hub's quest places use (Astranaar
    is Ashenvale, not the Stonetalon map that overhangs it; `town_maps` ranks each hub's maps). Elsewhere it takes the
    smallest of `maps` it stands in (Talonbranch Glade is Felwood, not the Mount Hyjal map over it). Several spawns
    give the least place, as several givers of one quest do.
    """
    factions = {int(r["ID"]): r for r in faction_rows}
    template_faction = {r["Entry"]: r["Faction"] for r in tables["creature_template"]}
    found = spawns(tables, "creature", role.keys(), world)
    npcs = {}
    for entry, fields in role.items():
        side = reaction(factions.get(template_faction[entry]))
        candidates = []
        for spawn in found[entry]:
            if options := [o for o in spawn["options"] if o[2] in maps]:
                hub = nearest_hub(spawn["at"], grid)
                home = next((m for m in town_maps.get(hub, ()) if any(o[2] == m for o in options)), None)
                place = pick({**spawn, "options": options}, (), home)
                candidates.append(place if hub is None else {**place, "hub": hub})
        if not side or not candidates:
            counts["dropped NPC: no side" if candidates else "dropped NPC: no zone-map spawn"] += 1
            continue
        place = min(candidates, key=lambda p: (p["map"], p["name"], p["x"], p["y"]))
        npcs[entry] = {**fields, "side": side, "place": place}
    counts["NPCs"] = len(npcs)
    counts["NPCs in a hub"] = sum("hub" in npc["place"] for npc in npcs.values())
    return npcs


CANVAS = (1002, 668)  # a zone map's art in pixels: WorldMapOverlay offsets and hit rectangles are on this canvas


def overlays(ui_maps, map_art, overlay_rows, area_rows):
    """Each zone map's (UiMap Type 3) explorable areas: the WorldMapOverlay rows of its art that the client draws once
    explored, so the addon can tell which it hasn't seen (roadmap #13).

    `ox`, `oy` are the overlay's offset, which C_MapExplorationInfo.GetExploredMapTextures returns for an explored one;
    an overlay without a texture is never returned, so it is left out, as is every overlay sharing its offset with
    another on the map. `area`, `name` and `level` are its first AreaTable row's ID, English name and ExplorationLevel;
    an area whose level is 0 is never suggested, so it is left out. `x`, `y` are the hit rectangle's centre on the
    map, for which is nearer only: never a place.
    """
    zones = {int(r["ID"]) for r in ui_maps if int(r["Type"]) == 3}
    maps_of = defaultdict(set)
    for row in map_art:
        if int(row["UiMapID"]) in zones and int(row["PhaseID"]) == 0:
            maps_of[int(row["UiMapArtID"])].add(int(row["UiMapID"]))
    areas = {int(r["ID"]): r for r in area_rows}
    found = defaultdict(list)
    for row in sorted(overlay_rows, key=lambda r: int(r["ID"])):
        area = areas.get(int(row["AreaID_0"]))
        if (
            not area
            or not int(area["ExplorationLevel"])
            or int(row["PlayerConditionID"])
            or not (int(row["TextureWidth"]) and int(row["TextureHeight"]))
        ):
            continue
        entry = {
            "area": int(area["ID"]),
            "name": area["AreaName_lang"],
            "level": int(area["ExplorationLevel"]),
            "ox": int(row["OffsetX"]),
            "oy": int(row["OffsetY"]),
            "x": round((int(row["HitRectLeft"]) + int(row["HitRectRight"])) / 2 / CANVAS[0], 4),
            "y": round((int(row["HitRectTop"]) + int(row["HitRectBottom"])) / 2 / CANVAS[1], 4),
        }
        for ui_map in maps_of.get(int(row["UiMapArtID"]), ()):
            found[ui_map].append(entry)
    result = {}
    for ui_map, entries in sorted(found.items()):
        offsets = Counter((e["ox"], e["oy"]) for e in entries)
        if kept := [e for e in entries if offsets[e["ox"], e["oy"]] == 1]:
            result[ui_map] = kept
    return result


def generate(
    tables,
    ui_maps,
    assignments,
    valid_ids,
    path_nodes,
    taxi_nodes,
    area_rows,
    map_rows,
    faction_rows,
    effects,
    skill_lines,
    reputations,
    map_art,
    overlay_rows,
    legacy_rows,
):
    maps, world, areas = map_indexes(ui_maps, assignments)
    legacy = legacy_maps(legacy_rows, areas)
    skill_names, faction_names = gate_names(skill_lines, reputations)
    instance_of, instances = instance_index(area_rows, map_rows)
    locations = places(tables, world)
    quests = {r["entry"]: r for r in tables["quest_template"]}
    home = homes(locations, quests, areas)
    incoming, groups = prerequisite_index(quests)
    seasonal = {r["quest"] for r in tables["game_event_quest"]}
    steps, spells = skill_steps(effects, skill_lines), trainer_spells(tables)
    role = roles(tables, steps, spells)
    trains = {("creature", entry): fields["class"] for entry, fields in role.items() if "class" in fields}
    explores = {r["quest"] for r in tables["areatrigger_involvedrelation"]}
    shapes = quest_shapes(tables)
    credit, drops = objective_sources(tables)
    wanted = defaultdict(set)
    for qid in quests.keys() & valid_ids:
        for slot in objectives(quests[qid], qid in explores):
            for kind, entry in objective_targets(quests[qid], slot, credit, drops):
                wanted[kind].add(entry)
    located = {
        (kind, entry): found
        for kind in ("creature", "gameobject")
        for entry, found in spawns(tables, kind, wanted[kind], world).items()
    }
    emitted, counts = {}, Counter()
    for qid, row in sorted(quests.items()):
        if qid not in valid_ids:
            counts["dropped: not in QuestV2"] += 1
            continue
        counts["client-validated quests"] += 1
        quest = {
            "title": row["Title"],
            "level": row["QuestLevel"],
            "min": row["MinLevel"],
            "side": faction(row["RequiredRaces"]),
        }
        for source, target in (("RequiredRaces", "races"), ("RequiredClasses", "classes")):
            if row[source]:
                quest[target] = row[source]
        zone_maps = areas.get(row["ZoneOrSort"], set())
        for suffix, target in (("questrelation", "start"), ("involvedrelation", "finish")):
            candidates = [
                (quest_place(spawn, zone_maps, home.get(spawn["entry"])), spawn["entry"])
                for kind in ("creature", "gameobject")
                for spawn in locations[kind, suffix].get(qid, ())
            ]
            if candidates:
                place, entry = min(
                    candidates,
                    key=lambda c: (c[0]["map"] not in zone_maps, c[0]["map"], c[0]["name"], c[0]["x"], c[0]["y"]),
                )
                # A class quest's giver who is a class trainer: the class it trains, so a card can say so.
                if target == "start" and row["RequiredClasses"] and entry in trains:
                    place["trainer"] = trains[entry]
                    counts["class quests from a class trainer"] += 1
                quest[target] = place
        if zone := sorted(zone_maps & PUBLISHED.keys()):
            quest["zone"] = zone[0]
        elif place := quest.get("start", quest.get("finish")):
            quest["zone"] = place["map"]
        pre, pre_any, unknown = prerequisites(qid, quests, incoming, groups)
        if pre:
            quest["pre"] = pre
        if pre_any:
            quest["preAny"] = pre_any
        if row["ExclusiveGroup"] > 0:
            quest["group"] = row["ExclusiveGroup"]
        # A breadcrumb leads to its target: open only while the target is neither done nor in the log.
        if crumb := row["BreadcrumbForQuestId"]:
            quest["breadcrumb"] = crumb
        if following := row["NextQuestInChain"] or max(0, row["NextQuestId"]):
            quest["next"] = following
        if row["SpecialFlags"] & 1 or row["QuestFlags"] & (4096 | 32768):
            quest["repeatable"] = True
        elite = row["Type"] in (1, 62, 81, 88) or row["SuggestedPlayers"] > 1 or row["QuestFlags"] & 64
        if elite:
            quest["elite"] = True
        # ZoneOrSort names the area a quest is filed under; an area inside an instance names its Map.ID.
        quest.update(instance_fields(row, instance_of, instances))
        if "dungeon" in quest:
            counts["flagged raid" if quest.get("raid") else "flagged dungeon"] += 1
            counts["flagged, not elite"] += not elite
        elif quest.get("raid"):
            counts["typed raid, filed outdoors"] += 1
        # The state contract has no condition, event or maximum-level state; skill and reputation gates it holds
        # (`requirements`). Preserve records/enders for the live log; no start means never recommend an unknown pickup.
        needs = requirements(row, skill_names, faction_names)
        gated = (
            needs is None
            or row["RequiredCondition"]
            or row["MaxLevel"] not in (0, 255)
            or row["Method"] != 2
            or row["QuestFlags"] & (1024 | 16384)
        )
        if unknown or any(p not in valid_ids for p in pre + pre_any) or (crumb and crumb not in valid_ids):
            quest.pop("start", None)
            counts["suppressed pickup: unknown prerequisite"] += 1
        elif qid in seasonal:
            quest.pop("start", None)
            counts["suppressed pickup: event quest"] += 1
        elif gated or not quest["side"] or not quest["title"] or quest["level"] == 0:
            quest.pop("start", None)
            counts["suppressed pickup: unsupported eligibility"] += 1
        elif needs and "start" in quest:
            quest.update(needs)
            counts["skill- or reputation-gated start"] += 1
        counts["breadcrumb starts"] += "breadcrumb" in quest and "start" in quest
        counts["with start"] += "start" in quest
        counts["with finish"] += "finish" in quest
        counts["repeatable"] += bool(quest.get("repeatable"))
        # xp values a pickup; a quest in the log is finished whatever it is worth.
        if "start" in quest and (xp := full_xp(row)):
            quest["xp"] = xp
        # A dungeon's objectives are inside it, and a lap never goes there: they have no areas. need goes with every
        # other quest's objectives, placed or not, so the planner can tell a quest with none to do from one it cannot
        # place, which it never picks up for the player.
        slots = objectives(row, qid in explores)
        if slots and "dungeon" not in quest:
            found = {
                slot: [
                    s for target in sorted(objective_targets(row, slot, credit, drops)) for s in located.get(target, ())
                ]
                for slot in slots
            }
            quest["need"] = slots
            if spots := objective_areas(slots, shapes[qid], found, world, zone_maps, quest.get("zone"), legacy):
                quest["obj"] = spots
            open_world = (
                "start" in quest and quest.get("zone") in PUBLISHED and not quest.get("repeatable") and not elite
            )
            for scope in ("", "open-world ") if open_world else ("",):
                counts[f"{scope}quests with objectives"] += 1
                counts[f"{scope}quests with an objective area"] += bool(spots)
                counts[f"{scope}quests with every objective placed"] += slots.keys() <= {a[0] for a in spots}
        if flags := quest_flags(row, qid in explores):
            quest["flags"] = flags
        emitted[qid] = quest
    zones = {m: {"name": maps[m]["Name_lang"], "min": low, "max": high} for m, (low, high) in sorted(PUBLISHED.items())}
    wanted = {q[k]["map"] for q in emitted.values() for k in ("start", "finish") if k in q} | zones.keys()
    centres = geometry(assignments, wanted, {m: row["Name_lang"] for m, row in maps.items()})
    counts["maps without a centre"] = len(wanted - centres.keys())
    points = {}
    for quest in emitted.values():
        for place in (quest[k] for k in ("start", "finish") if k in quest):
            if centre := centres.get(place["map"]):
                points[place["map"], place["x"], place["y"]] = (centre["continent"], *world_point(centre, place))
    hubs = town_hubs(points)
    hub_of = {key: hub for hub, (_, members) in enumerate(hubs, 1) for _, _, key in members}
    for quest in emitted.values():
        for place in (quest[k] for k in ("start", "finish") if k in quest):
            if (key := (place["map"], place["x"], place["y"])) in hub_of:
                place["hub"] = hub_of[key]
    grid, votes = defaultdict(list), defaultdict(Counter)
    for hub, (continent, members) in enumerate(hubs, 1):
        for x, y, (ui_map, _, _) in members:
            grid[continent, math.floor(x / LINK), math.floor(y / LINK)].append((x, y, hub))
            votes[hub][ui_map] += 1
    town_maps = {hub: sorted(counter, key=lambda m: (-counter[m], m)) for hub, counter in votes.items()}
    npcs = role_npcs(tables, world, faction_rows, role, grid, town_maps, centres.keys(), counts)
    names = defaultdict(set)
    for quest in emitted.values():
        for place in (quest[k] for k in ("start", "finish") if "hub" in quest.get(k, {})):
            names[place["hub"]].add(place["name"])
    counts["town hubs"] = len(hubs)
    counts["town hubs with several givers"] = sum(len(n) > 1 for n in names.values())
    counts["widest town hub (yards)"] = round(max(diameter(members) for _, members in hubs))
    towns = hub_names(hubs, flight_masters(taxi_nodes))
    counts["named town hubs"] = len(towns)
    shifts = continents(ui_maps, assignments, {c["continent"] for c in centres.values()})
    counts["continents off the world map"] = len({c["continent"] for c in centres.values()} - shifts.keys())
    ferries = crossings(tables["gameobject_template"], path_nodes, taxi_nodes, shifts.keys())
    counts["ocean crossings"] = len(ferries)
    used = {q["dungeon"] for q in emitted.values() if "dungeon" in q}
    named = {
        m: {"name": instances[m]["name"], **({"raid": True} if instances[m]["raid"] else {})} for m in sorted(used)
    }
    skills = {q["skill"]["id"] for q in emitted.values() if "skill" in q}
    factions = {q["rep"]["faction"] for q in emitted.values() if "rep" in q}
    lookups = {
        "skills": {s: {"name": skill_names[s]} for s in skills},
        "factions": {f: {"name": faction_names[f]} for f in factions},
        "professions": professions(npcs, steps, spells, skill_lines, counts),
    }
    explorable = overlays(ui_maps, map_art, overlay_rows, area_rows)
    counts["explorable areas"] = sum(map(len, explorable.values()))
    counts["zone maps with explorable areas"] = len(explorable)
    return emitted, zones, named, centres, shifts, ferries, towns, npcs, lookups, explorable, counts


def lua(value):
    if isinstance(value, str):
        # JSON and Lua share these escapes, except JSON's unicode escapes; keep UTF-8 literal.
        return json.dumps(value, ensure_ascii=False).replace("\\u0000", "\\000").replace("\\u001a", "\\026")
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{f'[{k}]' if isinstance(k, int) else k} = {lua(v)}" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "{ " + ", ".join(lua(v) for v in value) + " }"
    if value is None:
        return "nil"
    return str(value)


def render(quests, zones, instances, centres, shifts, ferries, towns, npcs, lookups, explorable):
    lines = [
        "-- Generated by tools/gen_quests.py — do not edit.",
        f"-- CMaNGOS classic-db (GPL-3.0), pinned: {CLASSICDB_URL}",
        "-- wago.tools UiMap, UiMapAssignment, QuestV2, TaxiPathNode, TaxiNodes, AreaTable, Map, FactionTemplate,",
        "-- SpellEffect, SkillLine, Faction, UiMapXMapArt, WorldMapOverlay:",
        f"-- https://wago.tools/db2/QuestV2/csv?build={BUILD}",
        f"-- Published zone ranges (tweaks-forever/tools/gen_zonelevels.py): {ZONE_SOURCE}",
        "-- Prev > 0: completed; Prev < 0: unknown, no pickup. NextQuestId contributes reverse prerequisites.",
        "-- Positive exclusive groups close siblings; negative predecessor groups expand to pre (all completed).",
        "-- NextQuestInChain is display-only. Complex alternatives and unsupported gates have no start.",
        "-- Item starters and spawns without zone-level coordinates have no start.",
        f"-- hub: the town a start or finish stands in, by single linkage at {LINK} yd, split again past {CAP} yd.",
        f"-- hubs: a town's name is its flight master's (TaxiNodes) within {NAME_REACH} yd of a giver; no other name.",
        "-- npc: a creature giver's entry, the ID in its UnitGUID; an object giver has none.",
        "-- npcs: class, pet, riding and profession trainers, battlemasters and innkeepers (creature_template",
        "-- NpcFlags, TrainerType, npc_trainer, battlemaster_entry); ranks: each SKILL_STEP spell taught of a",
        "-- SkillLine profession or secondary skill (SpellEffect); side: every side FactionTemplate.EnemyGroup is",
        "-- not hostile to; place: a non-seasonal spawn, as quest givers'. Within",
        f"-- {LINK} yd of a quest place: its hub, on the map most of the hub's places use; else the smallest map.",
        "-- No side or zone-map spawn: left out.",
        "-- skill, rep: RequiredSkill/Value and RequiredMin/MaxRep, as Player::SatisfyQuestSkill and",
        "-- SatisfyQuestReputation check them; skills and factions: the names of those a quest here needs.",
        "-- professions: each skill line a trainer here teaches, its ranks' npc_trainer reqlevel and reqskillvalue.",
        "-- trainer: a class quest's giver who trains a class (creature_template TrainerClass): that class.",
        "-- breadcrumb: BreadcrumbForQuestId, the quest a breadcrumb leads to; it is open only while that is neither",
        "-- completed nor in the log, and has no start when that is not in QuestV2.",
        "-- dungeon: the instance a quest's ZoneOrSort area lies in (AreaTable, Map InstanceType); raid: filed in a",
        f"-- raid, or of Type {' or '.join(map(str, RAID_TYPES))} (a raid's quest wherever it is filed).",
        "-- overlays: a zone map's explorable areas (WorldMapOverlay with a texture, one per offset; AreaTable name",
        "-- and ExplorationLevel, never 0); ox, oy: the offset GetExploredMapTextures returns; x, y: nearness only.",
        "-- need: each objective's count by quest_poi objIndex slot (0-3 ReqCreatureOrGOCount, 4-7 ReqItemCount,",
        "-- 16 an areatrigger_involvedrelation explore), leaving out the item SrcItemId gives; never for a dungeon's.",
        "-- obj: where each is done, as { slot, x, y, r[, map] }: x, y in thousandths of the map (the quest's zone",
        "-- unless given), r the yards holding 80% of the source. The source is Blizzard's quest_poi shape: its",
        "-- vertex mean when that lies inside it, else its nearest vertex. With no shape, the biggest groups of the",
        "-- objective's spawns in its quest's zone (the creature, its KillCredit, the object, or what drops the item",
        f"-- at {MIN_DROP}%+), linked at {SPAWN_LINK} yd: each group's medoid, a real spawn. At most {AREAS} per",
        "-- objective; none for a dungeon quest; objIndex 9-13 (meaning unknown) is left out.",
        "-- xp: a start's full XP, as the core's Quest::XPValue: RewMoneyMaxLevel / 0.6 rounded up (the dump has no",
        "-- RewXP), for level 1-60 only.",
        "-- flags: event, a script completes it: an escort, a cast, a fight (SpecialFlags 2 without an area trigger);",
        "-- timed, the seconds it allows (LimitTime).",
        "---@type string, AGFNamespace",
        "local _, ns = ...",
        "---@type AGFData",
        "-- stylua: ignore",
        "ns.Data = {",
        f"\tbuild = {lua(BUILD)},",
        f'\tsource = "CMaNGOS classic-db {CLASSICDB_COMMIT}; wago.tools {BUILD}",',
        "\tzones = {",
    ]
    lines.extend(f"\t\t[{qid}] = {lua(zone)}," for qid, zone in sorted(zones.items()))
    lines.extend(["\t},", "\tinstances = {"])
    lines.extend(f"\t\t[{map_id}] = {lua(instance)}," for map_id, instance in sorted(instances.items()))
    lines.extend(["\t},", "\tmaps = {"])
    lines.extend(f"\t\t[{ui_map}] = {lua(centre)}," for ui_map, centre in sorted(centres.items()))
    lines.extend(["\t},", "\tcontinents = {"])
    lines.extend(f"\t\t[{continent}] = {lua(shift)}," for continent, shift in sorted(shifts.items()))
    lines.extend(["\t},", "\tcrossings = {"])
    lines.extend(f"\t\t{lua(ferry)}," for ferry in ferries)
    lines.extend(["\t},", "\thubs = {"])
    lines.extend(f"\t\t[{hub}] = {lua(town)}," for hub, town in sorted(towns.items()))
    lines.extend(["\t},", "\tnpcs = {"])
    lines.extend(f"\t\t[{entry}] = {lua(npc)}," for entry, npc in sorted(npcs.items()))
    for name in ("skills", "factions", "professions"):
        lines.extend(["\t},", f"\t{name} = {{"])
        lines.extend(f"\t\t[{key}] = {lua(value)}," for key, value in sorted(lookups[name].items()))
    lines.extend(["\t},", "\toverlays = {"])
    for ui_map, entries in sorted(explorable.items()):
        lines.append(f"\t\t[{ui_map}] = {{")
        lines.extend(f"\t\t\t{lua(entry)}," for entry in entries)
        lines.append("\t\t},")
    lines.extend(["\t},", "\tquests = {"])
    lines.extend(f"\t\t[{qid}] = {lua(quest)}," for qid, quest in sorted(quests.items()))
    return "\n".join(lines + ["\t},", "}", ""])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload the pinned sources")
    mode.add_argument("--offline", action="store_true", help="require cached sources")
    options = vars(parser.parse_args())
    content = download(CLASSICDB_URL, f"classicdb-{CLASSICDB_COMMIT[:7]}.sql.gz", **options)
    with gzip.open(io.BytesIO(content), "rt", encoding="utf-8") as dump:
        tables = read_tables(dump)
    quests, zones, instances, centres, shifts, ferries, towns, npcs, lookups, explorable, counts = generate(
        tables,
        db2("UiMap", ("ID", "Name_lang", "Type"), **options),
        db2("UiMapAssignment", ("ID", "UiMapID", "MapID", "AreaID", "Region_0", "Region_5", "UiMin_0"), **options),
        {int(r["ID"]) for r in db2("QuestV2", ("ID",), **options)},
        db2("TaxiPathNode", ("PathID", "NodeIndex", "ContinentID", "Loc_0", "Loc_1", "Delay"), **options),
        db2(
            "TaxiNodes",
            (
                "ID",
                "Name_lang",
                "ContinentID",
                "Pos_0",
                "Pos_1",
                "Flags",
                "ConditionID",
                "VisibilityConditionID",
                "MountCreatureID_0",
                "MountCreatureID_1",
            ),
            **options,
        ),
        db2("AreaTable", ("ID", "ContinentID", "AreaName_lang", "ExplorationLevel"), **options),
        db2("Map", ("ID", "MapName_lang", "InstanceType"), **options),
        db2("FactionTemplate", ("ID", "EnemyGroup"), **options),
        db2("SpellEffect", ("SpellID", "Effect", "EffectMiscValue_0", "EffectBasePointsF"), **options),
        db2("SkillLine", ("ID", "CategoryID", "DisplayName_lang"), **options),
        db2("Faction", ("ID", "Name_lang", "ReputationIndex"), **options),
        db2("UiMapXMapArt", ("UiMapID", "UiMapArtID", "PhaseID"), **options),
        db2(
            "WorldMapOverlay",
            ("ID", "UiMapArtID", "TextureWidth", "TextureHeight", "OffsetX", "OffsetY", "PlayerConditionID")
            + ("HitRectTop", "HitRectBottom", "HitRectLeft", "HitRectRight", "AreaID_0"),
            **options,
        ),
        db2("WorldMapArea", ("ID", "AreaID"), build=LEGACY_MAP_BUILD, **options),
    )
    if not quests or not counts["with start"]:
        raise ValueError("No usable quests; leaving existing output untouched")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        render(quests, zones, instances, centres, shifts, ferries, towns, npcs, lookups, explorable), encoding="utf-8"
    )
    for name, count in sorted(counts.items()):
        print(f"{name}: {count}")
    print(
        f"Wrote {len(quests)} quests, {len(zones)} zones, {len(centres)} map centres, {len(npcs)} NPCs: "
        f"{OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size:,} bytes)"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, csv.Error, urllib.error.URLError) as error:
        sys.exit(f"gen_quests: {error}")
