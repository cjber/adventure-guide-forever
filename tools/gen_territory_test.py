"""Pure territory checks: python3 -m unittest discover -s tools -p '*_test.py'."""

import unittest

from gen_territory import map_ids, render, territory

GEOMETRY = (
    "ns.Data = {\n\tmaps = {\n\t\t[1411] = { name = 'Durotar' },\n\t\t[1413] = { name = 'The Barrens' },\n\t},\n}\n"
)


def assignment(ui_map, area, doodad=0):
    return {"UiMapID": str(ui_map), "AreaID": str(area), "WMODoodadPlacementID": str(doodad)}


def area(ident, mask):
    return {"ID": str(ident), "FactionGroupMask": str(mask)}


class TerritoryTest(unittest.TestCase):
    def test_map_ids(self):
        self.assertEqual(map_ids(GEOMETRY), [1411, 1413])

    def test_the_whole_map_assignment_pins_the_area(self):
        areas = [area(14, 4), area(17, 0), area(99, 2)]
        assignments = [assignment(1411, 14), assignment(1411, 99, 7), assignment(1413, 17)]
        self.assertEqual(territory({1411, 1413}, assignments, areas), {1411: 4, 1413: 0})

    def test_a_map_without_a_mask_is_left_out(self):
        self.assertEqual(territory({1411}, [assignment(1411, 14)], []), {})

    def test_render(self):
        self.assertIn("ns.Data.territory = {\n", render({1411: 4, 1413: 0}))
        self.assertIn("\t[1411] = 4,\n\t[1413] = 0,\n", render({1411: 4, 1413: 0}))


if __name__ == "__main__":
    unittest.main()
