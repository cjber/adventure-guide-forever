"""Encounter fallback requires explicit kill credits and complete Classic coverage."""

import unittest

from gen_bosses import DUNGEON_LEVELS, encounters


class EncounterTests(unittest.TestCase):
    def test_credits_and_coverage(self):
        tables = {"instance_dungeon_encounters": [], "instance_encounters": [], "creature_template": []}
        for instance in DUNGEON_LEVELS:
            tables["instance_dungeon_encounters"].append(
                {"MapId": instance, "Id": instance, "Difficulty": 0, "EncounterIndex": 0, "EncounterName": "Boss"}
            )
            tables["instance_encounters"].append({"entry": instance, "creditType": 0, "creditEntry": instance + 10000})
            tables["creature_template"].append({"Entry": instance + 10000, "MinLevel": 20, "MaxLevel": 21})
        result = encounters(tables)
        self.assertEqual(set(result), set(DUNGEON_LEVELS))
        self.assertEqual(result[36][0]["id"], 10036)
        tables["instance_encounters"][0]["creditType"] = 1
        with self.assertRaisesRegex(ValueError, "No verified encounters"):
            encounters(tables)


if __name__ == "__main__":
    unittest.main()
