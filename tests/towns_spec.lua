-- Towns, their names and the NPCs who serve in them come from the QuestieDB build (QuestieTowns.lua,
-- QuestieSource.lua): a town is the named area of a zone map a place stands in, and nothing about where a giver,
-- trainer or innkeeper stands is bundled.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function noop() end
local function Ready(h)
	h.G.Questie = { API = {
		isReady = true,
		RegisterOnReady = function(fn)
			fn()
		end,
	} }
end

-- A synthetic world: one 1000-yard map whose two overlapping areas each hold a point; a place's town is the area
-- whose rectangle holds it, the nearest centre when two do, and the map itself when none does.
local plain = harness.load()
local Towns, bundled = plain.ns.QuestieTowns, plain.ns.Data
local data = {
	maps = { [1] = { continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
	towns = {
		[1] = {
			{ area = 7, x0 = 0.0, y0 = 0.0, x1 = 0.5, y1 = 0.5, cx = 0.25, cy = 0.25 },
			{ area = 9, x0 = 0.2, y0 = 0.2, x1 = 0.9, y1 = 0.9, cx = 0.55, cy = 0.55 },
		},
	},
	areaNames = { [7] = "Near area", [9] = "Far area" },
}
local function At(x, y)
	return { map = 1, x = x, y = y }
end
local village = { At(0.10, 0.10), At(0.15, 0.10), At(0.22, 0.10) }
local overlap, nine, gap, repeated = At(0.30, 0.30), At(0.60, 0.60), At(0.95, 0.60), At(0.10, 0.10)
local unplaced = { map = 2, x = 0.5, y = 0.5 }
local places = { overlap, unplaced, nine, gap, village[3], village[1], repeated, village[2] }
local hubs = Towns.Build(data, places, noop)
equal(village[1].hub, "1:7", "a place takes the area that holds it")
equal(village[2].hub, "1:7", "every place in one area shares its hub")
equal(village[3].hub, "1:7", "a string of places still takes the one area holding each")
equal(overlap.hub, "1:7", "the nearest centre wins where two rectangles hold the point")
equal(nine.hub, "1:9", "a place in the other area is another town")
equal(gap.hub, "1:0", "a place in no area belongs to its map")
equal(repeated.hub, "1:7", "the same place twice is one town")
equal(unplaced.hub, nil, "a place on a map the data does not place has no town")
equal(hubs["1:7"].name, "Near area", "a hub is named for its area")
equal(hubs["1:9"].name, "Far area", "the other area names its own town")
equal(hubs["1:0"].name ~= "", true, "a map-level town is named by its map")
equal(Towns.Hub(data, At(0.10, 0.10)), "1:7", "an NPC in a quest place's area joins its town")
equal(Towns.Hub(data, At(0.40, 0.40)) ~= nil, true, "an NPC is in an area wherever it stands")
equal(Towns.Hub(data, unplaced), nil, "an NPC on an unplaced map has no town")
-- The hubs are a pure function of the map and area IDs, not the order the places arrive in.
local again = { gap, nine, village[1] }
Towns.Build(data, again, noop)
local swapped = { village[1], nine, gap }
Towns.Build(data, swapped, noop)
equal(again[1].hub, swapped[3].hub, "hub keys do not depend on the order of the places")
equal(again[2].hub, swapped[2].hub, "hub keys do not depend on the order of the places, second town")

-- The shipped data carries the overlay areas a town is, and nothing a quest place could answer.
equal(bundled.townAnchors, nil, "no town anchors are bundled")
local areas = 0
for ui_map, found in pairs(bundled.towns) do
	equal(type(ui_map) == "number", true, "a town's map is a uiMapID")
	for _, area in ipairs(found) do
		equal(
			type(area.area) == "number" and area.x0 ~= nil and area.cx ~= nil,
			true,
			"a town area is an AreaTable ID with a rectangle and a centre"
		)
		equal(type(bundled.areaNames[area.area]) == "string", true, "every town area carries its English name")
		areas = areas + 1
	end
end
equal(areas > 0, true, "the world map's areas are bundled")

-- The rule, on the game's own coordinates: one stop the player walks to, never a town a thousand yards away.
---@param map integer
---@param x number
---@param y number
---@return string hub
---@return string name
local function TownAt(map, x, y)
	local hub = plain.ns.Model.Hub(bundled, { map = map, x = x, y = y })
	return hub, Towns.Name(bundled, { map = map, hub = hub })
end
local maestra, maestraName = TownAt(1440, 0.2644, 0.3859)
local astranaar, astranaarName = TownAt(1440, 0.3577, 0.4910)
equal(maestraName, "Maestra's Post", "Maestra's Post is its own town")
equal(astranaarName, "Astranaar", "Astranaar is its own town")
equal(maestra ~= astranaar, true, "Maestra's Post is not Astranaar")
local farm, farmName = TownAt(1431, 0.4512, 0.6703)
local hill, hillName = TownAt(1431, 0.1838, 0.5637)
equal(farmName, "The Yorgen Farmstead", "the Duskwood giver at 0.4512, 0.6703 names its farm")
equal(hillName, "Raven Hill", "the Duskwood giver at 0.1838, 0.5637 names Raven Hill")
equal(farm ~= hill, true, "the two Duskwood givers are different towns")
local _, cragName = TownAt(1442, 0.7187, 0.6000)
equal(cragName, "Windshear Crag", "the Windshear Crag goblins name their crag")
equal(cragName ~= "Sun Rock Retreat", true, "the Windshear Crag goblins are not Sun Rock Retreat")
equal((select(2, TownAt(1429, 0.42, 0.65))), "Goldshire", "Goldshire names itself, not Stormwind")
equal((select(2, TownAt(1411, 0.5, 0.5))), "Razor Hill", "Razor Hill names itself, not Orgrimmar")
equal((select(2, TownAt(1454, 0.5, 0.5))), "Orgrimmar", "a city map is named by its map")
equal((select(2, TownAt(1453, 0.5, 0.5))), "Stormwind City", "a whole city is the one map-level town")
equal(bundled.areaNames[413], "Maestra's Post", "the bundled English name is the harness fallback")

-- A service NPC's place, side and inn are QuestieDB's; what a trainer teaches is the bundled role.
local trainer = next(bundled.roles)
local fake = {
	quests = {
		[900001] = {
			name = "Town quest",
			questLevel = 10,
			requiredLevel = 8,
			startedBy = { { 900100 } },
			finishedBy = { { 900100 } },
			zoneOrSort = 12,
		},
	},
	npcs = {
		[900100] = { name = "Giver", spawns = { [12] = { { 43, 65 } } }, zoneID = 12 },
		[900101] = {
			name = "Keeper",
			spawns = { [12] = { { 43.5, 65.5 } }, [40] = { { 10, 10 } } },
			zoneID = 12,
			npcFlags = 135,
			friendlyToFaction = "A",
		},
		[900102] = { name = "Trader", spawns = { [12] = { { 43, 66 } } }, npcFlags = 4, friendlyToFaction = "AH" },
		[900103] = { name = "No side", spawns = { [12] = { { 43, 66 } } }, npcFlags = 128 },
		[900104] = { name = "Nowhere", spawns = {}, npcFlags = 128, friendlyToFaction = "H" },
		[trainer] = { name = "Teacher", spawns = { [40] = { { 50, 50 } } }, npcFlags = 16, friendlyToFaction = "H" },
	},
	objects = {},
	zones = { area = { [12] = 1429, [40] = 1436 } },
}
local h = harness.load({ questiedb = fake, setup = Ready })
equal(#h.errors, 0, "build errors")
equal(h.ns.QuestieStatus.state, "questie", "catalogue ready")
local built = h.ns.Data
local hub = built.quests[900001].start.hub
equal(hub ~= nil, true, "a quest giver's place is a town")
local keeper = built.npcs[900101]
equal(keeper.inn, true, "QuestieDB's flag makes an innkeeper")
equal(keeper.side, 1, "QuestieDB's friendly side")
equal(keeper.place.map, 1429, "an NPC stands on its usual map")
equal(keeper.place.name, "Keeper", "an NPC's place carries its name")
equal(keeper.place.hub, hub, "an innkeeper beside a giver is in the giver's town")
equal(built.npcs[900102], nil, "a plain vendor is no service NPC")
equal(built.npcs[900103], nil, "an NPC with no side is left out")
equal(built.npcs[900104], nil, "an NPC with no spawn is left out")
local teacher = built.npcs[trainer]
equal(teacher.side, 2, "a trainer's side is QuestieDB's")
equal(teacher.place.map, 1436, "a trainer's place is QuestieDB's")
equal(teacher.place.hub ~= nil, true, "a trainer far from every giver still has a town")
for key, value in pairs(bundled.roles[trainer]) do
	equal(teacher[key], value, "a trainer keeps its bundled role: " .. key)
end

-- Before the build, and without QuestieDB, the guide has no towns or service NPCs and says what to install.
local absent = harness.load({ questiedb = false })
equal(absent.ns.Data.npcs, nil, "no service NPCs without QuestieDB")
equal(next(absent.ns.Data.hubs), nil, "no towns without QuestieDB")
equal(absent.ns.QuestieStatus.reason, absent.ns.L.QUESTIE_ABSENT, "the line says what to install")
equal(#absent.errors, 0, "no errors without QuestieDB")

-- A QuestieDB that says what the generated corpus says composes the towns the generator placed.
local corpus = harness.data()
local mirrored = harness.load({ questiedb = harness.questieMirror(corpus), setup = Ready })
local runtime = mirrored.ns.Data
local compared = 0
for id, quest in pairs(corpus.quests) do
	for _, key in ipairs({ "start", "finish" }) do
		local place = quest[key]
		if place and place.hub then
			compared = compared + 1
			equal(runtime.quests[id][key].hub, place.hub, ("quest %d %s town"):format(id, key))
		end
	end
end
equal(compared > 5000, true, "the corpus places thousands of starts and finishes")
for id, town in pairs(corpus.hubs) do
	equal(runtime.hubs[id] and runtime.hubs[id].name, town.name, "town name " .. id)
end
for id, town in pairs(runtime.hubs) do
	equal(corpus.hubs[id] and corpus.hubs[id].name, town.name, "no extra town name " .. id)
end
for id, npc in pairs(corpus.npcs) do
	local other = runtime.npcs[id]
	equal(other ~= nil, true, "service NPC " .. id)
	equal(other.side, npc.side, "service NPC side " .. id)
	equal(other.inn, npc.inn, "service NPC inn " .. id)
	equal(other.place.map, npc.place.map, "service NPC map " .. id)
end
equal(#mirrored.errors, 0, "mirror errors")
print(("towns_spec: %d checks passed"):format(checks))
