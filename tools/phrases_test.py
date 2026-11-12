"""What the translation template holds: literal lines under their keys, never a GlobalString the client translates."""

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from phrases import HEADER, KEYWORD, keyword_files, phrases, render


class PhrasesTests(unittest.TestCase):
    def test_release_tokens_only_fail_in_processed_package_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tools").mkdir()
            (root / ".pkgmeta").write_text("ignore:\n  - tools\nplain-copy:\n  - Raw.lua\n")
            for name in ("Runtime.lua", "Raw.lua", "tools/check.lua", "checker.py"):
                (root / name).write_text(KEYWORD + " export\n")
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            with patch("phrases.ROOT", root):
                self.assertEqual(keyword_files(), ["Runtime.lua"])

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

    def test_a_phrase_assigned_after_the_table(self):
        # A shared file reads ns.L by the English phrase itself, so enUS assigns those keys after its table.
        source = r"""
            ns.L = { A = "a" }
            ns.L["%s: %s is out of date. Update it to fix this."] = "%s: %s is out of date. Update it to fix this."
        """
        found = phrases(source)
        self.assertEqual(found["A"], "a")
        self.assertEqual(
            found["%s: %s is out of date. Update it to fix this."],
            "%s: %s is out of date. Update it to fix this.",
        )

    def test_unreadable(self):
        # The same walker as the copy lint (lint_copy.ns_l_entries): a missing table fails loudly.
        for source in ('local L = { A = "a" }', 'ns.L = { ["A"] "a" }'):
            with self.assertRaises(ValueError, msg=source):
                phrases(source)


if __name__ == "__main__":
    unittest.main()
