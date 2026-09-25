-- Run from the repository root: luajit tests/playthrough_spec.lua
-- Every race and class Classic allows plays levels 1 to 60 on the planner's own advice (design §5.2): at each level
-- it takes card 1's route, one lap a level, picking up, finishing objectives and handing in finished quests as the
-- steps say, then levels up and drops what went grey. Four things a player should never see fail it: an empty guide
-- while quests they can take exist, an orange or red pickup, a story that flips back to a zone it left (A, B, A),
-- a step on a point the data does not have, and fewer than two zone cards (the story and the zones to head to) while
-- the data has two zones with enough for them (design §2.2). It reports the quests handed in and the yards walked a
-- level.
-- A second pass plays a scripted chooser (design §2.18): always card 2 when there is one, and "Not this quest" on every
-- tenth quest by ID; a step that holds a dropped quest fails it too.
-- AGF_PLAYTHROUGH_TRACE="Human class 1" prints that character's card 1 each round.
local ns = {}
assert(loadfile("Data/Quests.lua"))("AdventureGuideForever", ns)
-- Locales/enUS.lua for ns.L, the planner's copy, then Core.lua with its load-time hooks into the client stubbed.
assert(loadfile("Locales/enUS.lua"))("AdventureGuideForever", ns)
local core = assert(loadfile("Core.lua"))
setfenv(
	core,
	setmetatable({
		EventUtil = { ContinueOnAddOnLoaded = function() end },
		SlashCmdList = {},
		CreateFrame = function()
			return { SetScript = function() end }
		end,
	}, { __index = _G })
)
core("AdventureGuideForever", ns)
assert(loadfile("Model.lua"))("AdventureGuideForever", ns)
local Model, data = ns.Model, ns.Data
local trace = os.getenv("AGF_PLAYTHROUGH_TRACE")

-- Classic's races (ID, side, where level 1 stands) and the classes each may be (class IDs).
local RACES = {
	{ "Human", 1, 1, { 1429, 0.48, 0.42 }, { 1, 2, 4, 5, 8, 9 } },
	{ "Orc", 2, 2, { 1411, 0.52, 0.68 }, { 1, 3, 4, 7, 9 } },
	{ "Dwarf", 3, 1, { 1426, 0.29, 0.71 }, { 1, 2, 3, 4, 5 } },
	{ "Night Elf", 4, 1, { 1438, 0.58, 0.44 }, { 1, 3, 4, 5, 11 } },
	{ "Undead", 5, 2, { 1420, 0.30, 0.71 }, { 1, 4, 5, 8, 9 } },
	{ "Tauren", 6, 2, { 1412, 0.44, 0.77 }, { 1, 3, 7, 11 } },
	{ "Gnome", 7, 1, { 1426, 0.29, 0.71 }, { 1, 4, 8, 9 } },
	{ "Troll", 8, 2, { 1411, 0.52, 0.68 }, { 1, 3, 4, 5, 7, 8 } },
}
-- A round is card 1's whole route, a lap (town, its areas, back): one a level, since a lap does a level's quests.
local LOG_SIZE, ROUNDS, ORANGE, RED = 20, 1, 3, 5

-- The data's places, keyed to 4 places: a step's point must be one of them.
local places = {}
local function Key(map, x, y)
	return ("%d:%.4f:%.4f"):format(map or 0, x or -1, y or -1)
end
local function Add(place)
	if place and place.map then
		places[Key(place.map, place.x, place.y)] = true
	end
end
for _, quest in pairs(data.quests) do
	Add(quest.start)
	Add(quest.finish)
	for _, area in ipairs(quest.obj or {}) do
		places[Key(area[5] or quest.zone, area[2] / 1000, area[3] / 1000)] = true
	end
end
for _, npc in pairs(data.npcs or {}) do
	Add(npc.place)
end

-- A step's point is a place the data has, or, for an area, where the player enters it: inside the ring of one of its
-- shapes, each centred on a place the data has, with the ring's middle one too (Model.lua Enter).
local function Placed(step)
	if places[Key(step.map, step.x, step.y)] then
		return true
	end
	local ring = step.ring
	if not (ring and places[Key(ring.map, ring.x, ring.y)]) then
		return false
	end
	for _, shape in ipairs(step.shapes or {}) do
		local yards = Model.Yards(data, step, shape)
		if places[Key(shape.map, shape.x, shape.y)] and yards and yards <= shape.r then
			return true
		end
	end
	return false
