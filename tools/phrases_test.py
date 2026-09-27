"""What the translation template holds: literal lines under their keys, never a GlobalString the client translates."""

import unittest

from phrases import HEADER, phrases, render


class PhrasesTests(unittest.TestCase):
    def test_lines(self):
        source = r"""
            ns.L = {
                B = "joined " .. 'across lines',
                A = 'a "!" over givers',
                C = CLIENT_GLOBAL or "fallback",
                D = "WTF\\Account",
            }
        """
        expected = r"""L["A"] = "a \"!\" over givers"
L["B"] = "joined across lines"
L["D"] = "WTF\\Account"
"""
        self.assertEqual(render(phrases(source)), HEADER + expected)

    def test_unreadable(self):
        # The same walker as the copy lint (lint_copy.ns_l_entries): a missing table or a bracketed key fails loudly.
        for source in ('local L = { A = "a" }', 'ns.L = { ["A"] = "a" }'):
            with self.assertRaises(ValueError, msg=source):
                phrases(source)


if __name__ == "__main__":
    unittest.main()
