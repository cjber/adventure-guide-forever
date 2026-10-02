"""Every generated output, including the test corpus, must be compared."""

import tempfile
import unittest
from pathlib import Path

import check_generated
from gen_quests import FIXTURE, ROOT


class GeneratedTest(unittest.TestCase):
    def test_stale_quest_fixture_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = FIXTURE.relative_to(ROOT).as_posix()
            for name in {*check_generated.DATA, fixture}:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"committed\n")
            expected = check_generated.outputs(root)
            (root / fixture).write_bytes(b"regenerated\n")
            with self.assertRaisesRegex(SystemExit, fixture):
                check_generated.compare(expected, check_generated.outputs(root), "Stale generated files")


if __name__ == "__main__":
    unittest.main()
