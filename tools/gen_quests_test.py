"""Pure generator checks: python3 -m unittest discover -s tools -p '*_test.py'."""

import unittest

from gen_quests import (
    continents,
    crossings,
    faction,
    geometry,
    parse_values,
    prerequisite_index,
    prerequisites,
    project,
)


class ParsingTest(unittest.TestCase):
    def test_sql_literals(self):
        self.assertEqual(
            list(parse_values(r"(1,'It\'s (a,b) \\ path',NULL,-3),(2,'It''s\nnext',1.25,0);")),
            [[1, "It's (a,b) \\ path", None, -3], [2, "It's\nnext", 1.25, 0]],
        )

    def test_truncated_or_executable_sql_rejected(self):
        for text in ("(1,'unfinished)", "(1,2)", "(1,NOW());", "(1); DROP TABLE quests;"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                list(parse_values(text))

    def test_faction_masks(self):
        self.assertEqual([faction(mask) for mask in (0, 77, 178, 255, 4, 16)], [3, 1, 2, 3, 1, 2])


class PrerequisiteTest(unittest.TestCase):
    @staticmethod
    def resolve(rows, target):
        quests = {
            qid: {"PrevQuestId": prev, "NextQuestId": nxt, "ExclusiveGroup": group} for qid, prev, nxt, group in rows
        }
        incoming, groups = prerequisite_index(quests)
        return prerequisites(target, quests, incoming, groups)

    def test_signs(self):
        self.assertEqual(self.resolve([(1, 0, 0, 0), (2, 1, 0, 0)], 2), ([1], [], False))
        self.assertEqual(self.resolve([(1, 0, 0, 0), (2, -1, 0, 0)], 2), ([], [], True))
        self.assertEqual(self.resolve([(1, 0, -2, 0), (2, 0, 0, 0)], 2), ([], [], True))

    def test_exclusive_group_signs(self):
        for group, expected in ((7, ([], [1, 2], False)), (-7, ([1, 2], [], False))):
            self.assertEqual(self.resolve([(1, 0, 3, group), (2, 0, 3, group), (3, 0, 0, 0)], 3), expected)
        self.assertEqual(self.resolve([(1, 0, 0, -7), (2, 0, 0, -7), (3, 1, 0, 0)], 3), ([1, 2], [], False))

    def test_unknown_and_complex_requirements(self):
        self.assertEqual(self.resolve([(3, 99, 0, 0)], 3), ([], [], True))
        rows = [(1, 0, 4, -7), (2, 0, 4, -7), (3, 0, 4, 0), (4, 0, 0, 0)]
        self.assertEqual(self.resolve(rows, 4), ([], [], True))


class ProjectionTest(unittest.TestCase):
    def setUp(self):
        self.row = dict(zip((f"Region_{i}" for i in range(6)), (100, 200, -10, 300, 600, 10), strict=True))
        self.row.update(UiMin_0="0", UiMin_1="0", UiMax_0="1", UiMax_1="1")

    def test_axes_and_boundaries(self):
        self.assertEqual(project(self.row, 300, 600), (0, 0))
        self.assertEqual(project(self.row, 100, 200), (1, 1))
        self.assertEqual(project(self.row, 150, 500), (0.25, 0.75))
        self.assertIsNone(project(self.row, 301, 500))
        self.assertIsNone(project(self.row, 150, 500, 11))

    def test_subrectangle_and_degenerate(self):
        self.row.update(UiMin_0="0.2", UiMax_0="0.6", UiMin_1="0.4", UiMax_1="0.8")
        x, y = project(self.row, 200, 400)
        self.assertAlmostEqual(x, 0.4)
        self.assertAlmostEqual(y, 0.6)
        self.row["Region_3"] = self.row["Region_0"]
        self.assertIsNone(project(self.row, 100, 400))


class GeometryTest(unittest.TestCase):
    @staticmethod
    def row(ui_map, map_id, region, doodad=0):
        row = {"UiMapID": str(ui_map), "MapID": str(map_id), "WMODoodadPlacementID": str(doodad)}
        row.update((f"Region_{i}", str(value)) for i, value in enumerate(region))
        return row

    def test_darkshore_centre_and_continent(self):
        # Darkshore's UiMapAssignment row at 1.60.1.69913: Kalimdor (MapID 1).
        darkshore = self.row(1439, 1, (3966.6665039062, -3608.3332519531, -1e6, 8333.3330078125, 2941.6665039062, 1e6))
        other = self.row(1440, 1, (829.1666, -4066.6665, -1e6, 4672.9165, 1699.9999, 1e6))
        self.assertEqual(
            geometry([darkshore, other], {1439}, {1439: "Darkshore"}),
            {1439: {"name": "Darkshore", "continent": 1, "cx": 6150.0, "cy": -333.3, "sx": 6550.0, "sy": 4366.7}},
        )

    def test_ambiguous_or_partial_rows_left_out(self):
        region = (0, 0, -1, 10, 10, 1)
        rows = [self.row(947, 0, region), self.row(947, 1, region), self.row(1453, 0, region, doodad=5)]
        self.assertEqual(geometry(rows, {947, 1453}, {}), {})

    def test_continent_shift_onto_the_world_map(self):
        # Kalimdor's row on UiMap 947 (Azeroth, a Type 1 world map) at 1.60.1.69913. A continent map's own row
        # (Type 2) is not a world map, and a continent no place uses is left out.
        kalimdor = self.row(947, 1, (-12800, -9600, -1e6, 12266.700195312, 6933.2998046875, 1e6))
        kalimdor.update(UiMin_0="0.03990000114", UiMax_0="0.40830001235", UiMin_1="0.08550000191")
        kalimdor["UiMax_1"] = "0.92339998484"
        eastern = self.row(1415, 0, (-16000, -19199.9, -1e6, 7466.6, 16000, 1e6))
        ui_maps = [{"ID": "947", "Type": "1"}, {"ID": "1415", "Type": "2"}]
        self.assertEqual(continents(ui_maps, [kalimdor, eastern], {0, 1}), {1: {"x": 8724.0, "y": 14824.5}})
        self.assertEqual(continents(ui_maps, [kalimdor], {0}), {})


class CrossingTest(unittest.TestCase):
    @staticmethod
    def node(path, index, continent, x, y, delay):
        return {"PathID": path, "NodeIndex": index, "ContinentID": continent, "Loc_0": x, "Loc_1": y, "Delay": delay}

    @staticmethod
    def taxi(continent, x, y, flags):
        return {"ContinentID": continent, "Pos_0": x, "Pos_1": y, "Flags": flags}

    def test_docks_and_sides(self):
        # Serenity's Shore (176310) on TaxiPath 295 at 1.60.1.69913: Menethil Harbor to Auberdine.
        path = [
            self.node(295, 24, 1, "6406.2158", "823.0809", 60),
            self.node(295, 7, 0, "-3709.474", "-575.0987", 60),
            self.node(295, 12, 0, "-3000", "-900", 0),
        ]
        taxis = [self.taxi(0, "-3790.5", "-783.3", 1025), self.taxi(1, "6343.2", "561.6", 1025)]
        boat = {"entry": 176310, "type": 15, "data0": 295}
        self.assertEqual(
            crossings([boat, {"entry": 1, "type": 3, "data0": 295}], path, taxis, {0, 1}),
            [
                {
                    "transport": 176310,
                    "side": 1,
                    "a": {"continent": 0, "x": -3709.5, "y": -575.1},
                    "b": {"continent": 1, "x": 6406.2, "y": 823.1},
                }
            ],
        )
        # A dock no flight master stands near serves nobody; a continent off the world map is left out.
        self.assertEqual(crossings([boat], path, taxis[:1], {0, 1}), [])
        self.assertEqual(crossings([boat], path, taxis, {0}), [])


if __name__ == "__main__":
    unittest.main()
