#!/usr/bin/env python3
"""Unit tests for tools/check_refresh.py's regression classes: compare() classifies a corpus diff, and a
regression fails the refresh where a report does not. Stdlib only; run with the repo's Python test runner."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_refresh
import fdb_pin

ROOT = check_refresh.ROOT


def quest(**fields):
    row = {"id": 6, "title": "Bounty on Garrick Padfoot"}
    row.update(fields)
    return row


PLACE = {"map": 1429, "x": 0.4817, "y": 0.4294, "z": 83}


class CompareTest(unittest.TestCase):
    def compare(self, old, new, old_books=None, new_books=None):
        old = {k: quest(**v) for k, v in old.items()}
        new = {k: quest(**v) for k, v in new.items()}
        return check_refresh.compare(old, old_books or {}, new, new_books or {})

    def test_both_places_lost_is_a_regression(self):
        regressions, _ = self.compare(
            {6: {"start": PLACE, "finish": PLACE}},
            {6: {}},
        )
        self.assertEqual(len(regressions), 1)
        self.assertIn("lost every place it had", regressions[0][1])

    def test_one_place_lost_is_a_regression(self):
        regressions, _ = self.compare({6: {"start": PLACE, "finish": PLACE}}, {6: {"finish": PLACE}})
        self.assertEqual(len(regressions), 1)
        self.assertIn("dropped its start", regressions[0][1])

    def test_one_place_gained_is_a_report(self):
        _, reports = self.compare({6: {"finish": PLACE}}, {6: {"start": PLACE, "finish": PLACE}})
        self.assertEqual(len(reports), 1)
        self.assertIn("gained a start", reports[0])

    def test_a_lost_prereq_is_a_regression(self):
        regressions, _ = self.compare({6: {"pre": [18], "finish": PLACE}}, {6: {"pre": [], "finish": PLACE}})
        self.assertEqual(len(regressions), 1)
        self.assertIn("dropped pre 18", regressions[0][1])

    def test_faction_specific_prereq_preserves_theldurins_alliance_requirement(self):
        quests = {653: {"side": 1}, 688: {"side": 2}}
        theldurin = {"title": "Theldurin the Lost", "side": 3}
        regressions, reports = self.compare(
            {687: {**theldurin, "preAny": [653, 688]}, **quests},
            {687: {**theldurin, "pre": [653]}, **quests},
        )
        self.assertEqual(regressions, [])
        self.assertEqual(
            reports,
            ['quest 687 "Theldurin the Lost": dropped preAny 688 (Horde-only for the Alliance corpus)'],
        )

    def test_an_any_of_with_one_both_sides_quest_is_equivalent_to_pre(self):
        quests = {18: {"side": 3}, 19: {"side": 2}}
        all_of = {6: {"pre": [17, 18]}, **quests}
        any_of = {6: {"pre": [17], "preAny": [18, 19]}, **quests}
        for old, new in ((all_of, any_of), (any_of, all_of)):
            with self.subTest(old=old[6], new=new[6]):
                regressions, reports = self.compare(old, new)
                self.assertEqual(regressions, [])
                self.assertEqual(len(reports), 1)
                self.assertIn("preAny 19 (Horde-only for the Alliance corpus)", reports[0])

    def test_a_missing_quest_does_not_supply_evidence_that_its_link_is_unreachable(self):
        regressions, reports = self.compare(
            {6: {"preAny": [18, 19]}, 19: {"side": 2}},
            {6: {}, 19: {"side": 2}},
        )
        self.assertEqual(regressions, [(6, 'quest 6 "Bounty on Garrick Padfoot": dropped pre 18')])
        self.assertEqual(len(reports), 1)
        self.assertIn("dropped preAny 19 (Horde-only for the Alliance corpus)", reports[0])

    def test_a_reachable_any_of_link_can_be_lost_while_the_requirement_remains(self):
        quests = {18: {"side": 1}, 19: {"side": 2}, 20: {"side": 3}, 21: {"side": 1}}
        regressions, reports = self.compare(
            {6: {"preAny": [18, 19, 20]}, **quests},
            {6: {"preAny": [18, 21]}, **quests},
        )
        self.assertEqual(regressions, [(6, 'quest 6 "Bounty on Garrick Padfoot": dropped preAny 20')])
        self.assertTrue(any("dropped preAny 19 (Horde-only for the Alliance corpus)" in line for line in reports))
        self.assertTrue(any("gained preAny 21" in line for line in reports))

    def test_a_required_quest_becoming_one_of_several_alternatives_is_a_regression(self):
        quests = {18: {"side": 1}, 19: {"side": 2}, 20: {"side": 3}, 21: {"side": 1}}
        regressions, reports = self.compare(
            {6: {"pre": [18], "preAny": [19, 20, 21]}, **quests},
            {6: {"preAny": [18, 20, 21]}, **quests},
        )
        self.assertEqual(regressions, [(6, 'quest 6 "Bounty on Garrick Padfoot": dropped pre 18')])
        self.assertTrue(any("dropped preAny 19 (Horde-only for the Alliance corpus)" in line for line in reports))

    def test_another_faction_does_not_excuse_a_lost_all_of_link(self):
        quests = {18: {"side": 2}, 19: {"side": 2}, 20: {"side": 1}}
        regressions, reports = self.compare(
            {6: {"pre": [18], "preAny": [19, 20]}, **quests},
            {6: {"pre": [20]}, **quests},
        )
        self.assertEqual(regressions, [(6, 'quest 6 "Bounty on Garrick Padfoot": dropped pre 18')])
        self.assertEqual(len(reports), 1)
        self.assertIn("dropped preAny 19 (Horde-only for the Alliance corpus)", reports[0])

    def test_removing_every_other_faction_alternative_loses_the_requirement(self):
        quests = {18: {"side": 2}, 19: {"side": 2}}
        regressions, reports = self.compare(
            {6: {"pre": [17], "preAny": [18, 19]}, **quests},
            {6: {"pre": [17]}, **quests},
        )
        self.assertEqual(
            regressions, [(6, 'quest 6 "Bounty on Garrick Padfoot": dropped its unsatisfiable preAny requirement')]
        )
        self.assertEqual(len(reports), 2)
        self.assertTrue(all("Horde-only for the Alliance corpus" in line for line in reports))

    def test_dropping_one_alternative_can_leave_the_requirement_unsatisfiable(self):
        quests = {18: {"side": 2}, 19: {"side": 2}}
        regressions, reports = self.compare(
            {6: {"preAny": [18, 19]}, **quests},
            {6: {"preAny": [18]}, **quests},
        )
        self.assertEqual(regressions, [])
        self.assertEqual(len(reports), 1)
        self.assertIn("dropped preAny 19 (Horde-only for the Alliance corpus)", reports[0])

    def test_an_alternative_changing_faction_can_leave_the_requirement_unsatisfiable(self):
        regressions, reports = self.compare(
            {6: {"preAny": [18, 19]}, 18: {"side": 1}, 19: {"side": 2}},
            {6: {"preAny": [18, 19]}, 18: {"side": 2}, 19: {"side": 2}},
        )
        self.assertEqual(regressions, [(6, 'quest 6 "Bounty on Garrick Padfoot": dropped pre 18')])
        self.assertEqual(len(reports), 1)
        self.assertIn("changed its side", reports[0])

    def test_a_horde_only_quest_keeps_every_alternative_its_own_players_can_complete(self):
        quests = {18: {"side": 2}, 19: {"side": 2}, 20: {"side": 2}}
        regressions, _ = self.compare(
            {6: {"side": 2, "preAny": [18, 19, 20]}, **quests},
            {6: {"side": 2, "preAny": [18, 19]}, **quests},
        )
        self.assertEqual(regressions, [(6, 'quest 6 "Bounty on Garrick Padfoot": dropped preAny 20')])

    def test_a_lost_breadcrumb_is_a_regression(self):
        regressions, _ = self.compare({6: {"breadcrumb": 484, "finish": PLACE}}, {6: {"finish": PLACE}})
        self.assertEqual(len(regressions), 1)
        self.assertIn("dropped its breadcrumb", regressions[0][1])

    def test_a_lost_group_is_a_regression(self):
        regressions, _ = self.compare({6: {"group": 23, "finish": PLACE}}, {6: {"finish": PLACE}})
        self.assertEqual(len(regressions), 1)
        self.assertIn("dropped its group", regressions[0][1])

    def test_a_lost_xp_is_a_regression(self):
        regressions, _ = self.compare({6: {"xp": 335, "finish": PLACE}}, {6: {"finish": PLACE}})
        self.assertEqual(len(regressions), 1)
        self.assertIn("dropped its XP", regressions[0][1])

    def test_a_gained_xp_is_a_report(self):
        _, reports = self.compare({6: {"finish": PLACE}}, {6: {"xp": 335, "finish": PLACE}})
        self.assertEqual(len(reports), 1)
        self.assertIn("gained XP", reports[0])

    def test_a_quest_nobody_carries_any_more_is_a_report(self):
        _, reports = self.compare({6: {"finish": PLACE}}, {})
        self.assertEqual(len(reports), 1)
        self.assertIn("is gone", reports[0])

    def test_a_book_that_loses_some_spots_is_a_regression(self):
        spots = [
            {"map": 1453, "x": 0.1, "y": 0.2},
            {"map": 1431, "x": 0.3, "y": 0.4},
            {"map": 1432, "x": 0.5, "y": 0.6},
        ]
        finish = {"map": 1453, "npc": 211033}
        regressions, _ = check_refresh.compare(
            {6: quest(finish=PLACE)},
            {78124: {"id": 78124, "spots": spots, "finish": finish}},
            {6: quest(finish=PLACE)},
            {78124: {"id": 78124, "spots": spots[:1], "finish": finish}},
        )
        self.assertEqual(len(regressions), 1)
        self.assertIn("lost spots (3 -> 1)", regressions[0][1])

    def test_a_book_that_gains_a_finish_is_a_report(self):
        spots = [{"map": 1453, "x": 0.1, "y": 0.2}]
        regressions, reports = check_refresh.compare(
            {6: quest(finish=PLACE)},
            {78124: {"id": 78124, "spots": spots}},
            {6: quest(finish=PLACE)},
            {78124: {"id": 78124, "spots": spots, "finish": {"map": 1453, "npc": 211033}}},
        )
        self.assertEqual(regressions, [])
        self.assertEqual(len(reports), 1)
        self.assertIn("gained a finish", reports[0])


class FetchFdbTest(unittest.TestCase):
    def test_a_relative_cache_path_resolves_against_the_checkout_root(self):
        """The workflow passes tools/.cache/fdb-<sha>.zip relative; a missing file there is a fetch, not a
        missing-file exit."""
        relative = Path("tools/.cache") / f"fdb-{fdb_pin.FDB_SHA256}.zip"
        if (ROOT / relative).is_file():
            self.assertEqual(check_refresh.fetch_fdb(relative), (ROOT / relative).read_bytes())
        else:
            with self.assertRaises(SystemExit) as caught:
                check_refresh.fetch_fdb(Path("tools/.cache") / "fdb-not-the-pins-sha.zip")
            self.assertIn(str((ROOT / "tools/.cache" / "fdb-not-the-pins-sha.zip").resolve()), str(caught.exception))


if __name__ == "__main__":
    unittest.main()
