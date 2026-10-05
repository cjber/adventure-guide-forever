import tempfile
import unittest
from pathlib import Path
from unittest import mock

import gen_quests


class Db2Test(unittest.TestCase):
    def rows(self, text, columns=("ID", "Value")):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / f"T-{gen_quests.BUILD}.csv").write_text(text, encoding="utf-8")
            with mock.patch.object(gen_quests, "CACHE", cache):
                return gen_quests.db2("T", columns, offline=True)

    def test_valid_rows_keep_their_strings(self):
        self.assertEqual(self.rows("ID,Value\n1,2\n"), [{"ID": "1", "Value": "2"}])

    def test_rejects_malformed_exports(self):
        for text, message in (
            ("ID,Value,Value\n1,2,3\n", "duplicate columns"),
            ("ID,Value\n1,2\n1,3\n", "duplicate ID"),
            ("ID,Value\n1\n", "malformed CSV row"),
            ("ID\n1\n", "missing required columns"),
            ("ID,Value\n", "empty export"),
        ):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, message):
                self.rows(text)

    def test_invalid_refresh_preserves_cached_source(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            path = cache / f"T-{gen_quests.BUILD}.csv"
            original = b"ID,Value\n1,2\n"
            path.write_bytes(original)
            with (
                mock.patch.object(gen_quests, "CACHE", cache),
                mock.patch.object(gen_quests.wago, "read_source", return_value=(b"ID,Value,Value\n1,2,3\n", True)),
                self.assertRaisesRegex(ValueError, "duplicate columns"),
            ):
                gen_quests.db2("T", ("ID", "Value"), refresh=True)
            self.assertEqual(path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
