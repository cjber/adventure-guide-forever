"""Layout regressions for the approval concept, independent of Pillow and network."""

import unittest
from dataclasses import replace

import journey_preview as preview


class JourneyLayoutTest(unittest.TestCase):
    def test_layout(self):
        preview.validate_layout()

    def test_map_alignment(self):
        with self.assertRaisesRegex(ValueError, "inner edges"):
            preview.validate_layout(map_rect=replace(preview.MAP, x=preview.MAP.x + 1))

    def test_map_aspect(self):
        bad_map = replace(preview.MAP, height=200)
        bad_frame = preview.Rect(bad_map.x - 8, bad_map.y - 8, bad_map.width + 16, bad_map.height + 16)
        with self.assertRaisesRegex(ValueError, "native aspect"):
            preview.validate_layout(map_rect=bad_map, map_frame=bad_frame)

    def test_button_overflow(self):
        with self.assertRaisesRegex(ValueError, "fit inside"):
            preview.validate_layout(buttons=(replace(preview.BUTTONS[0], width=400), preview.BUTTONS[1]))

    def test_empty_column(self):
        with self.assertRaisesRegex(ValueError, "available column"):
            preview.validate_layout(upcoming=preview.UPCOMING[:3])

    def test_stretched_list_art(self):
        with self.assertRaisesRegex(ValueError, "preserve its aspect"):
            preview.validate_art(358, 124, 200, 46)

    def test_fixed_corner_frame(self):
        preview.validate_art(370, 118, 174, 96, sliced=True)
        with self.assertRaisesRegex(ValueError, "fixed eight-pixel corners"):
            preview.validate_art(10, 118, 174, 96, sliced=True)


if __name__ == "__main__":
    unittest.main()
