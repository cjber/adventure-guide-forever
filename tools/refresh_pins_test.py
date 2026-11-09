#!/usr/bin/env python3
"""Run from the repository root: python3 tools/refresh_pins_test.py"""

import json
import os
import unittest
from unittest import mock

import refresh_pins

BUILDS = {
    "wow_classic_beta": [{"version": "5.5.0.62071"}, {"version": "1.60.1.9999"}, {"version": "1.60.1.70205"}],
    "wow_classic_era": [{"version": "1.15.9.70003"}, {"version": "1.15.9.69722"}],
}

RELEASES = [
    {
        "tag_name": "v1.0.12",
        "draft": False,
        "prerelease": False,
        "assets": [{"name": "QuestieDB-1.0.12-all.zip", "browser_download_url": "https://example.test/1.0.12-all.zip"}],
    },
    {
        "tag_name": "v1.0.11",
        "draft": False,
        "prerelease": False,
        "assets": [
            {"name": "QuestieDB-1.0.11-all.zip", "browser_download_url": "https://example.test/1.0.11-all.zip"},
            {
                "name": "QuestieDB-1.0.11-Forever.zip",
                "browser_download_url": "https://example.test/1.0.11-Forever.zip",
            },
        ],
    },
    {
        "tag_name": "preview",
        "draft": False,
        "prerelease": True,
        "assets": [
            {
                "name": "QuestieDB-preview-Forever.zip",
                "browser_download_url": "https://example.test/preview-Forever.zip",
            }
        ],
    },
    {
        "tag_name": "v1.0.10",
        "draft": False,
        "prerelease": False,
        "assets": [
            {"name": "QuestieDB-Forever.zip", "browser_download_url": "https://example.test/1.0.10-Forever.zip"}
        ],
    },
]


class Response:
    """The part of an `urlopen` response `json.load` and the digest loop use."""

    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *exception):
        return False

    def read(self):
        return json.dumps(self.payload).encode()


def sent_requests(call, token):
    """The requests `call` makes, with GITHUB_TOKEN set to `token` (absent when None)."""
    requests = []

    def urlopen(request, timeout=None):
        requests.append(request)
        return Response([])

    with mock.patch.dict(os.environ, {"GITHUB_TOKEN": token} if token is not None else {}, clear=False):
        if token is None:
            os.environ.pop("GITHUB_TOKEN", None)
        with mock.patch.object(refresh_pins.urllib.request, "urlopen", urlopen):
            call()
    return requests


class RefreshPins(unittest.TestCase):
    def test_latest_is_the_newest_build_of_the_prefix_by_number(self):
        self.assertEqual(refresh_pins.latest(BUILDS, *refresh_pins.FOREVER, "1.60.1.69913"), "1.60.1.70205")
        self.assertEqual(refresh_pins.latest(BUILDS, *refresh_pins.ERA, "1.15.9.69722"), "1.15.9.70003")

    def test_a_pin_never_moves_backwards(self):
        self.assertEqual(refresh_pins.latest(BUILDS, *refresh_pins.FOREVER, "1.60.2.70300"), "1.60.2.70300")

    def test_no_listed_build_is_an_error(self):
        with self.assertRaises(SystemExit):
            refresh_pins.latest({"wow_classic_beta": []}, *refresh_pins.FOREVER, "1.60.1.69913")

    def test_questiedb_tag_moves_forward_only(self):
        self.assertEqual(refresh_pins.newest_tag("v1.0.4", "v1.0.5"), "v1.0.5")
        self.assertEqual(refresh_pins.newest_tag("v1.0.4", "v1.0.3"), "v1.0.4")
        self.assertEqual(refresh_pins.newest_tag("v1.0.4", "v1.0.4"), "v1.0.4")
        with self.assertRaises(SystemExit):
            refresh_pins.newest_tag("v1.0.4", "1.0.5")

    def test_pin_rewrites_exactly_one_assignment(self):
        self.assertEqual(refresh_pins.pin('A = 1\nBUILD = "x"\n', "BUILD", "y"), 'A = 1\nBUILD = "y"\n')
        with self.assertRaises(SystemExit):
            refresh_pins.pin('BUILD = "x"\nBUILD = "x"\n', "BUILD", "y")

    def test_pin_rewrites_the_questiedb_asset(self):
        self.assertEqual(
            refresh_pins.pin('QUESTIEDB_ASSET = "a.zip"\n', "QUESTIEDB_ASSET", "b.zip"),
            'QUESTIEDB_ASSET = "b.zip"\n',
        )
        with self.assertRaises(SystemExit):
            refresh_pins.pin('QUESTIEDB_ASSET = "a.zip"\nQUESTIEDB_ASSET = "a.zip"\n', "QUESTIEDB_ASSET", "b.zip")

    def test_forever_asset_picks_the_forever_zip(self):
        names = (
            "QuestieDB-1.0.11-all.zip",
            "QuestieDB-1.0.11-Vanilla.zip",
            "QuestieDB-1.0.11-TBC.zip",
            "QuestieDB-1.0.11-Wrath.zip",
            "QuestieDB-1.0.11-Cata.zip",
            "QuestieDB-1.0.11-Mists.zip",
            "QuestieDB-1.0.11-Forever.zip",
            "release.json",
            "RELEASE_NOTES.md",
        )
        release = {
            "tag_name": "v1.0.11",
            "assets": [{"name": name, "browser_download_url": f"https://example.test/{name}"} for name in names],
        }
        self.assertEqual(
            refresh_pins.forever_asset(release),
            ("QuestieDB-1.0.11-Forever.zip", "https://example.test/QuestieDB-1.0.11-Forever.zip"),
        )

    def test_forever_asset_without_one_is_an_error(self):
        release = {"tag_name": "v1.0.12", "assets": [{"name": "QuestieDB-1.0.12-all.zip"}]}
        with self.assertRaises(SystemExit):
            refresh_pins.forever_asset(release)

    def test_newest_release_skips_ones_without_a_forever_asset(self):
        self.assertEqual(refresh_pins.newest_questiedb_release(RELEASES)["tag_name"], "v1.0.11")

    def test_no_release_with_a_forever_asset_is_an_error(self):
        releases = [
            {
                "tag_name": "v1.0.12",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "QuestieDB-1.0.12-all.zip"}],
            }
        ]
        with self.assertRaises(SystemExit):
            refresh_pins.newest_questiedb_release(releases)


class GitHubToken(unittest.TestCase):
    def test_the_release_list_carries_the_workflow_token(self):
        (request,) = sent_requests(refresh_pins.fetch_questiedb_releases, "s3cret")
        self.assertEqual(request.get_header("Authorization"), "Bearer s3cret")

    def test_the_release_list_without_a_token_carries_none(self):
        (request,) = sent_requests(refresh_pins.fetch_questiedb_releases, None)
        self.assertIsNone(request.get_header("Authorization"))

    def test_the_token_goes_only_to_the_github_api(self):
        with mock.patch.dict(os.environ, {"GITHUB_TOKEN": "s3cret"}):
            request = refresh_pins.github_request("https://wago.tools/api/builds")
        self.assertIsNone(request.get_header("Authorization"))


if __name__ == "__main__":
    unittest.main()
