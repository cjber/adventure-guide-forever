"""no-em-dash over generator banners, generated data and the paths it leaves alone."""

import unittest

from tools.repo_rules import em_dashes


class EmDashTest(unittest.TestCase):
    def test_flags_banners_in_tools_and_data(self):
        self.assertEqual(len(em_dashes("tools/generate.py", '# ok\nbanner = "Generated \u2014 do not edit."')), 1)
        self.assertEqual(em_dashes("Data/Output.lua", "-- Generated \u2014 do not edit.")[0][:18], "Data/Output.lua:1:")

    def test_a_colon_and_other_paths_pass(self):
        self.assertEqual(em_dashes("tools/generate.py", 'banner = "Generated: do not edit."'), [])
        for path in ("Data/example.py", "docs/example.py", "tools/example.txt", "tools/sub/x.py"):
            self.assertEqual(em_dashes(path, "# \u2014"), [], path)


if __name__ == "__main__":
    unittest.main()
