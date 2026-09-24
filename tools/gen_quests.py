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


LINK = 100  # yards: two givers this close stand in one town (docs/plan.md §7.2)
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
        options = []
        for row in world[spawn["map"]]:
            xy = project(row, spawn["position_x"], spawn["position_y"], spawn["position_z"])
            if xy is not None:
                area = (float(row["Region_3"]) - float(row["Region_0"])) * (
                    float(row["Region_4"]) - float(row["Region_1"])
                )
                options.append((area, int(row["OrderIndex"]), int(row["UiMapID"]), xy))
        if options:
            at = (spawn["map"], spawn["position_x"], spawn["position_y"])
            result[entry].append({"entry": (kind, entry), "name": names[entry], "options": sorted(options), "at": at})
    return result


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
    options = spawn["options"]
    chosen = (
        next((o for o in options if o[2] in zone_maps), None)
        or next((o for o in options if o[2] == home), None)
        or options[0]
    )
    _, _, ui_map, (x, y) = chosen
    return {"map": ui_map, "x": round(x, 4), "y": round(y, 4), "name": spawn["name"]}


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


TRAINER, INNKEEPER = 16, 128  # creature_template NpcFlags (CMaNGOS UNIT_NPC_FLAG_TRAINER, _INNKEEPER)
SKILL_STEP = 44  # SpellEffect.Effect: teaches rank EffectBasePointsF of skill line EffectMiscValue_0
PROFESSIONS = {9, 11}  # SkillLine.CategoryID: secondary skills (First Aid, Cooking, Fishing), professions


def skill_steps(effects, skill_lines):
    """Each rank-granting spell (a SKILL_STEP effect) of a profession or secondary skill line the client has: its
    (skill line, rank), rank 1 Apprentice to 4 Artisan. CMaNGOS's old Lockpicking line 242 is not in SkillLine.
    """
    lines = {int(r["ID"]) for r in skill_lines if int(r["CategoryID"]) in PROFESSIONS}
    steps = ((r, int(r["EffectMiscValue_0"])) for r in effects if int(r["Effect"]) == SKILL_STEP)
    return {int(r["SpellID"]): (line, int(float(r["EffectBasePointsF"]))) for r, line in steps if line in lines}


def roles(tables, steps):
    """Each role NPC's fields: `class` and `upto` (its highest spell's level) for a class trainer, `pet` for a hunter
    pet trainer, `riding` and its `race` for a riding trainer, `skill` and `rank` (the highest rank it teaches) for a
    profession trainer, `bg` (battlemaster_entry.bg_template) for a battlemaster, `inn` for an innkeeper.

    A trainer teaches its npc_trainer rows plus its TrainerTemplateId's npc_trainer_template rows, less any behind a
    condition. One that teaches nothing, a profession trainer with no rank spell or ranks of several skills, and a
    TrainerType 0 trainer with no class (weapon masters and the like) are no trainer here.
    """
    taught, templates = defaultdict(list), defaultdict(list)
    for row in tables["npc_trainer"]:
        if not row["condition_id"]:
            taught[row["entry"]].append(row)
    for row in tables["npc_trainer_template"]:
        if not row["condition_id"]:
            templates[row["entry"]].append(row)
    battles = {r["entry"]: r["bg_template"] for r in tables["battlemaster_entry"]}
    result = {}
    for row in sorted(tables["creature_template"], key=lambda r: r["Entry"]):
        entry, kind, fields = row["Entry"], row["TrainerType"], {}
        spells = taught[entry] + (templates[row["TrainerTemplateId"]] if row["TrainerTemplateId"] else [])
        if row["NpcFlags"] & TRAINER and spells:
            if kind == 0 and row["TrainerClass"]:
                fields.update({"class": row["TrainerClass"], "upto": max(s["reqlevel"] for s in spells)})
            elif kind == 1:
                fields["riding"] = True
                if row["TrainerRace"]:
                    fields["race"] = row["TrainerRace"]
            elif kind == 2:
                ranks = {steps[s["spell"]] for s in spells if s["spell"] in steps}
                if len({skill for skill, _ in ranks}) == 1:
                    fields.update(zip(("skill", "rank"), max(ranks), strict=True))
            elif kind == 3:
                fields["pet"] = True
        if entry in battles:
            fields["bg"] = battles[entry]
        if row["NpcFlags"] & INNKEEPER:
            fields["inn"] = True
        if fields:
            result[entry] = fields
    return result


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


