"""What the translation template holds: literal lines under their keys, never a GlobalString the client translates."""

import io
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from phrases import HEADER, KEYWORD, keyword_files, main, phrases, render


class PhrasesTests(unittest.TestCase):
    def test_release_tokens_only_fail_in_processed_package_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tools").mkdir()
            (root / ".pkgmeta").write_text("package-as: Example\nignore:\n  - tools\nplain-copy:\n  - Raw.lua\n")
            for name in (
                "Runtime.lua",
                "Raw.lua",
                "tools/check.lua",
                "checker.py",
                "README.md",
                "notes.txt",
                "Panel.xml",
                "Other.toc",
                "Example.toc",
            ):
                (root / name).write_text(
                    ("## Interface: 16001\n" if name == "Example.toc" else "") + KEYWORD + " export\n"
                )
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            with patch("phrases.ROOT", root):
                self.assertEqual(keyword_files(), ["Example.toc", "Runtime.lua"])

    def test_check_rejects_unassigned_wrapped_shared_phrase(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shared = root / "Shared.lua"
            (root / "Example.toc").write_text("## Interface: 16001\nenUS.lua\nShared.lua\n")
            shared.write_text(
                'local function phrase(key, ...) return (ns.L or {})[key] end\nphrase(\n"Missing %s", name)\n'
            )
            english = root / "enUS.lua"
            english.write_text('ns.L = { A = "a" }\n')
            template = root / "phrases.txt"
            template.write_text(render(phrases(english.read_text())))
            with (
                patch("phrases.ROOT", root),
                patch("phrases.STRINGS", english),
                patch("phrases.PHRASES", template),
                patch("phrases.keyword_files", return_value=[]),
                patch("sys.argv", ["phrases.py", "--check"]),
            ):
                output = io.StringIO()
                with redirect_stdout(output):
                    self.assertEqual(main(), 1)
                self.assertIn("Shared.lua: missing ns.L assignment in Locales/enUS.lua: Missing %s", output.getvalue())
                english.write_text(english.read_text() + 'ns.L["Missing %s"] = "Missing %s"\n')
                template.write_text(render(phrases(english.read_text())))
                self.assertEqual(main(), 0)

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
