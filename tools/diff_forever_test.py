"""Pure diff checks: python3 -m unittest discover -s tools -p '*_test.py'."""

import unittest

from diff_forever import added, lands, render, zone_quests


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

    def test_lands_range_and_flight_masters(self):
        maps = [
            {"ID": "2548", "Name_lang": "Riverglades", "Type": "3"},
            {"ID": "2482", "Name_lang": "Hyjal", "Type": "3"},
        ]
        region = {"Region_0": "-10000", "Region_1": "-6000", "Region_2": "-1e6", "Region_3": "-6000"}
        region.update(Region_4="-2000", Region_5="1e6", UiMin_0="0", UiMin_1="0", UiMax_0="1", UiMax_1="1")
        assignments = [
            {"UiMapID": "2548", "MapID": "0", "AreaID": "16591", "WMODoodadPlacementID": "0", **region},
            {"UiMapID": "2482", "MapID": "1", "AreaID": "616", "WMODoodadPlacementID": "0", **region},
        ]
        areas = [
            {"ID": "16591", "ParentAreaID": "0", "ExplorationLevel": "0"},
            {"ID": "16724", "ParentAreaID": "16591", "ExplorationLevel": "38"},
            {"ID": "16685", "ParentAreaID": "16591", "ExplorationLevel": "44"},
            {"ID": "16735", "ParentAreaID": "16591", "ExplorationLevel": "36"},
            {"ID": "616", "ParentAreaID": "0", "ExplorationLevel": "0"},
            {"ID": "617", "ParentAreaID": "616", "ExplorationLevel": "0"},
        ]

        def node(node_id, name, flags, x, y):
            return {
                "ID": str(node_id),
                "Name_lang": name,
                "ContinentID": "0",
                "Pos_0": str(x),
                "Pos_1": str(y),
                "Flags": str(flags),
                "ConditionID": "0",
                "VisibilityConditionID": "0",
                "MountCreatureID_0": "541",
                "MountCreatureID_1": "0",
            }

        nodes = [
            node(3276, "Farholde Keep, Riverglades", 1025, -9000, -5000),
            node(3274, "Powderfuse Port, Riverglades", 1024, -8000, -5000),  # no side
            node(3203, "Rog'mar, Riverglades", 1026, -8000, -2500),
            node(5, "Lakeshire, Redridge", 1, -9400, -2200),  # an older node the rectangle overhangs
            node(3207, "Elsewhere", 1, 0, 0),  # off the map
        ]
        self.assertEqual(
            lands(maps, assignments, areas, nodes, {3276, 3274, 3203, 3207}),
            {
                2548: {
                    "name": "Riverglades",
                    "min": 36,
                    "max": 44,
                    "taxi": [
                        {"side": 2, "map": 2548, "x": 0.125, "y": 0.5, "name": "Rog'mar, Riverglades"},
                        {"side": 1, "map": 2548, "x": 0.75, "y": 0.75, "name": "Farholde Keep, Riverglades"},
                    ],
                }
            },
        )

    def test_render(self):
        text = render({1436: [10, 12]}, list(range(1, 8)), {})
        self.assertIn("ns.Data.forever = {", text)
        self.assertIn("\t\t[1436] = { 10, 12 },", text)
        self.assertIn("\t\t[7] = true,\n\t},", text)
        self.assertTrue(all(len(line) <= 120 for line in text.splitlines()))
        land = {"name": "Riverglades", "min": 36, "max": 44, "taxi": [{"side": 1, "map": 2548, "x": 0.6, "y": 0.8}]}
        text = render({}, [], {2548: land})
        self.assertIn('\t\t[2548] = { name = "Riverglades", min = 36, max = 44, taxi = {\n', text)
        self.assertIn("\t\t\t{ side = 1, map = 2548, x = 0.6, y = 0.8 },\n\t\t} },", text)


if __name__ == "__main__":
    unittest.main()
