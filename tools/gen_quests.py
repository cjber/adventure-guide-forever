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


def db2(name, columns, **options):
    content = download(f"https://wago.tools/db2/{name}/csv?build={BUILD}", f"{name}-{BUILD}.csv", **options)
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


def places(tables, world):
    """Every spawn of a quest giver or ender, with each zone map whose rectangle contains it.

    Zone rectangles overlap (Durotar's covers the eastern Barrens), so the map is chosen per quest
    in `pick`, not here.
    """
    result = {}
    for kind in ("creature", "gameobject"):
        wanted = {r["id"] for suffix in ("questrelation", "involvedrelation") for r in tables[f"{kind}_{suffix}"]}
        names = {r.get("Entry", r.get("entry")): r.get("Name", r.get("name")) for r in tables[f"{kind}_template"]}
        # A positive event spawns the row only while that event (Midsummer, Hallow's End...) runs.
        seasonal = {r["guid"] for r in tables[f"game_event_{kind}"] if r["event"] > 0}
        spawns = defaultdict(list)
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
                spawns[entry].append({"entry": (kind, entry), "name": names[entry], "options": sorted(options)})
        for suffix in ("questrelation", "involvedrelation"):
            relations = defaultdict(list)
            for relation in tables[f"{kind}_{suffix}"]:
                relations[relation["quest"]].extend(spawns[relation["id"]])
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


def generate(tables, ui_maps, assignments, valid_ids):
    maps, world, areas = map_indexes(ui_maps, assignments)
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
        instances = sorted(m for m in zone_maps if int(maps[m]["Type"]) == 4)
        if instances:
            quest["dungeon"] = instances[0]
        if row["Type"] in (1, 62, 81, 88) or row["SuggestedPlayers"] > 1 or row["QuestFlags"] & 64:
            quest["elite"] = True
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
    shifts = continents(ui_maps, assignments, {c["continent"] for c in centres.values()})
    counts["continents off the world map"] = len({c["continent"] for c in centres.values()} - shifts.keys())
    return emitted, zones, centres, shifts, counts


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


def render(quests, zones, centres, shifts):
    lines = [
        "-- Generated by tools/gen_quests.py — do not edit.",
        f"-- CMaNGOS classic-db (GPL-3.0), pinned: {CLASSICDB_URL}",
        f"-- wago.tools UiMap, UiMapAssignment, QuestV2: https://wago.tools/db2/QuestV2/csv?build={BUILD}",
        f"-- Published zone ranges (tweaks-forever/tools/gen_zonelevels.py): {ZONE_SOURCE}",
        "-- Prev > 0: completed; Prev < 0: unknown, no pickup. NextQuestId contributes reverse prerequisites.",
        "-- Positive exclusive groups close siblings; negative predecessor groups expand to pre (all completed).",
        "-- NextQuestInChain is display-only. Complex alternatives and unsupported gates have no start.",
        "-- Item starters and spawns without zone-level coordinates have no start; no objective coordinates invented.",
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
    lines.extend(["\t},", "\tmaps = {"])
    lines.extend(f"\t\t[{ui_map}] = {lua(centre)}," for ui_map, centre in sorted(centres.items()))
    lines.extend(["\t},", "\tcontinents = {"])
    lines.extend(f"\t\t[{continent}] = {lua(shift)}," for continent, shift in sorted(shifts.items()))
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
    quests, zones, centres, shifts, counts = generate(
        tables,
        db2("UiMap", ("ID", "Name_lang", "Type"), **options),
        db2("UiMapAssignment", ("ID", "UiMapID", "MapID", "AreaID", "Region_0", "Region_5", "UiMin_0"), **options),
        {int(r["ID"]) for r in db2("QuestV2", ("ID",), **options)},
    )
    if not quests or not counts["with start"]:
        raise ValueError("No usable quests; leaving existing output untouched")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(quests, zones, centres, shifts), encoding="utf-8")
    for name, count in sorted(counts.items()):
        print(f"{name}: {count}")
    print(
        f"Wrote {len(quests)} quests, {len(zones)} zones, {len(centres)} map centres: "
        f"{OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size:,} bytes)"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, csv.Error, urllib.error.URLError) as error:
        sys.exit(f"gen_quests: {error}")
