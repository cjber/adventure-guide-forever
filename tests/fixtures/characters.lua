-- Fixed characters for the golden routes (docs/plan.md §1.5). Each is plain data: level, side (1 Alliance,
-- 2 Horde), race and class bits as State.lua builds them (1 << (ID - 1)), a map position, completed quests as
-- rules plus explicit IDs, a quest log and prefs. `Resolve` turns one into the planner's arguments.
local characters = {}

characters.list = {
	{
		-- A night elf hunter who finished Teldrassil and Darkshore, standing in Auberdine.
		name = "ne21_darkshore",
		level = 21,
		side = 1,
		raceBit = 8,
		classBit = 4,
		map = 1439,
		x = 0.3700,
		y = 0.4400,
		completed = { zones = { 1438, 1439 } },
	},
	{
		-- The same two levels later, when the next zone matters (the next-zone card is offered at level + 2).
		name = "ne23_darkshore",
		level = 23,
		side = 1,
		raceBit = 8,
		classBit = 4,
		map = 1439,
		x = 0.3700,
		y = 0.4400,
		completed = { zones = { 1438, 1439 } },
	},
	{
		-- ne21_darkshore carrying finished quests with turn-ins on three kinds of map: Darkshore (947, 948), the next
		-- zone over (967, Ashenvale) and another continent (168, Stormwind). The log gives no waypoint, so each
		-- turn-in is the data's `finish`.
		name = "ne21_crosszone",
		level = 21,
		side = 1,
		raceBit = 8,
		classBit = 4,
		map = 1439,
		x = 0.3700,
		y = 0.4400,
		completed = { zones = { 1438, 1439 } },
		log = {
			{ id = 947, title = "Cave Mushrooms", level = 17, complete = true },
			{ id = 948, title = "Onu", level = 17, complete = true },
			{ id = 967, title = "The Tower of Althalaxx", level = 18, complete = true },
			{ id = 168, title = "Collecting Memories", level = 18, complete = true },
		},
	},
	{
		-- A human warrior in Goldshire who finished Elwynn Forest.
		name = "human12_elwynn",
		level = 12,
		side = 1,
		raceBit = 1,
		classBit = 1,
		map = 1429,
		x = 0.4200,
		y = 0.6500,
		completed = { zones = { 1429 } },
	},
	{
		-- The probe's level-18 orc shaman at the Crossroads, as ui_spec loads it: one hand-in, one quest under way.
		name = "orc18_barrens",
		level = 18,
		side = 2,
		raceBit = 2,
		classBit = 64,
		map = 1413,
		x = 0.5200,
		y = 0.3000,
		completed = { ids = { 844 } },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
		},
	},
	{
		-- A level-60 human warrior at Light's Hope Chapel with nothing completed: the end-game zones only.
		name = "human60",
		level = 60,
		side = 1,
		raceBit = 1,
		classBit = 1,
		map = 1423,
		x = 0.8100,
		y = 0.5800,
		completed = {},
	},
}

-- Completion rules: `zones` completes every quest of the character's side filed under those uiMapIDs, `below`
-- every quest of the side with a level below it, and `ids` exactly those quests.
local function Completed(data, fixture)
	local rules, completed = fixture.completed or {}, {}
	local zones = {}
	for _, map in ipairs(rules.zones or {}) do
		zones[map] = true
	end
	for id, quest in pairs(data.quests) do
		if quest.side == 3 or quest.side == fixture.side then
			if
				(quest.zone and zones[quest.zone]) or (rules.below and quest.level > 0 and quest.level < rules.below)
			then
				completed[id] = true
			end
		end
	end
	for _, id in ipairs(rules.ids or {}) do
		completed[id] = true
	end
	-- A quest in the log is not completed, whatever the rules above say.
	for _, entry in ipairs(fixture.log or {}) do
		completed[entry.id] = nil
	end
	return completed
end

function characters.Resolve(data, fixture)
	local player = {
		level = fixture.level,
		maxLevel = 60, -- WoW: Forever's cap, as GetMaxPlayerLevel() gives it
		side = fixture.side,
		raceBit = fixture.raceBit,
		classBit = fixture.classBit,
		map = fixture.map,
		x = fixture.x,
		y = fixture.y,
	}
	local log = {}
	for _, entry in ipairs(fixture.log or {}) do
		log[entry.id] = {
			id = entry.id,
			title = entry.title,
			level = entry.level,
			complete = entry.complete,
			map = entry.map,
			x = entry.x,
			y = entry.y,
		}
	end
	local prefs = { quests = true, dungeons = false, skipped = {} }
	for key, value in pairs(fixture.prefs or {}) do
		prefs[key] = value
	end
	return player, Completed(data, fixture), log, prefs
end

return characters
