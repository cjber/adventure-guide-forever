-- Run from the repository root: luajit tests/profession_spec.lua
-- The profession aside (roadmap #9, Hints/Profession.lua, docs/design.md §2.15) through tests/harness.lua: which nudge
-- (Model.Profession), the nearest trainer of the right rank, the line's text, Skip moving on, and SKILL_LINES_CHANGED.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function clean(h, label)
	equal(#h.errors, 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
end

-- A skill line the character has: a profession unless `category` says 9, a secondary skill.
local function Line(id, rank, cap, category)
	return { skillID = id, name = "Line " .. id, rank = rank, maxRank = cap, category = category }
end

local MINING, BLACKSMITHING, HERBALISM, SKINNING = 186, 164, 182, 393
local FIRST_AID, COOKING, FISHING = 129, 185, 356
local SECONDARY = 9

-- The harness's level-18 orc shaman in The Barrens, with these lines and player fields; step 1's frame settled.
local function Load(skills, player)
	local h = harness.load({ skills = skills, player = player })
	h.ns.Invalidate()
	h.flush()
	return h
end

-- Every lines but those given: two professions and the secondary skills, none at a cap.
local function Settled(...)
	local skills = {
		Line(HERBALISM, 1, 75),
		Line(SKINNING, 1, 75),
		Line(FIRST_AID, 1, 75, SECONDARY),
		Line(COOKING, 1, 75, SECONDARY),
		Line(FISHING, 1, 75, SECONDARY),
	}
	for _, line in ipairs({ ... }) do
		for index, have in ipairs(skills) do
			if have.skillID == line.skillID then
				table.remove(skills, index)
				break
			end
		end
		skills[#skills + 1] = line
	end
	return skills
end

-- The nudge Model.Profession gives for the harness's player now.
local function Nudge(h, wanted)
	return h.ns.Model.Profession(h.ns.Data, h.ns.State.Player(), wanted)
end

local function Teaches(npc, skill, rank)
	for _, taught in ipairs(npc.ranks or {}) do
		if npc.skill == skill and taught == rank then
			return true
		end
	end
	return false
end

-- The nudge's trainer teaches its rank to the player's side, and none who does is nearer (one continent: yards).
local function Nearest(h, nudge, label)
	local data, player = h.ns.Data, h.ns.State.Player()
	local npc = nudge.npc
	equal(npc ~= nil, true, label .. ": a trainer")
	local lines = nudge.skills or { nudge.skill }
	local function Fits(candidate)
		for _, skill in ipairs(lines) do
			if Teaches(candidate, skill, nudge.rank) and math.floor(candidate.side / player.side) % 2 == 1 then
				return true
			end
		end
		return false
	end
	equal(Fits(npc), true, label .. ": teaches the rank to the player's side")
	local far = h.ns.Model.Yards(data, player, npc.place)
	for id, other in pairs(data.npcs) do
		local yards = Fits(other) and h.ns.Model.Yards(data, player, other.place)
		equal(not yards or yards >= far, true, label .. ": none nearer than " .. id)
	end
end

-- The aside the guide shows.
local function Aside(h)
	return h.ns.Asides.Current()
end

-- A learned line at its rank's cap, whose next rank the player can train: the next rank's nearest trainer.
do
	local h = Load(Settled(Line(MINING, 75, 75)))
	local nudge = Nudge(h)
	equal(nudge.key, "profession:186:2", "cap: Journeyman Mining")
	equal(nudge.kind, "cap", "cap: its kind")
	Nearest(h, nudge, "cap")
	local aside = Aside(h)
	local town = h.ns.Model.TownName(h.ns.Data, nudge.npc.place, h.ns.State.MapName)
	equal(aside.text, "Your Line 186 has reached 75 of 75 · Journeyman training in " .. town, "cap: the line")
	equal(aside.icon, "profession", "cap: the minimap's profession trainer mark")
	equal(aside.place, nudge.npc.place, "cap: Go takes the player to that trainer")
	clean(h, "cap")
end

-- No nudge for a line short of its cap, a next rank the player cannot train yet, or one no trainer teaches.
for _, case in ipairs({
	{ "short of the cap", Line(MINING, 74, 75) },
	{ "a cap not on the 75 scale", Line(MINING, 80, 80) },
	{ "Journeyman Blacksmithing asks level 10", Line(BLACKSMITHING, 75, 75), { level = 9 } },
	{ "Expert Cooking comes from a book", Line(COOKING, 150, 150, SECONDARY) },
	{ "Artisan Mining is the last", Line(MINING, 300, 300) },
}) do
	local h = Load(Settled(case[2]), case[3])
	equal(Nudge(h), nil, "no cap: " .. case[1])
	equal(Aside(h), nil, "no cap: " .. case[1] .. ", no aside")
	clean(h, case[1])
end
do
	local h = Load(Settled(Line(BLACKSMITHING, 75, 75)), { level = 10 })
	equal(Nudge(h).key, "profession:164:2", "cap: Journeyman Blacksmithing at level 10")
end

-- A rank only the other side's trainers teach is no nudge: Artisan Fishing is Katoom the Angler's, a Horde trainer.
do
	local horde = Load(Settled(Line(FISHING, 225, 225, SECONDARY)), { level = 40 })
	equal(Nudge(horde).key, "profession:356:4", "side: Artisan Fishing for the Horde")
	local alliance = Load(
		Settled(Line(FISHING, 225, 225, SECONDARY)),
		{ level = 40, faction = "Alliance", raceID = 1, classID = 1, map = 1453, x = 0.5, y = 0.5 }
	)
	equal(Nudge(alliance), nil, "side: none for the Alliance")
	clean(alliance, "side")
end

-- A free profession slot: the nearest trainer of any profession the player lacks and can learn now.
do
	local h = Load({ Line(HERBALISM, 1, 75), Line(FIRST_AID, 1, 75, SECONDARY), Line(COOKING, 1, 75, SECONDARY) })
	local function NoFishing(key)
		return key ~= "profession:356:1"
	end
	local nudge = Nudge(h, NoFishing)
	equal(nudge.key, "profession:slot", "slot: one profession of two")
	equal(nudge.npc.skill ~= HERBALISM, true, "slot: never one the player has")
	Nearest(h, nudge, "slot")
	local town = h.ns.Model.TownName(h.ns.Data, nudge.npc.place, h.ns.State.MapName)
	equal(Aside(h).text, "A profession slot is free · trainers in " .. town, "slot: the line")

	-- At level 1 only the gathering professions ask no level.
	local young = Load({ Line(FIRST_AID, 1, 75, SECONDARY) }, { level = 1 })
	nudge = Nudge(young)
	equal(nudge.key, "profession:slot", "slot: at level 1")
	table.sort(nudge.skills)
	equal(table.concat(nudge.skills, ","), "182,186,393", "slot: Herbalism, Mining and Skinning ask no level")

	-- Two professions fill the slots; a client that gives no count gives no slot.
	equal(Nudge(Load(Settled())), nil, "slot: none free")
	local player = h.ns.State.Player()
	player.primaries = nil
	equal(h.ns.Model.Profession(h.ns.Data, player, NoFishing), nil, "slot: no count, no slot")
	clean(h, "slot")
end

-- A secondary skill the player lacks: the nearest trainer of its first rank, once the player has its level.
do
	local skills = Settled()
	table.remove(skills, 5) -- Fishing
	local h = Load(skills, { level = 4 })
	equal(Nudge(h), nil, "learn: Fishing asks level 5")
	h = Load(skills, { level = 5 })
	local nudge = Nudge(h)
	equal(nudge.key, "profession:356:1", "learn: Fishing")
	Nearest(h, nudge, "learn")
	local town = h.ns.Model.TownName(h.ns.Data, nudge.npc.place, h.ns.State.MapName)
	equal(Aside(h).text, "You can learn Fishing in " .. town, "learn: the data's name for a line the player lacks")
	clean(h, "learn")
end

-- The order: a cap, then a free slot, then a secondary skill; Skip for now and Not interested move on to the next.
do
	local h = Load({ Line(MINING, 75, 75), Line(COOKING, 1, 75, SECONDARY), Line(FISHING, 1, 75, SECONDARY) })
	equal(Aside(h).key, "profession:186:2", "order: the cap first")
	h.ns.Asides.Skip("profession:186:2")
	h.flush()
	equal(Aside(h).key, "profession:slot", "order: then the free slot")
	h.ns.Asides.Decline(Aside(h))
	h.flush()
	equal(Aside(h).key, "profession:129:1", "order: then First Aid")
	h.ns.Asides.Skip("profession:129:1")
	h.flush()
	equal(Aside(h), nil, "order: nothing left")
	local again = harness.load({ skills = h.skills, charDB = h.G.AdventureGuideForeverCharDB })
	again.ns.Invalidate()
	again.flush()
	equal(Aside(again).key, "profession:186:2", "order: a skip lasts the session, Not interested stays")
	again.ns.Asides.Skip("profession:186:2")
	again.flush()
	equal(Aside(again).key, "profession:129:1", "order: the slot stays turned down")
	clean(h, "order")
end

-- No place for the player (an instance): the line without a town, and no Go.
do
	local h = Load(Settled(Line(MINING, 75, 75)), { map = false })
	local aside = Aside(h)
	equal(aside.text, "Your Line 186 has reached 75 of 75 · Journeyman training is open to you", "no place: text only")
	equal(aside.place, nil, "no place: nowhere to go")
	clean(h, "no place")
end

-- SKILL_LINES_CHANGED: a profession line's rank or cap moving asks again, a frame later; a weapon skill-up does not.
do
	local h = Load(Settled(Line(MINING, 74, 75)))
	local asks = 0
	local profession = h.ns.Model.Profession
	h.ns.Model.Profession = function(...)
		asks = asks + 1
		return profession(...) -- multi-value: the wrapper is transparent
	end
	equal(Aside(h), nil, "event: short of the cap")
	h.skills[#h.skills].rank = 75
	h.fire("SKILL_LINES_CHANGED")
	h.flush()
	equal(Aside(h).key, "profession:186:2", "event: at the cap, asked again")
	h.skills[#h.skills].maxRank = 150
	h.fire("SKILL_LINES_CHANGED")
	h.flush()
	equal(Aside(h), nil, "event: Journeyman learned, the line goes")
	asks = 0
	h.skills[#h.skills + 1] = { skillID = 43, name = "Swords", rank = 11, maxRank = 90, category = 6 }
	h.fire("SKILL_LINES_CHANGED")
	h.flush()
	h.skills[#h.skills].rank = 12
	h.fire("SKILL_LINES_CHANGED")
	h.flush()
	equal(asks, 0, "event: a weapon skill-up asks nothing")
	clean(h, "event")
end

print(("profession_spec: %d checks passed"):format(checks))
