#!/usr/bin/env python3
"""Diff the refreshed test corpus against the previous one for lost data, with forever-db's evidence (stdlib only).

    python3 tools/check_refresh.py --old <corpus-dir> --new <corpus-dir> --fdb <forever-db.zip>

Dumps both corpora through tools/corpus_dump.lua (LuaJIT) and fails on a regression: a quest that lost a place (its
start or its finish), a prereq link, its breadcrumb, its exclusive group or its XP, or a book that lost spots or
whose finish NPC or map changed. A refresh's other effects are only reported: gained places, links
and XP, a changed level, title, side or breadcrumb, a place that moved map, quests and books added or dropped, and
how many of the new corpus's no-XP quests forever-db could fill. Every regression prints what forever-db -- the zip
at --fdb, or the release pinned in tools/fdb_pin.py fetched into tools/.cache when --fdb is omitted -- says about
that quest, so the reader can tell which source the refresh should follow. The zip is checked against the pin's
FDB_SHA256 before it is read, whatever fetched it.
"""

import argparse
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import fdb_pin
import gen_quests

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
CACHE = TOOLS / ".cache"


def dump(corpus):
    """The corpus's quests and books as tools/corpus_dump.lua's JSON lines, keyed by id."""
    if shutil.which("luajit") is None:
        raise SystemExit("check_refresh: luajit is not on PATH")
    quests, books = {}, {}
    with tempfile.TemporaryDirectory(prefix="agf-refresh-") as scratch:
        lines = Path(scratch) / "corpus.jsonl"
        subprocess.run(
            ["luajit", str(TOOLS / "corpus_dump.lua"), str(corpus), str(lines)],
            cwd=ROOT,
            check=True,
        )
        for line in lines.read_text(encoding="utf-8").splitlines():
            record = json.loads(line)
            if record["kind"] == "quest":
                quests[record["id"]] = record
            elif record["kind"] == "book":
                books[record["id"]] = record
            else:
                raise ValueError(f"corpus_dump wrote an unknown kind: {record['kind']}")
    return quests, books


def fetch_fdb(path):
    """The pinned forever-db zip's bytes: `path`'s when it exists, otherwise fetched into tools/.cache under the
    sha256 name tools/gen_xpfills.py shares. Checked against the pin's FDB_SHA256 before anything reads it."""
    name = f"fdb-{fdb_pin.FDB_SHA256}.zip"
    if path.is_file():
        content = path.read_bytes()
    elif path.parent == CACHE and path.name == name:
        content = gen_quests.download(fdb_pin.FDB_URL, name, offline=False)
        try:
            verify_fdb(content, path)
        except ValueError:
            # A changed or corrupted cached zip: redownload once, then hold the pin.
            content = gen_quests.download(fdb_pin.FDB_URL, name, refresh=True, offline=False)
    else:
        raise SystemExit(f"check_refresh: {path} does not exist")
    verify_fdb(content, path)
    return content


def verify_fdb(content, path):
    """`content`'s sha256, raised against the pin's FDB_SHA256 so the guard never reads another zip."""
    digest = hashlib.sha256(content).hexdigest()
    if digest != fdb_pin.FDB_SHA256:
        raise ValueError(f"check_refresh: {path}: sha256 {digest} does not match the pin's {fdb_pin.FDB_SHA256}")


def member(archive, stem):
    """The archive member holding `stem` under its data/ folder, whatever folder prefix the release packs."""
    found = [name for name in archive.namelist() if name == f"data/{stem}" or name.endswith(f"/data/{stem}")]
    if len(found) != 1:
        raise ValueError(f"check_refresh: expected one data/{stem} member in the release, found {len(found)}")
    return found[0]


