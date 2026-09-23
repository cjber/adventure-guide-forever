"""tools/screenshots.py's anchor resolver, which needs no Pillow; rendering is checked only where Pillow is present."""

import importlib.util
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import screenshots  # noqa: E402

ROOT = {"root": (0, 0, 300, 200)}


def anchor(point, relative_to="root", relative_point=None, x=0, y=0):
    return {"point": point, "relativeTo": relative_to, "relativePoint": relative_point or point, "x": x, "y": y}


def entry(path, anchors, size=None, **extra):
    return {"path": path, "type": "Frame", "anchors": anchors, "size": size, **extra}


class Resolve(unittest.TestCase):
    def test_both_edges_give_the_size(self):
        rects = screenshots.resolve(
            [entry("a", [anchor("TOPLEFT", x=10, y=-5), anchor("BOTTOMRIGHT", x=-20, y=15)])], ROOT
        )
        self.assertEqual(rects["a"], (10, 5, 270, 180))

    def test_one_edge_and_a_centre_keep_the_explicit_size(self):
        # TOPLEFT and RIGHT: the height stays the explicit one, placed from the top (BNet.xml's TopLine).
        rects = screenshots.resolve([entry("a", [anchor("TOPLEFT", y=-10), anchor("RIGHT", x=-10)], (0, 12))], ROOT)
        self.assertEqual(rects["a"], (0, 10, 290, 12))

    def test_centre_alone_places_by_the_centre(self):
        rects = screenshots.resolve([entry("a", [anchor("CENTER", x=5, y=5)], (20, 10))], ROOT)
        self.assertEqual(rects["a"], (145, 90, 20, 10))

    def test_intrinsic_size_when_nothing_else_sets_it(self):
        rects = screenshots.resolve(
            [entry("a", [anchor("TOPLEFT")])], ROOT, intrinsic=lambda e, width=None: (40, 12 if width else 0)
        )
        self.assertEqual(rects["a"], (0, 0, 40, 12))

    def test_chained_relative_regions(self):
        entries = [
            entry("a", [anchor("TOPLEFT", x=8, y=-4)], (100, 20)),
            entry("a.b", [anchor("TOPLEFT", "a", "BOTTOMLEFT", y=-6)], (50, 10)),
        ]
        self.assertEqual(screenshots.resolve(entries, ROOT)["a.b"], (8, 30, 50, 10))

    def test_no_anchors_is_not_drawn_unless_defaults_supply_them(self):
        entries = [entry("a", [], (10, 10)), entry("a.scrollChild", [], (5, 5))]
        rects = screenshots.resolve(entries, {"a": (1, 2, 10, 10)}, defaults=screenshots.scroll_child_anchors)
        self.assertEqual(rects["a.scrollChild"], (1, 2, 5, 5))
        self.assertIsNone(screenshots.resolve([entry("b", [], (10, 10))], ROOT)["b"])

    def test_unknown_relative_frame_fails(self):
        with self.assertRaises(KeyError):
            screenshots.resolve([entry("a", [anchor("TOPLEFT", "Nowhere")])], ROOT)

    def test_cycles_fail(self):
        entries = [entry("a", [anchor("TOPLEFT", "b")]), entry("b", [anchor("TOPLEFT", "a")])]
        with self.assertRaises(ValueError):
            screenshots.resolve(entries, ROOT)

    def test_lua_rects_flip_y(self):
        self.assertEqual(screenshots.lua_rects({"a": (10, 20, 30, 40), "b": None}), {"a": [10, -60, 30, 40]})


class Stock(unittest.TestCase):
    def test_unknown_stock_template_fails_the_run(self):
        with self.assertRaises(SystemExit):
            screenshots.stock(entry("a", [], stockTemplate="NoSuchTemplate"))

    def test_every_recipe_cites_blizzard_source(self):
        for name, (draw, *_) in screenshots.STOCK.items():
            self.assertRegex(draw.__doc__ or "", r"\.(xml|lua)", name)


@unittest.skipUnless(
    importlib.util.find_spec("PIL") and (screenshots.WOWMOCK / "wowmock.py").is_file(), "Pillow or wowmock missing"
)
class Render(unittest.TestCase):
    def test_wowmock_loads_the_fonts_the_addon_uses(self):
        wm = screenshots.load_wowmock()
        for name in ("GameFontNormalMed3", "GameFontDisable"):
            self.assertIn(name, wm.FONTS)


if __name__ == "__main__":
    unittest.main()
