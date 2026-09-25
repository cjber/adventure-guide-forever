"""Pure zone-art checks: python3 -m unittest discover -s tools -p '*_test.py'."""

import unittest

from gen_zoneart import quest_zones, render, tiles_needed, zone_art

QUESTS = (
    "ns.Data = {\n\tzones = {\n\t\t[1411] = { name = 'Durotar' },\n\t\t[1413] = { name = 'The Barrens' },\n\t},\n}\n"
)


def overlay(ident, art, width, height, condition=0):
    return {
        "ID": str(ident),
        "UiMapArtID": str(art),
        "TextureWidth": str(width),
        "TextureHeight": str(height),
        "OffsetX": "10",
        "OffsetY": "20",
        "PlayerConditionID": str(condition),
    }


def tile(overlay_id, row, col, file):
    return {
        "WorldMapOverlayID": str(overlay_id),
        "RowIndex": str(row),
        "ColIndex": str(col),
        "LayerIndex": "0",
        "FileDataID": str(file),
    }


class ZoneArtTest(unittest.TestCase):
    def test_quest_zones(self):
        self.assertEqual(quest_zones(QUESTS), [1411, 1413])

    def test_tiles_needed_rounds_up(self):
        self.assertEqual(tiles_needed(256, 256), 1)
        self.assertEqual(tiles_needed(300, 100), 2)
        self.assertEqual(tiles_needed(513, 257), 6)

    def test_zone_art_keeps_whole_unconditioned_overlays_row_major(self):
        map_art = [
            {"ID": "2", "UiMapID": "1411", "UiMapArtID": "99", "PhaseID": "0"},
            {"ID": "1", "UiMapID": "1411", "UiMapArtID": "7", "PhaseID": "0"},
            {"ID": "3", "UiMapID": "1413", "UiMapArtID": "8", "PhaseID": "0"},
        ]
        arts = [{"ID": "7", "UiMapArtStyleID": "1"}, {"ID": "8", "UiMapArtStyleID": "2"}]
        layer = {"LayerIndex": "0", "TileWidth": "256"}
        layers = [
            {"UiMapArtStyleID": "1", "LayerWidth": "1002", "LayerHeight": "668", **layer},
            {"UiMapArtStyleID": "2", "LayerWidth": "2048", "LayerHeight": "1024", **layer},
        ]
        overlays = [
            overlay(5, 7, 300, 100),
            overlay(4, 7, 100, 100, condition=12),
            overlay(6, 7, 100, 100),
            overlay(9, 8, 100, 100),
        ]
        tiles = [tile(5, 0, 1, 51), tile(5, 0, 0, 50), tile(4, 0, 0, 40), tile(9, 0, 0, 90)]
        art = zone_art({1411, 1413}, map_art, arts, layers, overlays, tiles)
        self.assertEqual(art, {1411: [(10, 20, 300, 100, [50, 51])]})

    def test_render(self):
        text = render({1411: [(10, 20, 300, 100, [50, 51])]})
        self.assertIn("ns.Data.zoneArt = {\n\t[1411] = {\n\t\t{ 10, 20, 300, 100, 50, 51 },\n\t},\n}\n", text)


if __name__ == "__main__":
    unittest.main()
