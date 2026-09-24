"""Pure generator checks: python3 -m unittest discover -s tools -p '*_test.py'."""

import unittest

from gen_quests import (
    CAP,
    LINK,
    NAME_REACH,
    continents,
    crossings,
    faction,
    flight_masters,
    gate_names,
    geometry,
    hub_names,
    instance_index,
    nearest_hub,
    overlays,
    parse_values,
    prerequisite_index,
    prerequisites,
    project,
    quest_place,
    reaction,
    requirements,
    roles,
    skill_steps,
    town_hubs,
    world_point,
)


class ParsingTest(unittest.TestCase):
    def test_sql_literals(self):
        self.assertEqual(
            list(parse_values(r"(1,'It\'s (a,b) \\ path',NULL,-3),(2,'It''s\nnext',1.25,0);")),
            [[1, "It's (a,b) \\ path", None, -3], [2, "It's\nnext", 1.25, 0]],
        )

    def test_truncated_or_executable_sql_rejected(self):
        for text in ("(1,'unfinished)", "(1,2)", "(1,NOW());", "(1); DROP TABLE quests;"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                list(parse_values(text))

    def test_faction_masks(self):
        self.assertEqual([faction(mask) for mask in (0, 77, 178, 255, 4, 16)], [3, 1, 2, 3, 1, 2])


class PrerequisiteTest(unittest.TestCase):
    @staticmethod
    def resolve(rows, target):
        quests = {
            qid: {"PrevQuestId": prev, "NextQuestId": nxt, "ExclusiveGroup": group} for qid, prev, nxt, group in rows
        }
        incoming, groups = prerequisite_index(quests)
        return prerequisites(target, quests, incoming, groups)

    def test_signs(self):
        self.assertEqual(self.resolve([(1, 0, 0, 0), (2, 1, 0, 0)], 2), ([1], [], False))
        self.assertEqual(self.resolve([(1, 0, 0, 0), (2, -1, 0, 0)], 2), ([], [], True))
        self.assertEqual(self.resolve([(1, 0, -2, 0), (2, 0, 0, 0)], 2), ([], [], True))

    def test_exclusive_group_signs(self):
        for group, expected in ((7, ([], [1, 2], False)), (-7, ([1, 2], [], False))):
            self.assertEqual(self.resolve([(1, 0, 3, group), (2, 0, 3, group), (3, 0, 0, 0)], 3), expected)
        self.assertEqual(self.resolve([(1, 0, 0, -7), (2, 0, 0, -7), (3, 1, 0, 0)], 3), ([1, 2], [], False))

    def test_unknown_and_complex_requirements(self):
        self.assertEqual(self.resolve([(3, 99, 0, 0)], 3), ([], [], True))
        rows = [(1, 0, 4, -7), (2, 0, 4, -7), (3, 0, 4, 0), (4, 0, 0, 0)]
        self.assertEqual(self.resolve(rows, 4), ([], [], True))


class GateTest(unittest.TestCase):
    NAMES = gate_names(
        [
            {"ID": "197", "CategoryID": "11", "DisplayName_lang": "Tailoring"},
            {"ID": "356", "CategoryID": "9", "DisplayName_lang": "Fishing"},
            {"ID": "43", "CategoryID": "6", "DisplayName_lang": "Swords"},
        ],
        [
            {"ID": "576", "Name_lang": "Timbermaw Hold", "ReputationIndex": "35"},
            {"ID": "529", "Name_lang": "Argent Dawn", "ReputationIndex": "13"},
            {"ID": "169", "Name_lang": "Steamwheedle Cartel", "ReputationIndex": "-1"},
        ],
    )

    @classmethod
    def gates(cls, skill=(0, 0), low=(0, 0), high=(0, 0)):
        row = dict(
            zip(("RequiredSkill", "RequiredSkillValue"), skill, strict=True),
            **dict(zip(("RequiredMinRepFaction", "RequiredMinRepValue"), low, strict=True)),
            **dict(zip(("RequiredMaxRepFaction", "RequiredMaxRepValue"), high, strict=True)),
        )
        return requirements(row, *cls.NAMES)

    def test_names(self):
        self.assertEqual(self.NAMES, ({197: "Tailoring", 356: "Fishing"}, {576: "Timbermaw Hold", 529: "Argent Dawn"}))

    def test_skill(self):
        self.assertEqual(self.gates(skill=(197, 150)), {"skill": {"id": 197, "value": 150}})
        # Player::SatisfyQuestSkill: an unlearned line's rank 0 is never below 0, so a value of 0 asks nothing.
        self.assertEqual(self.gates(skill=(356, 0)), {})
        self.assertIsNone(self.gates(skill=(43, 1)), "a weapon skill is no profession")

    def test_reputation(self):
        self.assertEqual(self.gates(low=(576, 3000)), {"rep": {"faction": 576, "min": 3000}})
        both = self.gates(low=(529, 9000), high=(529, 20999))
        self.assertEqual(both, {"rep": {"faction": 529, "min": 9000, "max": 20999}})
        self.assertEqual(self.gates(high=(576, 0)), {"rep": {"faction": 576, "max": 0}})
        self.assertIsNone(self.gates(low=(576, 3000), high=(529, 9000)), "two factions")
        self.assertIsNone(self.gates(low=(169, 3000)), "a faction with no reputation")
        self.assertEqual(self.gates(), {})


class ProjectionTest(unittest.TestCase):
    def setUp(self):
        self.row = dict(zip((f"Region_{i}" for i in range(6)), (100, 200, -10, 300, 600, 10), strict=True))
        self.row.update(UiMin_0="0", UiMin_1="0", UiMax_0="1", UiMax_1="1")

    def test_axes_and_boundaries(self):
        self.assertEqual(project(self.row, 300, 600), (0, 0))
        self.assertEqual(project(self.row, 100, 200), (1, 1))
        self.assertEqual(project(self.row, 150, 500), (0.25, 0.75))
        self.assertIsNone(project(self.row, 301, 500))
        self.assertIsNone(project(self.row, 150, 500, 11))

    def test_subrectangle_and_degenerate(self):
        self.row.update(UiMin_0="0.2", UiMax_0="0.6", UiMin_1="0.4", UiMax_1="0.8")
        x, y = project(self.row, 200, 400)
        self.assertAlmostEqual(x, 0.4)
        self.assertAlmostEqual(y, 0.6)
        self.row["Region_3"] = self.row["Region_0"]
        self.assertIsNone(project(self.row, 100, 400))


class GeometryTest(unittest.TestCase):
    @staticmethod
    def row(ui_map, map_id, region, doodad=0):
        row = {"UiMapID": str(ui_map), "MapID": str(map_id), "WMODoodadPlacementID": str(doodad)}
        row.update((f"Region_{i}", str(value)) for i, value in enumerate(region))
        return row

    def test_darkshore_centre_and_continent(self):
        # Darkshore's UiMapAssignment row at 1.60.1.69913: Kalimdor (MapID 1).
        darkshore = self.row(1439, 1, (3966.6665039062, -3608.3332519531, -1e6, 8333.3330078125, 2941.6665039062, 1e6))
        other = self.row(1440, 1, (829.1666, -4066.6665, -1e6, 4672.9165, 1699.9999, 1e6))
        self.assertEqual(
            geometry([darkshore, other], {1439}, {1439: "Darkshore"}),
            {1439: {"name": "Darkshore", "continent": 1, "cx": 6150.0, "cy": -333.3, "sx": 6550.0, "sy": 4366.7}},
        )

    def test_ambiguous_or_partial_rows_left_out(self):
        region = (0, 0, -1, 10, 10, 1)
        rows = [self.row(947, 0, region), self.row(947, 1, region), self.row(1453, 0, region, doodad=5)]
        self.assertEqual(geometry(rows, {947, 1453}, {}), {})

    def test_continent_shift_onto_the_world_map(self):
        # Kalimdor's row on UiMap 947 (Azeroth, a Type 1 world map) at 1.60.1.69913. A continent map's own row
        # (Type 2) is not a world map, and a continent no place uses is left out.
        kalimdor = self.row(947, 1, (-12800, -9600, -1e6, 12266.700195312, 6933.2998046875, 1e6))
        kalimdor.update(UiMin_0="0.03990000114", UiMax_0="0.40830001235", UiMin_1="0.08550000191")
        kalimdor["UiMax_1"] = "0.92339998484"
        eastern = self.row(1415, 0, (-16000, -19199.9, -1e6, 7466.6, 16000, 1e6))
        ui_maps = [{"ID": "947", "Type": "1"}, {"ID": "1415", "Type": "2"}]
        self.assertEqual(continents(ui_maps, [kalimdor, eastern], {0, 1}), {1: {"x": 8724.0, "y": 14824.5}})
        self.assertEqual(continents(ui_maps, [kalimdor], {0}), {})


class CrossingTest(unittest.TestCase):
    @staticmethod
    def node(path, index, continent, x, y, delay):
        return {"PathID": path, "NodeIndex": index, "ContinentID": continent, "Loc_0": x, "Loc_1": y, "Delay": delay}

    @staticmethod
    def taxi(continent, x, y, flags):
        return {"ContinentID": continent, "Pos_0": x, "Pos_1": y, "Flags": flags}

    def test_docks_and_sides(self):
        # Serenity's Shore (176310) on TaxiPath 295 at 1.60.1.69913: Menethil Harbor to Auberdine.
        path = [
            self.node(295, 24, 1, "6406.2158", "823.0809", 60),
            self.node(295, 7, 0, "-3709.474", "-575.0987", 60),
            self.node(295, 12, 0, "-3000", "-900", 0),
        ]
        taxis = [self.taxi(0, "-3790.5", "-783.3", 1025), self.taxi(1, "6343.2", "561.6", 1025)]
        boat = {"entry": 176310, "type": 15, "data0": 295}
        self.assertEqual(
            crossings([boat, {"entry": 1, "type": 3, "data0": 295}], path, taxis, {0, 1}),
            [
                {
                    "transport": 176310,
                    "side": 1,
                    "a": {"continent": 0, "x": -3709.5, "y": -575.1},
                    "b": {"continent": 1, "x": 6406.2, "y": 823.1},
                }
            ],
        )
        # A dock no flight master stands near serves nobody; a continent off the world map is left out.
        self.assertEqual(crossings([boat], path, taxis[:1], {0, 1}), [])
        self.assertEqual(crossings([boat], path, taxis, {0}), [])


class InstanceTest(unittest.TestCase):
    def test_area_to_instance(self):
        # The Deadmines' area 1581 sits on Map 36, a party instance; Molten Core's 2717 on 409, a raid; Elwynn
        # Forest's 12 on the Eastern Kingdoms, which is no instance.
        areas = [
            {"ID": "1581", "ContinentID": "36"},
            {"ID": "2717", "ContinentID": "409"},
            {"ID": "12", "ContinentID": "0"},
        ]
        maps = [
            {"ID": "36", "MapName_lang": "Deadmines", "InstanceType": "1"},
            {"ID": "409", "MapName_lang": "Molten Core", "InstanceType": "2"},
            {"ID": "0", "MapName_lang": "Eastern Kingdoms", "InstanceType": "0"},
        ]
        self.assertEqual(
            instance_index(areas, maps),
            (
                {1581: 36, 2717: 409},
                {36: {"name": "Deadmines", "raid": False}, 409: {"name": "Molten Core", "raid": True}},
            ),
        )


class HubTest(unittest.TestCase):
    @staticmethod
    def keys(hubs):
        return [sorted(key for _, _, key in members) for _, members in hubs]

    def test_single_linkage(self):
        # A chain of steps of LINK yards is one town however long; one more yard is another town.
        points = {"a": (0, 0, 0), "b": (0, LINK, 0), "c": (0, 2 * LINK, 0), "d": (0, 3 * LINK + 1, 0)}
        self.assertEqual(self.keys(town_hubs(points)), [["a", "b", "c"], ["d"]])
        # Continents never link, however close their coordinates.
        self.assertEqual(self.keys(town_hubs({"a": (0, 0, 0), "b": (1, 0, 0)})), [["a"], ["b"]])

    def test_wide_towns_split_again(self):
        # Five givers 95 yards apart span 380 yards: one town under CAP. Six span 475: split at LINK - 10, where
        # the 95-yard steps no longer link. A 90-yard pair inside a wide town stays together.
        five = {f"g{i}": (0, 95 * i, 0) for i in range(5)}
        self.assertEqual(self.keys(town_hubs(five)), [sorted(five)])
        six = {f"g{i}": (0, 95 * i, 0) for i in range(6)}
        self.assertEqual(self.keys(town_hubs(six)), [[key] for key in six])
        self.assertGreater(95 * 5, CAP)
        six["near"] = (0, 95, 85)
        self.assertEqual(self.keys(town_hubs(six)), [["g0"], ["g1", "near"], ["g2"], ["g3"], ["g4"], ["g5"]])

    def test_ids_are_stable(self):
        # Ordered by continent, then least x, then least y, whatever order the places come in.
        points = {"k1": (1, 0, 0), "e2": (0, 500, 0), "e1": (0, 0, 500), "e3": (0, 0, 900)}
        expected = [["e1"], ["e3"], ["e2"], ["k1"]]
        self.assertEqual(self.keys(town_hubs(points)), expected)
        self.assertEqual(self.keys(town_hubs(dict(reversed(points.items())))), expected)

    def test_world_point_inverts_the_projection(self):
        # Darkshore's rectangle (GeometryTest): its centre is the map's middle, and map x grows as world y falls.
        darkshore = {"continent": 1, "cx": 6150.0, "cy": -333.3, "sx": 6550.0, "sy": 4366.7}
        self.assertEqual(world_point(darkshore, {"x": 0.5, "y": 0.5}), (6150.0, -333.3))
        x, y = world_point(darkshore, {"x": 0.6, "y": 0.5})
        self.assertAlmostEqual(y, -333.3 - 655.0)
        self.assertEqual(x, 6150.0)


class HubNameTest(unittest.TestCase):
    @staticmethod
    def node(node, name="Lakeshire, Redridge", continent=0, flags=3, mounts=(1, 1), conditions=(0, 0)):
        return {
            "ID": str(node),
            "Name_lang": name,
            "ContinentID": str(continent),
            "Pos_0": "10",
            "Pos_1": "20",
            "Flags": str(flags),
            "ConditionID": str(conditions[0]),
            "VisibilityConditionID": str(conditions[1]),
            "MountCreatureID_0": str(mounts[0]),
            "MountCreatureID_1": str(mounts[1]),
        }

    def test_filter_mirrors_shortest_path(self):
        rows = [
            self.node(1),
            self.node(2, flags=1024),
            self.node(3275, flags=0, mounts=(0, 5)),
            self.node(4, continent=530),
            self.node(5, name="zzOLD Lakeshire"),
            self.node(6, name="Quest - Test"),
            self.node(7, conditions=(9, 0)),
            self.node(8, conditions=(0, 9)),
            self.node(9, mounts=(0, 0)),
            self.node(62),
        ]
        self.assertEqual([n[0] for n in flight_masters(rows)], [1, 3275])
        self.assertEqual(flight_masters(rows[:1]), [(1, 0, 10.0, 20.0, "Lakeshire, Redridge")])

    def test_nearest_within_reach(self):
        hubs = [(0, [(0, 0, "a"), (500, 0, "b")]), (0, [(2000, 0, "c")]), (1, [(0, 0, "d")])]
        nodes = [
            (7, 0, 500 + NAME_REACH, 0, "Far side"),
            (5, 0, 500 - NAME_REACH, 0, "Near side"),
            (3, 0, 2000 + NAME_REACH + 1, 0, "Too far"),
            (1, 0, 0, 0, "At a giver"),
        ]
        # The nearest wins, a tie goes to the lower ID, the reach counts from any giver, and a node on another
        # continent never names a hub.
        self.assertEqual(hub_names(hubs, nodes), {1: {"name": "At a giver"}})
        self.assertEqual(hub_names(hubs, nodes[:3]), {1: {"name": "Near side"}})
        self.assertEqual(hub_names(hubs[2:], [(1, 0, 0, 0, "At a giver")]), {})


class NpcTest(unittest.TestCase):
    @staticmethod
    def template(entry, flags, kind=0, klass=0, race=0, template=0):
        return {
            "Entry": entry,
            "NpcFlags": flags,
            "TrainerType": kind,
            "TrainerClass": klass,
            "TrainerRace": race,
            "TrainerTemplateId": template,
        }

    @staticmethod
    def taught(entry, spell, level=0, condition=0):
        return {"entry": entry, "spell": spell, "reqlevel": level, "condition_id": condition}

    def test_skill_steps(self):
        # Journeyman Alchemy's teaching spell 2280 at 1.60.1.69913: LEARN_SPELL (36), then SKILL_STEP (44) rank 2.
        effects = [
            {"SpellID": "2280", "Effect": "36", "EffectMiscValue_0": "0", "EffectBasePointsF": "25"},
            {"SpellID": "2280", "Effect": "44", "EffectMiscValue_0": "171", "EffectBasePointsF": "2"},
            # CMaNGOS's old Lockpicking line 242 (1809) is no SkillLine; Frost (6, a class line) is no profession.
            {"SpellID": "1809", "Effect": "44", "EffectMiscValue_0": "242", "EffectBasePointsF": "1"},
            {"SpellID": "1", "Effect": "44", "EffectMiscValue_0": "6", "EffectBasePointsF": "1"},
        ]
        lines = [{"ID": "171", "CategoryID": "11"}, {"ID": "129", "CategoryID": "9"}, {"ID": "6", "CategoryID": "7"}]
        self.assertEqual(skill_steps(effects, lines), {2280: (171, 2)})

    def test_roles(self):
        tables = {
            "creature_template": [
                self.template(5497, 16 | 2, klass=8, template=9),  # a mage trainer, spells from a template
                self.template(198, 16, klass=8),  # a starting-area mage trainer
                self.template(5499, 16, kind=2),  # an alchemy trainer: Apprentice and Journeyman
                self.template(1, 16, kind=2),  # a profession trainer with no rank spell
                self.template(2, 16, kind=2),  # ranks of two skills
                self.template(4732, 16, kind=1, race=1),
                self.template(543, 16, kind=3, klass=3),
                self.template(2485, 16, klass=8),  # a portal trainer: spells from level 20 only
                self.template(3, 16, klass=0),  # a weapon master
                self.template(4, 16, klass=4),  # teaches only behind a condition
                self.template(6929, 128 | 1),
                self.template(347, 2048),
                self.template(5, 4),
            ],
            "npc_trainer": [
                self.taught(198, 10, 1),
                self.taught(198, 11, 6),
                self.taught(5499, 2275, 5),
                self.taught(5499, 2280, 10),
                self.taught(5499, 99),
                self.taught(1, 99),
                self.taught(2, 2275),
                self.taught(2, 2372),
                self.taught(4732, 33389, 40),
                self.taught(543, 20),
                self.taught(2485, 32, 20),
                self.taught(2485, 33, 40),
                self.taught(3, 21),
                self.taught(4, 22, 10, condition=7),
            ],
            "npc_trainer_template": [self.taught(9, 30, 60), self.taught(9, 31, 1)],
            "battlemaster_entry": [{"entry": 347, "bg_template": 1}],
        }
        steps = {2275: (171, 1), 2280: (171, 2), 2372: (182, 1)}
        self.assertEqual(
            roles(tables, steps),
            {
                198: {"class": 8, "upto": 6},
                347: {"bg": 1},
                543: {"pet": True},
                4732: {"riding": True, "race": 1},
                2485: {"class": 8, "upto": 40, "from": 20},
                5497: {"class": 8, "upto": 60},
                5499: {"skill": 171, "rank": 2},
                6929: {"inn": True},
            },
        )

    def test_reaction(self):
        # FactionTemplate.EnemyGroup at 1.60.1.69913: 12 Stormwind 4, 85 Orgrimmar 2, 120 Booty Bay 0; 12 and 10
        # add bit 8 (monsters); 1 is hostile to every player. A template the DB2 lacks has no side.
        self.assertEqual(
            [reaction(r and {"EnemyGroup": r}) for r in ("4", "2", "0", "12", "10", "1", None)],
            [1, 2, 3, 1, 2, 0, 0],
        )

    def test_nearest_hub(self):
        grid = {(0, 0, 0): [(10, 10, 1), (60, 10, 2)], (0, 1, 0): [(150, 10, 3)], (1, 0, 0): [(0, 0, 4)]}
        self.assertEqual(nearest_hub((0, 40, 10), grid), 2)
        self.assertEqual(nearest_hub((0, 150 + LINK, 10), grid), 3)
        self.assertIsNone(nearest_hub((0, 151 + LINK, 10), grid))
        self.assertIsNone(nearest_hub((2, 0, 0), grid))


class QuestPlaceTest(unittest.TestCase):
    def spawn(self, kind):
        return {"entry": (kind, 823), "name": "Deputy Willem", "options": [(1.0, 0, 1429, (0.48171, 0.42939))]}

    def test_an_npc_giver_keeps_its_creature_entry(self):
        self.assertEqual(
            quest_place(self.spawn("creature"), {1429}, None),
            {"map": 1429, "x": 0.4817, "y": 0.4294, "name": "Deputy Willem", "npc": 823},
        )

    def test_an_object_has_no_npc(self):
        self.assertNotIn("npc", quest_place(self.spawn("gameobject"), {1429}, None))


class OverlayTest(unittest.TestCase):
    MAPS = [{"ID": "1439", "Type": "3"}, {"ID": "1414", "Type": "2"}]
    ART = [
        {"UiMapID": "1439", "UiMapArtID": "2171", "PhaseID": "0"},
        {"UiMapID": "1414", "UiMapArtID": "2171", "PhaseID": "0"},
    ]
    AREAS = [
        {"ID": "447", "AreaName_lang": "Ameth'Aran", "ExplorationLevel": "11"},
        {"ID": "442", "AreaName_lang": "Auberdine", "ExplorationLevel": "12"},
        {"ID": "616", "AreaName_lang": "Mount Hyjal", "ExplorationLevel": "0"},
    ]

    @staticmethod
    def row(overlay, area, offset, size=(256, 256), hit=(350, 420, 395, 460), condition=0):
        keys = ("HitRectTop", "HitRectBottom", "HitRectLeft", "HitRectRight")
        row = {"ID": str(overlay), "UiMapArtID": "2171", "AreaID_0": str(area), "PlayerConditionID": str(condition)}
        row.update(
            OffsetX=str(offset[0]), OffsetY=str(offset[1]), TextureWidth=str(size[0]), TextureHeight=str(size[1])
        )
        row.update(zip(keys, map(str, hit), strict=True))
        return row

    def test_darkshore_overlay_matches_the_probe(self):
        # WorldMapOverlay 5385 at 1.60.1.69913; the probe's GetExploredMapTextures(1439) gave offset 324, 306 and this
        # hit rectangle. The Kalimdor map shares the art but is no zone map.
        self.assertEqual(
            overlays(self.MAPS, self.ART, [self.row(5385, 447, (324, 306))], self.AREAS),
            {1439: [{"area": 447, "name": "Ameth'Aran", "level": 11, "ox": 324, "oy": 306, "x": 0.4266, "y": 0.5763}]},
        )

    def test_unknowable_or_unsuggestable_overlays_left_out(self):
        rows = [
            self.row(1, 616, (10, 10)),  # ExplorationLevel 0
            self.row(2, 447, (20, 20), size=(0, 0)),  # no texture: never returned as explored
            self.row(3, 447, (30, 30), condition=5),  # drawn only under a condition
            self.row(4, 999, (40, 40)),  # no AreaTable row
            self.row(5, 447, (50, 50)),  # shares its offset with 6
            self.row(6, 442, (50, 50)),
        ]
        self.assertEqual(overlays(self.MAPS, self.ART, rows, self.AREAS), {})


if __name__ == "__main__":
    unittest.main()
