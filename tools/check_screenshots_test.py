#!/usr/bin/env python3
"""Run from the repository root: python3 tools/check_screenshots_test.py"""

import contextlib
import io
import unittest
from unittest import mock

import check_screenshots

STALE = ["panel.png: what it shows changed but the image did not; run tools/screenshots.py"]


def run(env, problems, argv=()):
    out, err = io.StringIO(), io.StringIO()
    with (
        mock.patch.object(check_screenshots.screens, "check", return_value=list(problems)),
        contextlib.redirect_stdout(out),
        contextlib.redirect_stderr(err),
    ):
        code = check_screenshots.main(list(argv), env)
    return code, out.getvalue(), err.getvalue()


class StaleScreenshots(unittest.TestCase):
    def test_a_stale_image_fails_on_a_pull_request(self):
        code, _, err = run({"GITHUB_HEAD_REF": "fix/thing", "GITHUB_REF_NAME": "12/merge"}, STALE)
        self.assertEqual(code, 1)
        self.assertIn("panel.png", err)

    def test_a_stale_image_fails_on_main(self):
        self.assertEqual(run({"GITHUB_HEAD_REF": "", "GITHUB_REF_NAME": "main"}, STALE)[0], 1)

    def test_a_stale_image_fails_locally(self):
        self.assertEqual(run({}, STALE)[0], 1)

    def test_the_data_pull_request_warns_and_passes(self):
        code, out, _ = run({"GITHUB_HEAD_REF": "data/refresh", "GITHUB_REF_NAME": "181/merge"}, STALE)
        self.assertEqual(code, 0)
        self.assertIn("::warning title=Stale screenshot::panel.png", out)

    def test_ci_dispatched_on_the_data_branch_warns_and_passes(self):
        code, out, _ = run({"GITHUB_REF_NAME": "data/refresh"}, STALE)
        self.assertEqual(code, 0)
        self.assertIn("::warning", out)

    def test_the_data_branch_with_nothing_stale_says_so(self):
        code, out, _ = run({"GITHUB_REF_NAME": "data/refresh"}, [])
        self.assertEqual(code, 0)
        self.assertNotIn("::warning", out)

    def test_record_is_unchanged_on_the_data_branch(self):
        with mock.patch.object(check_screenshots.screens, "main", return_value=0) as shared:
            self.assertEqual(check_screenshots.main(["--record"], {"GITHUB_REF_NAME": "data/refresh"}), 0)
        shared.assert_called_once_with(check_screenshots.OUT, check_screenshots.SCENES, ["--record"])


if __name__ == "__main__":
    unittest.main()
