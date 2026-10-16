"""Every committed generated output must be compared; the test corpus is built, never committed, so it is not."""

import tempfile
import unittest
from pathlib import Path

import check_generated
import gen_quests
from gen_corpus import FIXTURE, ROOT, TOWN_FIXTURE


class GeneratedTest(unittest.TestCase):
    def test_stale_output_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            geometry = gen_quests.OUTPUT.relative_to(ROOT).as_posix()
            for name in check_generated.DATA:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"committed\n")
            expected = check_generated.outputs(root)
            (root / geometry).write_bytes(b"regenerated\n")
            with self.assertRaisesRegex(SystemExit, geometry):
                check_generated.compare(expected, check_generated.outputs(root), "Stale generated files")

    def test_the_corpus_is_not_committed_output(self):
        # QuestieDB carries no licence (WFA-28): the corpus is built into the gitignored tests/.corpus/ instead.
        for path in (FIXTURE, TOWN_FIXTURE):
            self.assertNotIn(path.relative_to(ROOT).as_posix(), check_generated.DATA)
            self.assertEqual(path.parent.name, ".corpus")
        self.assertIn("tests/.corpus/", (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines())


if __name__ == "__main__":
    unittest.main()