def read_fdb(content):
    """The forever-db rows the guard reads, from the zip's bytes after fetch_fdb checked them against the pin."""
    fdb = {"quests": {}, "prereqs": {}, "starts": {}, "ends": {}, "spawns": {}}
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        with archive.open(member(archive, "quest.jsonl")) as rows:
            for row in rows:
                entry = json.loads(row)
                fdb["quests"][entry["id"]] = entry
        with archive.open(member(archive, "quest_prereq.jsonl")) as rows:
            for row in rows:
                entry = json.loads(row)
                fdb["prereqs"].setdefault(entry["quest"], []).append(entry)
        for stem, key in (("quest_start.jsonl", "starts"), ("quest_end.jsonl", "ends")):
            with archive.open(member(archive, stem)) as rows:
                for row in rows:
                    entry = json.loads(row)
                    fdb[key].setdefault(entry["quest"], []).append((entry["kind"], entry["id"]))
        with archive.open(member(archive, "spawn.jsonl")) as rows:
            for row in rows:
                entry = json.loads(row)
                fdb["spawns"].setdefault((entry["kind"], entry["id"]), []).append(entry)
    return fdb


def evidence(fdb, quest_id):
    """What forever-db says about `quest_id`: its XP and prereqs, and its start and end joined to spawn points, so
    the reader can see which source the refresh should follow."""
    parts = []
    row = fdb["quests"].get(quest_id)
    if row:
        parts.append(f"xp {row.get('xp') or 0}")
    links = fdb["prereqs"].get(quest_id) or ()
    for mode in ("all", "any"):
        members = sorted(link["pre"] for link in links if link.get("mode") == mode and not link.get("breadcrumb"))
        if members:
            parts.append(f"{mode}: " + ", ".join(str(value) for value in members))
    for link in links:
        if link.get("breadcrumb"):
            parts.append(f"breadcrumb of: {link['pre']}")
        elif link.get("mode") not in ("all", "any"):
            parts.append(f"{link['mode']}: {link['pre']}")
    for label, places in (("start", fdb["starts"].get(quest_id) or ()), ("end", fdb["ends"].get(quest_id) or ())):
        for kind, place_id in places:
            points = fdb["spawns"].get((kind, place_id)) or ()
            if points:
                maps = sorted({point["map"] for point in points})
                joined = ",".join(str(value) for value in maps)
                coords = f"{points[0]['x']}, {points[0]['y']}"
                parts.append(f"{label} {kind} {place_id}: map {joined} at {coords} ({len(points)} spawns)")
            else:
                parts.append(f"{label} {kind} {place_id}: no spawn points in forever-db")
    return "; ".join(parts) or "no forever-db record"


def coverage(fdb, quests):
    """How many of the new corpus's no-XP quests forever-db carries XP for."""
    missing = [quest_id for quest_id, quest in sorted(quests.items()) if not quest.get("xp")]
    fillable = [quest_id for quest_id in missing if (fdb["quests"].get(quest_id) or {}).get("xp")]
    return f"forever-db carries XP for {len(fillable)} of the {len(missing)} quests the new corpus leaves without XP"