def role_npcs(tables, world, faction_rows, effects, skill_lines, grid, town_maps, maps, counts):
    """Each role NPC (`roles`) with its side (`reaction`) and place: a spawn projected as a quest giver's is. Within
    LINK yards of a quest place it takes that place's hub and the map most of the hub's quest places use (Astranaar
    is Ashenvale, not the Stonetalon map that overhangs it; `town_maps` ranks each hub's maps). Elsewhere it takes the
    smallest of `maps` it stands in (Talonbranch Glade is Felwood, not the Mount Hyjal map over it). Several spawns
    give the least place, as several givers of one quest do.
    """
    factions = {int(r["ID"]): r for r in faction_rows}
    template_faction = {r["Entry"]: r["Faction"] for r in tables["creature_template"]}
    role = roles(tables, skill_steps(effects, skill_lines))
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
):
    maps, world, areas = map_indexes(ui_maps, assignments)
    instance_of, instances = instance_index(area_rows, map_rows)
    locations = places(tables, world)
    quests = {r["entry"]: r for r in tables["quest_template"]}
    home = homes(locations, quests, areas)
    incoming, groups = prerequisite_index(quests)
    seasonal = {r["quest"] for r in tables["game_event_quest"]}
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
                pick(spawn, zone_maps, home.get(spawn["entry"]))
                for kind in ("creature", "gameobject")
                for spawn in locations[kind, suffix].get(qid, ())
            ]
            if candidates:
                quest[target] = min(
                    candidates, key=lambda p: (p["map"] not in zone_maps, p["map"], p["name"], p["x"], p["y"])
                )
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
        if following := row["NextQuestInChain"] or max(0, row["NextQuestId"]):
            quest["next"] = following
        if row["SpecialFlags"] & 1 or row["QuestFlags"] & (4096 | 32768):
            quest["repeatable"] = True
        elite = row["Type"] in (1, 62, 81, 88) or row["SuggestedPlayers"] > 1 or row["QuestFlags"] & 64
        if elite:
            quest["elite"] = True
        # ZoneOrSort names the area a quest is filed under; an area inside an instance names its Map.ID.
        if (instance := instance_of.get(row["ZoneOrSort"])) is not None:
            quest["dungeon"] = instance
            if instances[instance]["raid"]:
                quest["raid"] = True
            counts["flagged raid" if quest.get("raid") else "flagged dungeon"] += 1
            counts["flagged, not elite"] += not elite
        # The state contract has no reputation, skill, condition, event or maximum-level state.
        # Preserve records/enders for the live log; no start means never recommend an unknown pickup.
        gated = (
            any(
                row[k]
                for k in (
                    "RequiredSkill",
                    "RequiredCondition",
                    "RequiredMinRepFaction",
                    "RequiredMaxRepFaction",
                    "BreadcrumbForQuestId",
                )
            )
            or row["MaxLevel"] not in (0, 255)
            or row["Method"] != 2
            or row["QuestFlags"] & (1024 | 16384)
        )
        if unknown or any(p not in valid_ids for p in pre + pre_any):
            quest.pop("start", None)
            counts["suppressed pickup: unknown prerequisite"] += 1
        elif qid in seasonal:
            quest.pop("start", None)
            counts["suppressed pickup: event quest"] += 1
        elif gated or not quest["side"] or not quest["title"] or quest["level"] == 0:
            quest.pop("start", None)
            counts["suppressed pickup: unsupported eligibility"] += 1
        counts["with start"] += "start" in quest
        counts["with finish"] += "finish" in quest
        counts["repeatable"] += bool(quest.get("repeatable"))
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
    npcs = role_npcs(tables, world, faction_rows, effects, skill_lines, grid, town_maps, centres.keys(), counts)
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
    named = {m: {"name": instances[m]["name"]} for m in sorted(used)}
    return emitted, zones, named, centres, shifts, ferries, towns, npcs, counts


def lua(value):
    if isinstance(value, str):
        # JSON and Lua share these escapes, except JSON's unicode escapes; keep UTF-8 literal.
        return json.dumps(value, ensure_ascii=False).replace("\\u0000", "\\000").replace("\\u001a", "\\026")
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{k} = {lua(v)}" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "{ " + ", ".join(lua(v) for v in value) + " }"
    if value is None:
        return "nil"
    return str(value)


def render(quests, zones, instances, centres, shifts, ferries, towns, npcs):
    lines = [
        "-- Generated by tools/gen_quests.py — do not edit.",
        f"-- CMaNGOS classic-db (GPL-3.0), pinned: {CLASSICDB_URL}",
        "-- wago.tools UiMap, UiMapAssignment, QuestV2, TaxiPathNode, TaxiNodes, AreaTable, Map, FactionTemplate,",
        "-- SpellEffect, SkillLine:",
        f"-- https://wago.tools/db2/QuestV2/csv?build={BUILD}",
        f"-- Published zone ranges (tweaks-forever/tools/gen_zonelevels.py): {ZONE_SOURCE}",
        "-- Prev > 0: completed; Prev < 0: unknown, no pickup. NextQuestId contributes reverse prerequisites.",
        "-- Positive exclusive groups close siblings; negative predecessor groups expand to pre (all completed).",
        "-- NextQuestInChain is display-only. Complex alternatives and unsupported gates have no start.",
        "-- Item starters and spawns without zone-level coordinates have no start; no objective coordinates invented.",
        f"-- hub: the town a start or finish stands in, by single linkage at {LINK} yd, split again past {CAP} yd.",
        f"-- hubs: a town's name is its flight master's (TaxiNodes) within {NAME_REACH} yd of a giver; no other name.",
        "-- npcs: class, pet, riding and profession trainers, battlemasters and innkeepers (creature_template",
        "-- NpcFlags, TrainerType, npc_trainer, battlemaster_entry); rank: the highest SKILL_STEP spell taught of a",
        "-- SkillLine profession or secondary skill (SpellEffect); side: every side FactionTemplate.EnemyGroup is",
        "-- not hostile to; place: a non-seasonal spawn, as quest givers'. Within",
        f"-- {LINK} yd of a quest place: its hub, on the map most of the hub's places use; else the smallest map.",
        "-- No side or zone-map spawn: left out.",
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
    quests, zones, instances, centres, shifts, ferries, towns, npcs, counts = generate(
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
        db2("AreaTable", ("ID", "ContinentID"), **options),
        db2("Map", ("ID", "MapName_lang", "InstanceType"), **options),
        db2("FactionTemplate", ("ID", "EnemyGroup"), **options),
        db2("SpellEffect", ("SpellID", "Effect", "EffectMiscValue_0", "EffectBasePointsF"), **options),
        db2("SkillLine", ("ID", "CategoryID"), **options),
    )
    if not quests or not counts["with start"]:
        raise ValueError("No usable quests; leaving existing output untouched")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(quests, zones, instances, centres, shifts, ferries, towns, npcs), encoding="utf-8")
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
