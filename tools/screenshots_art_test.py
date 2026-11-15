#!/usr/bin/env python3
"""Run from the repository root: python3 tools/screenshots_art_test.py

The companion asset resolver reads RestedXP's own logo from the installed addon or the pinned cache, and never draws
substitute art: a missing, unpinned or changed file stops the render.
"""

import hashlib
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import screenshots_art as art

DATA = b"BLP2 test asset"
SHA = hashlib.sha256(DATA).hexdigest()
PINNED = {"textures/v2/logo": ("Textures/v2/logo.blp", SHA)}


class CompanionAsset(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.addons = self.root / "Interface/AddOns"
        self.cache = self.root / "cache"
        for patch in (
            mock.patch.object(art, "RXP_CACHE", self.cache),
            mock.patch.dict(art.RXP_ASSETS, PINNED, clear=True),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def write(self, path, data=DATA):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def test_reads_the_installed_addon_first(self):
        self.write(self.addons / "RXPGuides/Textures/v2/logo.blp")
        with mock.patch.dict(os.environ, {"AGF_ADDONS_ROOT": str(self.addons)}):
            self.assertEqual(art.companion_asset("Textures/v2/logo"), DATA)
        self.assertFalse((self.cache / "RXPGuides/Textures/v2/logo.blp").exists())

    def test_a_changed_installed_file_stops_the_render(self):
        self.write(self.addons / "RXPGuides/Textures/v2/logo.blp", b"someone else's art")
        with (
            mock.patch.dict(os.environ, {"AGF_ADDONS_ROOT": str(self.addons)}),
            self.assertRaises(SystemExit) as caught,
        ):
            art.companion_asset("Textures/v2/logo")
        self.assertIn("not the pinned", str(caught.exception))

    def test_reads_a_verified_cache(self):
        self.write(self.cache / "RXPGuides/Textures/v2/logo.blp")
        with mock.patch.dict(os.environ, {"AGF_ADDONS_ROOT": ""}):
            self.assertEqual(art.companion_asset("Textures/v2/logo"), DATA)

    def test_downloads_and_caches_a_missing_file(self):
        with (
            mock.patch.dict(os.environ, {"AGF_ADDONS_ROOT": ""}),
            mock.patch.object(art.urllib.request, "urlopen", return_value=io.BytesIO(DATA)),
        ):
            self.assertEqual(art.companion_asset("Textures/v2/logo"), DATA)
        self.assertEqual((self.cache / "RXPGuides/Textures/v2/logo.blp").read_bytes(), DATA)

    def test_a_bad_download_is_not_cached(self):
        with (
            mock.patch.dict(os.environ, {"AGF_ADDONS_ROOT": ""}),
            mock.patch.object(art.urllib.request, "urlopen", return_value=io.BytesIO(b"not the pin")),
            self.assertRaises(SystemExit),
        ):
            art.companion_asset("Textures/v2/logo")
        self.assertFalse((self.cache / "RXPGuides/Textures/v2/logo.blp").exists())

    def test_an_unpinned_file_stops_the_render(self):
        with self.assertRaises(SystemExit) as caught:
            art.companion_asset("Textures/unknown")
        self.assertIn("no pinned asset", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
