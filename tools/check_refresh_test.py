#!/usr/bin/env python3
"""Unit tests for tools/check_refresh.py's regression classes: compare() classifies a corpus diff, and a
regression fails the refresh where a report does not. Stdlib only; run with the repo's Python test runner."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_refresh


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


if __name__ == "__main__":
    unittest.main()
