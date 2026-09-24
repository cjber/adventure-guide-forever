"""Pure diff checks: python3 -m unittest discover -s tools -p '*_test.py'."""

import unittest

from diff_forever import added, render, zone_quests


def rows(*ids):
    return [{"ID": str(i)} for i in ids]


class DiffTest(unittest.TestCase):
    def test_added_is_forever_only(self):
        self.assertEqual(added(rows(3, 1, 2, 9), rows(1, 2, 4)), [3, 9])

    def test_zone_quests_only_added_and_placed(self):
        blobs = [
            {"QuestID": "10", "UiMapID": "1436"},
            {"QuestID": "10", "UiMapID": "1436"},
            {"QuestID": "10", "UiMapID": "1453"},
            {"QuestID": "11", "UiMapID": "0"},
            {"QuestID": "5", "UiMapID": "1436"},
        ]
        self.assertEqual(zone_quests(blobs, [10, 11]), {1436: [10], 1453: [10]})

    def test_render(self):
        text = render({1436: [10, 12]}, list(range(1, 8)))
        self.assertIn("ns.Data.forever = {", text)
        self.assertIn("\t\t[1436] = { 10, 12 },", text)
        self.assertIn("\t\t[7] = true,\n\t},", text)
        self.assertTrue(all(len(line) <= 120 for line in text.splitlines()))


if __name__ == "__main__":
    unittest.main()
