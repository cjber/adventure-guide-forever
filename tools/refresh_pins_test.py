#!/usr/bin/env python3
"""Run from the repository root: python3 tools/refresh_pins_test.py"""

import unittest

import refresh_pins

BUILDS = {
    "wow_classic_beta": [{"version": "5.5.0.62071"}, {"version": "1.60.1.9999"}, {"version": "1.60.1.70205"}],
    "wow_classic_era": [{"version": "1.15.9.70003"}, {"version": "1.15.9.69722"}],
}


class RefreshPins(unittest.TestCase):
    def test_latest_is_the_newest_build_of_the_prefix_by_number(self):
        self.assertEqual(refresh_pins.latest(BUILDS, *refresh_pins.FOREVER, "1.60.1.69913"), "1.60.1.70205")
        self.assertEqual(refresh_pins.latest(BUILDS, *refresh_pins.ERA, "1.15.9.69722"), "1.15.9.70003")

    def test_a_pin_never_moves_backwards(self):
        self.assertEqual(refresh_pins.latest(BUILDS, *refresh_pins.FOREVER, "1.60.2.70300"), "1.60.2.70300")

    def test_no_listed_build_is_an_error(self):
        with self.assertRaises(SystemExit):
            refresh_pins.latest({"wow_classic_beta": []}, *refresh_pins.FOREVER, "1.60.1.69913")

    def test_pin_rewrites_exactly_one_assignment(self):
        self.assertEqual(refresh_pins.pin('A = 1\nBUILD = "x"\n', "BUILD", "y"), 'A = 1\nBUILD = "y"\n')
        with self.assertRaises(SystemExit):
            refresh_pins.pin('BUILD = "x"\nBUILD = "x"\n', "BUILD", "y")


if __name__ == "__main__":
    unittest.main()