def compare(old_quests, old_books, new_quests, new_books):
    """The refresh's regressions, which fail it, and its other changes, which are only reported: a regression is a
    (quest id, line) pair, so its forever-db evidence can be printed once per quest."""
    regressions, reports = [], []

    def regression(quest_id, label, text):
        regressions.append((quest_id, f"{label}: {text}"))

    def report(label, text):
        reports.append(f"{label}: {text}")

    for quest_id in sorted(set(old_quests) & set(new_quests)):
        was, now = old_quests[quest_id], new_quests[quest_id]
        label = f'quest {quest_id} "{now.get("title")}"'
        if ("start" in was or "finish" in was) and not ("start" in now or "finish" in now):
            regression(quest_id, label, "lost every place it had (start and finish are both gone)")
        else:
            for place in ("start", "finish"):
                if place in was and place not in now:
                    regression(quest_id, label, f"dropped its {place}")
                elif place in now and place not in was:
                    report(label, f"gained a {place}")
                elif place in was and place in now and was[place]["map"] != now[place]["map"]:
                    report(label, f"moved its {place} from map {was[place]['map']} to map {now[place]['map']}")
        for field in ("pre", "preAny"):
            had, has = set(was.get(field) or ()), set(now.get(field) or ())
            for link in sorted(had - has):
                regression(quest_id, label, f"dropped {field} {link}")
            for link in sorted(has - had):
                report(label, f"gained {field} {link}")
        for field in ("breadcrumb", "group"):
            had, has = was.get(field), now.get(field)
            if had and not has:
                regression(quest_id, label, f"dropped its {field} ({had})")
            elif has and not had:
                report(label, f"gained a {field} ({has})")
            elif had != has:
                report(label, f"changed its {field} from {had} to {has}")
        had_xp, has_xp = was.get("xp") or 0, now.get("xp") or 0
        if had_xp > 0 and has_xp == 0:
            regression(quest_id, label, f"dropped its XP ({had_xp} -> none)")
        elif has_xp > 0 and had_xp == 0:
            report(label, f"gained XP ({has_xp})")
        elif had_xp != has_xp:
            report(label, f"changed its XP from {had_xp} to {has_xp}")
        for field in ("level", "side"):
            if was.get(field) != now.get(field):
                report(label, f"changed its {field} from {was.get(field)} to {now.get(field)}")
        if was.get("title") != now.get("title"):
            report(label, f'was renamed from "{was.get("title")}" to "{now.get("title")}"')
    for quest_id in sorted(set(new_quests) - set(old_quests)):
        report(f'quest {quest_id} "{new_quests[quest_id].get("title")}"', "is new")
    for quest_id in sorted(set(old_quests) - set(new_quests)):
        report(f'quest {quest_id} "{old_quests[quest_id].get("title")}"', "is gone")
    for book_id in sorted(set(old_books) & set(new_books)):
        was, now = old_books[book_id], new_books[book_id]
        label = f"book {book_id}"
        had_spots, has_spots = was.get("spots") or (), now.get("spots") or ()
        if len(had_spots) > len(has_spots):
            regression(book_id, label, f"lost spots ({len(had_spots)} -> {len(has_spots)})")
        elif [spot["map"] for spot in had_spots] != [spot["map"] for spot in has_spots]:
            had_maps = ",".join(str(spot["map"]) for spot in had_spots)
            has_maps = ",".join(str(spot["map"]) for spot in has_spots)
            report(label, f"moved its spots (maps {had_maps} -> {has_maps})")
        had_finish, has_finish = was.get("finish"), now.get("finish")
        if has_finish and not had_finish:
            report(label, "gained a finish")
        elif had_finish and (
            not has_finish
            or has_finish.get("npc") != had_finish.get("npc")
            or has_finish.get("map") != had_finish.get("map")
        ):
            moved = f"npc {has_finish.get('npc')} on map {has_finish.get('map')}" if has_finish else "nowhere"
            regression(
                book_id,
                label,
                f"moved its finish from npc {had_finish.get('npc')} on map {had_finish.get('map')} to {moved}",
            )
    for book_id in sorted(set(new_books) - set(old_books)):
        report(f"book {book_id}", "is new")
    for book_id in sorted(set(old_books) - set(new_books)):
        report(f"book {book_id}", "is gone")
    return regressions, reports


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--old", type=Path, required=True, help="the corpus as the previous pins built it")
    parser.add_argument("--new", type=Path, required=True, help="the corpus as the refreshed pins built it")
    parser.add_argument(
        "--fdb",
        type=Path,
        default=CACHE / f"fdb-{fdb_pin.FDB_SHA256}.zip",
        help="the forever-db release zip, fetched into tools/.cache here when it is absent",
    )
    options = parser.parse_args()
    fdb = read_fdb(fetch_fdb(options.fdb))
    old_quests, old_books = dump(options.old.resolve())
    new_quests, new_books = dump(options.new.resolve())
    regressions, reports = compare(old_quests, old_books, new_quests, new_books)
    fills = coverage(fdb, new_quests)
    if not regressions and not reports:
        print(f"no catalogue changes ({len(new_quests)} quests, {len(new_books)} books)")
        print(fills)
        return 0
    if regressions:
        print(f"REGRESSIONS ({len(regressions)}):")
        shown = set()
        for quest_id, line in regressions:
            print(f"  {line}")
            if quest_id not in shown:
                shown.add(quest_id)
                print(f"    forever-db: {evidence(fdb, quest_id)}")
    if reports:
        print(f"REPORTED ({len(reports)}):")
        for line in reports:
            print(f"  {line}")
    print(fills)
    return 1 if regressions else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"check_refresh: {error}")