end

local flags = { empty = {}, orange = {}, red = {}, flip = {}, unplaced = {}, dropped = {}, zones = {} }
local function Flag(kind, text)
	local list = flags[kind]
	list[#list + 1] = text
end

-- The chooser's "Not this quest": every tenth quest by ID, the same on every character.
local notInterested = {}
for id, quest in pairs(data.quests) do
	if id % 10 == 0 then
		notInterested["quest:" .. id] = { title = quest.title }
	end
end

-- Quests the character could take now and would be offered: open, not grey, not orange, not an instance's and not
-- dropped.
local function Doable(player, completed, log, prefs)
	for id, quest in pairs(data.quests) do
		if
			not (prefs.notInterested and prefs.notInterested["quest:" .. id])
			and not quest.dungeon
			and not quest.raid
			and not completed[id]
			and not log[id]
			and quest.level - player.level < ORANGE
			and not Model.IsGray(quest.level, player.level)
			and Model.Eligible(data, player, completed, log, id)
		then
			return true
		end
	end
	return false
end

-- The zones the data has enough in for a zone card: five quests the character can take now (as Doable, and no outdoor
-- elite, which never picks a zone) that are still not grey two levels on, in a zone whose range they haven't outgrown.
-- None with a full log: nothing can be picked up, so a card of pickups has no step.
local function ZonesWithEnough(player, completed, log, held)
	if held >= LOG_SIZE then
		return 0
	end
	local counts, zones, ahead = {}, 0, math.min(player.level + 2, player.maxLevel)
	for id, quest in pairs(data.quests) do
		local map = quest.zone or (quest.start and quest.start.map)
		local zone = map and data.zones[map]
		if
			zone
			and player.level <= zone.max
			and quest.min <= player.level
			and quest.level - player.level < ORANGE
			and not Model.IsGray(quest.level, ahead)
			and not quest.elite
			and not quest.dungeon
			and not quest.raid
			and not completed[id]
			and not log[id]
			and Model.Eligible(data, player, completed, log, id)
		then
			counts[map] = (counts[map] or 0) + 1
			zones = zones + (counts[map] == 5 and 1 or 0)
		end
	end
	return zones
end

local function Finished(log, id)
	local quest, entry = data.quests[id], log[id]
	entry.complete = true
	if quest and quest.finish then
		-- The live client gives a finished quest's turn-in waypoint.
		entry.map, entry.x, entry.y = quest.finish.map, quest.finish.x, quest.finish.y
	end
end

local plans, started, characters = 0, os.clock(), 0
-- Each pass's quests handed in and yards walked: card 1's, and the chooser's.
local played = { handed = 0, lowest = math.huge, walked = 0 }
local chosen = { handed = 0, lowest = math.huge, walked = 0 }
-- One character's levels 1 to 60; `chooser` plays card 2 and drops every tenth quest.
local function Play(race, classID, chooser)
	local name, raceID, side, at = race[1], race[2], race[3], race[4]
	local label = ("%s class %d%s"):format(name, classID, chooser and ", chooser" or "")
	local player = {
		level = 1,
		maxLevel = 60,
		side = side,
		raceBit = 2 ^ (raceID - 1),
		classBit = 2 ^ (classID - 1),
		map = at[1],
		x = at[2],
		y = at[3],
		logMax = LOG_SIZE,
	}
	local completed, log, held, stories, last = {}, {}, 0, {}, nil
	local prefs = { quests = true, dungeons = false, skipped = {} }
	if chooser then
		prefs.notInterested = notInterested
	end
	characters = characters + (chooser and 0 or 1)
	for level = 1, 60 do
		player.level = level
		-- What went grey is dropped, as a player would.
		for id, entry in pairs(log) do
			if Model.IsGray(entry.level, level) and not entry.complete then
				log[id], held = nil, held - 1
			end
		end
		for _ = 1, ROUNDS do
			-- Each plan keeps to the last one's committed order, as the addon's rebuilds do.
			local route = Model.Plan(data, player, completed, log, prefs, nil, nil, last)
			plans = plans + 1
			-- The chooser takes card 2 whenever the cards offer one.
			local second = chooser and route.journeys[2]
			if second and route.journey ~= second.key then
				prefs.journey = second.key
				route, plans = Model.Plan(data, player, completed, log, prefs, nil, nil, last), plans + 1
			end
			last = route
			local where = ("%s, level %d"):format(label, level)
			local card = route.journeys[1]
			if trace and label:find(trace, 1, true) then
				print(where, card and card.key, card and #card.steps, held)
			end
			if not card and Doable(player, completed, log, prefs) then
				Flag("empty", where .. " at " .. Key(player.map, player.x, player.y))
			end
			if not chooser then
				local zoneCards = 0
				for _, journey in ipairs(route.journeys) do
					zoneCards = zoneCards + (journey.key:match("^zone:") and 1 or 0)
				end
				local enough = zoneCards < 2 and ZonesWithEnough(player, completed, log, held) or 0
				if enough >= 2 then
					Flag("zones", ("%s: %d zone cards, the data has %d"):format(where, zoneCards, enough))
				end
			end
			for _, journey in ipairs(route.journeys) do
				if not chooser and journey.kind == "story" and journey.key:match("^zone:") and journey == card then
					if stories[#stories] ~= journey.key then
						stories[#stories + 1] = journey.key
						local back = stories[#stories - 2]
						if back == journey.key then
							Flag("flip", ("%s: %s, %s, %s"):format(where, back, stories[#stories - 1], back))
						end
					end
				end
				for _, step in ipairs(journey.steps) do
					for _, id in ipairs(step.quests) do
						if chooser and notInterested["quest:" .. id] then
							Flag("dropped", ("%s: %s holds %d"):format(where, step.key, id))
						end
					end
					if not Placed(step) then
						Flag("unplaced", ("%s: %s %s"):format(where, step.key, Key(step.map, step.x, step.y)))
					end
					for _, id in ipairs(step.pickups or {}) do
						local over = data.quests[id].level - level
						if over >= RED then
							Flag("red", ("%s: %s pickup %d at %d"):format(where, journey.key, id, over + level))
						elseif over >= ORANGE then
							Flag("orange", ("%s: %s pickup %d at %d"):format(where, journey.key, id, over + level))
						end
					end
				end
			end
			-- The route shown, as the steps say: card 1's, or the chooser's card.
			for _, step in ipairs(route.steps) do
				if trace and label:find(trace, 1, true) then
					print("", step.key, step.map, step.x, step.y, table.concat(step.quests, ","))
				end
				for _, id in ipairs(step.handins or {}) do
					if log[id] and log[id].complete then
						log[id], completed[id], held = nil, true, held - 1
					end
				end
				for _, id in ipairs(step.pickups or {}) do
					if held < LOG_SIZE and not log[id] then
						local quest = data.quests[id]
						log[id], held =
							{ id = id, title = quest.title, level = quest.level, complete = false }, held + 1
						if not next(quest.need or {}) then
							Finished(log, id)
						end
					end
				end
				if step.kind == "area" or step.kind == "dungeon" then
					for _, id in ipairs(step.quests) do
						if log[id] then
							Finished(log, id)
						end
					end
				elseif step.kind == "turnin" then
					for _, id in ipairs(step.quests) do
						if log[id] then
							log[id], completed[id], held = nil, true, held - 1
						end
					end
				end
				local pass = chooser and chosen or played
				pass.walked = pass.walked + (Model.Yards(data, player, step) or 0)
				player.map, player.x, player.y = step.map, step.x, step.y
			end
		end
	end
	local count = 0
	for _ in pairs(completed) do
		count = count + 1
	end
	local pass = chooser and chosen or played
	pass.handed, pass.lowest = pass.handed + count, math.min(pass.lowest, count)
end

for _, chooser in ipairs({ false, true }) do
	for _, race in ipairs(RACES) do
		for _, classID in ipairs(race[5]) do
			Play(race, classID, chooser)
		end
	end
end

local total = 0
for _, kind in ipairs({ "empty", "orange", "red", "flip", "unplaced", "dropped", "zones" }) do
	local list = flags[kind]
	total = total + #list
	print(("playthrough: %-8s %d"):format(kind, #list))
	for index = 1, math.min(3, #list) do
		print("  " .. list[index])
	end
end
for _, pass in ipairs({ { "", played }, { ", choosing card 2", chosen } }) do
	local stats = pass[2]
	print(
		("playthrough: %d characters%s handed in %d quests each on average, %d at least, walking %d yards a level"):format(
			characters,
			pass[1],
			stats.handed / characters,
			stats.lowest,
			stats.walked / characters / 60
		)
	)
end
print(("playthrough_spec: %d plans in %.1f s; %d flags"):format(plans, os.clock() - started, total))
if total > 0 then
	os.exit(1)
end
