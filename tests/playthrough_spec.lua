-- Run from the repository root: luajit tests/playthrough_spec.lua
-- Every race and class Classic allows plays levels 1 to 60 on the planner's own advice (design §5.2): at each level
-- it takes card 1's route, picking up, finishing objectives and handing in as the steps say, then levels up and
-- drops what went grey. Four things a player should never see are flagged: an empty guide while quests they can
-- take exist, an orange or red pickup, a story that flips back to a zone it left (A, B, A), and a step on a point
-- the data does not have. It reports the counts and passes; AGF_PLAYTHROUGH_STRICT=1 fails on any flag, which the
-- auto-picking planner (PR 4) is to meet. AGF_PLAYTHROUGH_TRACE="Human class 1" prints that character's card 1
-- each round.
local ns = {}
assert(loadfile("Data/Quests.lua"))("AdventureGuideForever", ns)
-- Core.lua for ns.L, the planner's copy; its load-time hooks into the client are stubbed, since only the copy is read.
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
local strict, trace = os.getenv("AGF_PLAYTHROUGH_STRICT") == "1", os.getenv("AGF_PLAYTHROUGH_TRACE")

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
local LOG_SIZE, ROUNDS, ORANGE, RED = 20, 2, 3, 5

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

local flags = { empty = {}, orange = {}, red = {}, flip = {}, unplaced = {} }
local function Flag(kind, text)
	local list = flags[kind]
	list[#list + 1] = text
end

-- Quests the character could take now and would be offered: open, not grey, not orange, and not an instance's.
local function Doable(player, completed, log)
	for id, quest in pairs(data.quests) do
		if
			not quest.dungeon
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

local function Finished(log, id)
	local quest, entry = data.quests[id], log[id]
	entry.complete = true
	if quest and quest.finish then
		-- The live client gives a finished quest's turn-in waypoint.
		entry.map, entry.x, entry.y = quest.finish.map, quest.finish.x, quest.finish.y
	end
end

local plans, started, characters, handed, lowest = 0, os.clock(), 0, 0, math.huge
for _, race in ipairs(RACES) do
	local name, raceID, side, at, classes = race[1], race[2], race[3], race[4], race[5]
	for _, classID in ipairs(classes) do
		local label = ("%s class %d"):format(name, classID)
		local player = {
			level = 1,
			maxLevel = 60,
			side = side,
			raceBit = 2 ^ (raceID - 1),
			classBit = 2 ^ (classID - 1),
			map = at[1],
			x = at[2],
			y = at[3],
		}
		local completed, log, held, stories = {}, {}, 0, {}
		characters = characters + 1
		for level = 1, 60 do
			player.level = level
			-- What went grey is dropped, as a player would.
			for id, entry in pairs(log) do
				if Model.IsGray(entry.level, level) and not entry.complete then
					log[id], held = nil, held - 1
				end
			end
			for _ = 1, ROUNDS do
				local route =
					Model.Plan(data, player, completed, log, { quests = true, dungeons = false, skipped = {} })
				plans = plans + 1
				local where = ("%s, level %d"):format(label, level)
				local card = route.journeys[1]
				if trace and label:find(trace, 1, true) then
					print(where, card and card.key, card and #card.steps, held)
				end
				if not card and Doable(player, completed, log) then
					Flag("empty", where .. " at " .. Key(player.map, player.x, player.y))
				end
				for _, journey in ipairs(route.journeys) do
					if journey.kind == "story" and journey.key:match("^zone:") and journey == card then
						if stories[#stories] ~= journey.key then
							stories[#stories + 1] = journey.key
							local back = stories[#stories - 2]
							if back == journey.key then
								Flag("flip", ("%s: %s, %s, %s"):format(where, back, stories[#stories - 1], back))
							end
						end
					end
					for _, step in ipairs(journey.steps) do
						if not places[Key(step.map, step.x, step.y)] then
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
				-- Card 1's route, as the steps say.
				for _, step in ipairs(card and card.steps or {}) do
					for _, id in ipairs(step.handins or {}) do
						if log[id] then
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
					player.map, player.x, player.y = step.map, step.x, step.y
				end
			end
		end
		local count = 0
		for _ in pairs(completed) do
			count = count + 1
		end
		handed, lowest = handed + count, math.min(lowest, count)
	end
end

local total = 0
for _, kind in ipairs({ "empty", "orange", "red", "flip", "unplaced" }) do
	local list = flags[kind]
	total = total + #list
	print(("playthrough: %-8s %d"):format(kind, #list))
	for index = 1, math.min(3, #list) do
		print("  " .. list[index])
	end
end
print(
	("playthrough: %d characters handed in %d quests each on average, %d at least"):format(
		characters,
		handed / characters,
		lowest
	)
)
print(
	("playthrough_spec: %d plans in %.1f s; %d flags%s"):format(
		plans,
		os.clock() - started,
		total,
		strict and "" or " (expected until PR 4; AGF_PLAYTHROUGH_STRICT=1 fails on them)"
	)
)
if strict and total > 0 then
	os.exit(1)
end
