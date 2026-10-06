"""Saved catalogue reuse must never outlive its producer inputs."""

import unittest

import catalogue_revision


class CatalogueRevisionTest(unittest.TestCase):
    def test_current(self):
        catalogue_revision.check()


if __name__ == "__main__":
    unittest.main()
