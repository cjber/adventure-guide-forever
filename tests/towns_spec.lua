-- Towns, their names and the NPCs who serve in them come from the QuestieDB build (QuestieTowns.lua,
-- QuestieSource.lua): nothing about where a giver, trainer or innkeeper stands is bundled.
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

-- A synthetic world: one square map of 1000 yards, so a hundredth of the map is 10 yards.
local plain = harness.load()
local Towns, bundled = plain.ns.QuestieTowns, plain.ns.Data
local data = {
	maps = { [1] = { continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
	towns = {
		{ node = 9, continent = 0, x = 380, y = 400, name = "Far node" },
		{ node = 7, continent = 0, x = 395, y = 395, name = "Near node" },
		{ node = 3, continent = 1, x = 395, y = 395, name = "Another continent" },
	},
}
local function At(x, y)
	return { map = 1, x = x, y = y }
end
local village = { At(0.10, 0.10), At(0.15, 0.10), At(0.22, 0.10) }
local farm, repeated = At(0.60, 0.60), At(0.10, 0.10)
local unplaced = { map = 2, x = 0.5, y = 0.5 }
-- A street of places 90 yards apart: one chain at the town link, wider than the cap, so it is cut at a shorter link.
local street = {}
for index = 0, 6 do
	street[#street + 1] = At(0.05 + index * 0.09, 0.90)
end
local places = { farm, unplaced, village[3], village[1], repeated, village[2] }
for _, place in ipairs(street) do
	places[#places + 1] = place
end
local hubs, grid = Towns.Build(data, places, noop)
equal(village[1].hub ~= nil, true, "a place on a placed map stands in a town")
equal(village[2].hub, village[1].hub, "places within the link share a town")
equal(village[3].hub, village[1].hub, "a chain of short steps is one town")
equal(repeated.hub, village[1].hub, "the same place twice is one town")
equal(farm.hub ~= village[1].hub, true, "a place beyond the link is another town")
equal(unplaced.hub, nil, "a place on a map the data does not place has no town")
local cut = {}
for _, place in ipairs(street) do
	cut[place.hub] = true
end
equal(next(cut, next(cut)) ~= nil, true, "a town wider than the cap is cut again")
equal(hubs[village[1].hub].name, "Near node", "a town takes the nearest flight-map node's name")
equal(hubs[farm.hub], nil, "a town with no node in reach has no name")
equal(Towns.Hub(data, grid, At(0.12, 0.13)), village[1].hub, "an NPC near a quest place joins its town")
equal(Towns.Hub(data, grid, At(0.40, 0.30)), nil, "an NPC far from every quest place has no town")
equal(Towns.Hub(data, grid, unplaced), nil, "an NPC on an unplaced map has no town")
-- The numbering is the catalogue's, not the order the places arrive in.
local again = { At(0.60, 0.60), At(0.10, 0.10) }
Towns.Build(data, again, noop)
local swapped = { At(0.10, 0.10), At(0.60, 0.60) }
Towns.Build(data, swapped, noop)
equal(again[1].hub, swapped[2].hub, "hub numbers do not depend on the order of the places")
equal(again[2].hub, swapped[1].hub, "hub numbers do not depend on the order of the places, second town")

-- The shipped data carries what QuestieDB cannot answer and nothing it can.
equal(bundled.townAnchors, nil, "no town anchors are bundled")
for id, role in pairs(bundled.roles) do
	equal(
		role.place == nil and role.side == nil and role.inn == nil,
		true,
		"a bundled role has no place, side or inn: " .. id
	)
end
for _, node in ipairs(bundled.towns) do
	equal(
		type(node.name) == "string" and node.x ~= nil and node.continent ~= nil,
		true,
		"a flight-map node is named and placed"
	)
end

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
equal(teacher.place.hub, nil, "a trainer far from every giver has no town")
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
