#!/usr/bin/env python3
"""Run from the repository root: python3 tools/check_screenshots_test.py"""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_screenshots
from check_screenshots import screens

WARN = {"SCREENSHOTS_STALE_WARN": "true"}


class StaleScreenshots(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.out = Path(folder.name)
        self.dumps = {"a.png": b"scene a", "b.png": b"scene b"}
        for name in self.dumps:
            (self.out / name).write_bytes(b"image " + name.encode())
        scenes = {name: (lambda name=name: self.dumps[name]) for name in self.dumps}
        for patch in (
            mock.patch.object(check_screenshots, "OUT", self.out),
            mock.patch.object(check_screenshots, "SCENES", scenes),
        ):
            patch.start()
            self.addCleanup(patch.stop)
        screens.record(self.out, scenes, force=True)

    def run_check(self, env, argv=()):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = check_screenshots.main(list(argv), env)
        return code, out.getvalue(), err.getvalue()

    def test_current_images_pass_either_way(self):
        self.assertEqual(self.run_check({})[0], 0)
        code, out, _ = self.run_check(WARN)
        self.assertEqual(code, 0)
        self.assertNotIn("::warning", out)

    def test_a_moved_scene_fails_by_default(self):
        self.dumps["a.png"] = b"scene a, new data"
        code, _, err = self.run_check({"GITHUB_HEAD_REF": "data/refresh"})
        self.assertEqual(code, 1)
        self.assertIn("a.png", err)

    def test_a_moved_scene_only_warns_on_the_data_pr(self):
        self.dumps["a.png"] = b"scene a, new data"
        code, out, _ = self.run_check(WARN)
        self.assertEqual(code, 0)
        self.assertIn("::warning title=Stale screenshot::a.png", out)
        self.assertNotIn("b.png", out)

    def test_an_image_changed_without_record_still_fails_on_the_data_pr(self):
        (self.out / "a.png").write_bytes(b"rendered again")
        self.assertEqual(self.run_check(WARN)[0], 1)

    def test_a_missing_image_still_fails_on_the_data_pr(self):
        (self.out / "b.png").unlink()
        code, _, err = self.run_check(WARN)
        self.assertEqual(code, 1)
        self.assertIn("b.png: missing", err)

    def test_any_other_value_is_not_the_data_pr(self):
        self.dumps["a.png"] = b"scene a, new data"
        self.assertEqual(self.run_check({"SCREENSHOTS_STALE_WARN": "false"})[0], 1)

    def test_record_is_unchanged(self):
        with mock.patch.object(screens, "main", return_value=0) as shared:
            self.assertEqual(check_screenshots.main(["--record"], WARN), 0)
        shared.assert_called_once_with(self.out, check_screenshots.SCENES, ["--record"])

    def test_annotations_are_escaped(self):
        self.assertEqual(check_screenshots.annotation("50% done\nnext"), "50%25 done%0Anext")


if __name__ == "__main__":
    unittest.main()
