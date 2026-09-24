-- Run from the repository root: luajit tests/npcs_spec.lua
-- Data.npcs (tools/gen_quests.py `roles`): known NPCs by ID, and the shape every entry keeps.
local ns = {}
assert(loadfile("Data/Quests.lua"))("AdventureGuideForever", ns)
local npcs, maps, checks = ns.Data.npcs, ns.Data.maps, 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Each case: an NPC ID, its fields, and the uiMapID it stands on.
for _, case in ipairs({
	{ 5497, { class = 8, upto = 60, side = 1 }, 1453, "Jennea Cannon" }, -- Stormwind mage trainer
	{ 198, { class = 8, upto = 6, side = 1 }, 1429, "Khelden Bremen" }, -- Northshire's: novice spells only
	{ 6929, { inn = true, side = 2 }, 1454, "Innkeeper Gryshka" }, -- Orgrimmar
	{ 295, { inn = true, side = 1 }, 1429, "Innkeeper Farley" }, -- Goldshire
	{ 347, { bg = 1, side = 2 }, 1458, "Grizzle Halfmane" }, -- Alterac Valley battlemaster
	{ 5499, { skill = 171, rank = 2, side = 1 }, 1453, "Lilyssia Nightbreeze" }, -- Stormwind alchemy, to Journeyman
	{ 543, { pet = true, side = 1 }, 1448, "Nalesette Wildbringer" }, -- Felwood, not the Mount Hyjal map over it
	{ 4732, { riding = true, race = 1, side = 1 }, 1429, "Randal Hunter" }, -- Eastvale horse riding
}) do
	local id, fields, map, name = case[1], case[2], case[3], case[4]
	local npc = npcs[id]
	assert(npc, "NPC " .. id .. " missing")
	for key, value in pairs(fields) do
		equal(npc[key], value, id .. " " .. key)
	end
	equal(npc.place.map, map, id .. " map")
	equal(npc.place.name, name, id .. " name")
end
equal(npcs[6929].place.hub ~= nil, true, "Gryshka stands in an Orgrimmar hub")
equal(npcs[5497].place.hub, npcs[5499].place.hub, "Stormwind's Mage Quarter trainers share a hub")

local ROLES = { "class", "pet", "riding", "skill", "bg", "inn" }
local count = 0
for id, npc in pairs(npcs) do
	count = count + 1
	local roles = 0
	for _, role in ipairs(ROLES) do
		roles = roles + (npc[role] and 1 or 0)
	end
	equal(roles > 0, true, id .. " has a role")
	equal(npc.side >= 1 and npc.side <= 3, true, id .. " side")
	equal(npc.skill == nil, npc.rank == nil, id .. " skill and rank together")
	equal(npc.class == nil, npc.upto == nil, id .. " class and upto together")
	equal(npc.rank == nil or (npc.rank >= 1 and npc.rank <= 4), true, id .. " rank")
	local place = npc.place
	equal(maps[place.map] ~= nil, true, id .. " map has a centre")
	equal(place.x >= 0 and place.x <= 1 and place.y >= 0 and place.y <= 1, true, id .. " coordinates")
end
equal(count > 400, true, "NPC count")

print(("npcs_spec: %d checks passed; %d NPCs"):format(checks, count))
