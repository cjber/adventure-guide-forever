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


if __name__ == "__main__":
    unittest.main()
