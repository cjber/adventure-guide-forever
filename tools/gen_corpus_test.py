"""Check the built QuestieDB corpus (python3 tools/gen_corpus.py first): python3 -m unittest discover -s tools -p
'*_test.py'."""

import re
import unittest

from gen_corpus import BOOK_FIXTURE, FIXTURE, TOWN_FIXTURE


def span(text, key):
    """The braces' contents of `key = { ... }` in one line, by brace balance."""
    at = text.find(key + " = ")
    if at < 0:
        return None
    opening = text.index("{", at)
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1 : index]
    raise AssertionError(text)


def slots(body):
    """The slot keys of a `need` table: explicit `[slot] = count`, or positional entries."""
    found, position = set(), 0
    for part in body.split(", "):
        part = part.strip()
        explicit = re.fullmatch(r"\[(\d+)\] = -?\d+", part)
        if explicit:
            found.add(int(explicit[1]))
        elif part not in ("nil", ""):
            position += 1
            found.add(position)
    return found


def area_slots(line, need):
    """The work slots and, when present, the source-item slot for one of them."""
    known = slots(need)
    source = span(line, "sourceItem")
    if source is not None:
        # The corpus writes named fields in sorted order, so slot is last.
        match = re.search(r"(?:^|, )slot = (\d+)$", source.strip())
        if match and (work_slot := int(match[1])) in known:
            known.add(-work_slot - 1)
    return known


class CorpusTest(unittest.TestCase):
    """tests/.corpus/quests.lua and towns.lua, built by tools/gen_corpus.py."""

    @classmethod
    def setUpClass(cls):
        if not FIXTURE.is_file():
            raise AssertionError(f"{FIXTURE} is not built: run python3 tools/gen_corpus.py")
        cls.TEXT = FIXTURE.read_text(encoding="utf-8")

    def test_areas_are_on_a_map_and_the_quests_objectives(self):
        quests = re.findall(r"^\t\t\[\d+\] = \{.*$", self.TEXT, re.M)
        self.assertGreater(len(quests), 3000)
        count = levelled = elites = 0
        for line in quests:
            need, obj = span(line, "need"), span(line, "obj")
            self.assertTrue(bool(need) or obj is None, line)
            self.assertFalse(need and "dungeon = " in line, line)
            if obj is None:
                continue
            known = area_slots(line, need)
            for spot in re.findall(r"\{ ([^}]+) \}", obj):
                # A spot's elite mark comes last, after its map and level, and only as true.
                values = spot.split(", ")
                if values[-1] == "true":
                    self.assertEqual(len(values), 7, line)
                    values = values[:-1]
                    elites += 1
                slot, x, y, r, *rest = (int(value) for value in values)
                count += 1
                levelled += len(rest) == 2
                self.assertIn(slot, known, line)
                self.assertTrue(0 <= x <= 1000 and 0 <= y <= 1000 and 0 <= r <= 100 and len(rest) <= 2, line)
                # The spot's mobs' lowest level (#152), after its map: a level QuestieDB gives an NPC.
                self.assertTrue(len(rest) < 2 or 1 <= rest[1] <= 63, line)
        self.assertGreater(count, 2500)
        self.assertGreater(levelled, count // 2)
        # Some camps are all elites (QuestieDB rank 1 to 3), never most.
        self.assertTrue(0 < elites < count // 2)

    def test_the_corpus_names_the_release_and_no_provider_marker(self):
        self.assertIn("QuestieDB Forever, pinned:", self.TEXT)
        self.assertNotIn("provider = true", self.TEXT)

    def test_the_towns_carry_the_gate_names(self):
        towns = TOWN_FIXTURE.read_text(encoding="utf-8")
        for key in ("hubs", "npcs", "skills", "factions"):
            self.assertIn(f"\t{key} = {{", towns)
        self.assertGreater(len(re.findall(r"^\t\t\[\d+\] = \{ name = ", towns, re.M)), 0)

    def test_the_books_carry_their_object_spawns_and_hand_in(self):
        books = BOOK_FIXTURE.read_text(encoding="utf-8")
        records = re.findall(r"^\t\{.*$", books, re.M)
        # The library's books (40 with QuestieDB 1.1.0: 79953's object 423901 is no longer in item 215824's drops, but
        # the quest's own start object and collected item still name both, #739), every one with the NPC that takes it.
        self.assertEqual(len(records), 40)
        self.assertIn("id = 79953", books)
        self.assertIn("items = { 215824 }", books)
        for record in records:
            self.assertIn("finish = {", record)
            self.assertIn("spots = {", record)
        self.assertIn('name = "Garion Wendell", npc = 211033', books)


if __name__ == "__main__":
    unittest.main()
