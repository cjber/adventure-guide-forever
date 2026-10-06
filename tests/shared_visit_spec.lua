-- Run from the repository root: luajit tests/shared_visit_spec.lua
-- Shared visits (docs/design.md §4.2): quests whose objectives lie near each other are one area visit, titled for all
-- of its objectives, with each quest's own count under its row in the tracker and the map tooltip. Different maps
-- and ordinary against group work never merge; pickups lead the visit and hand-ins follow it.
local harness = dofile("tests/harness.lua")

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local ns = {}
harness.model(ns)
local Model = ns.Model

---@param steps AGFStep[]
local function Keys(steps)
	local keys = {}
	for _, step in ipairs(steps) do
		keys[#keys + 1] = step.key
	end
	return table.concat(keys, " ")
end

---@param steps AGFStep[]
---@param key string
local function Find(steps, key)
	for _, step in ipairs(steps) do
		if step.key == key then
			return step
		end
	end
end

-- Model.ObjectiveText: the client's words, else a count that means something, else nothing.
equal(
	Model.ObjectiveText({ id = 1, text = "Gnoll slain: 3/8", have = 3, need = 8 }),
	"Gnoll slain: 3/8",
	"text: words win"
)
equal(Model.ObjectiveText({ id = 1, text = "Gnoll slain: 3/8" }), "Gnoll slain: 3/8", "text: words with no count")
equal(Model.ObjectiveText({ id = 1, have = 3, need = 8 }), "3/8", "text: else the count")
equal(Model.ObjectiveText({ id = 1, text = "", have = 0, need = 5 }), "0/5", "text: empty words fall to the count")
equal(Model.ObjectiveText({ id = 1, have = 2, need = 0 }), nil, "text: an untallied kind says nothing")
equal(Model.ObjectiveText({ id = 1, need = 8 }), nil, "text: a need alone says nothing")
equal(Model.ObjectiveText({ id = 1, have = 3 }), nil, "text: a count alone says nothing")
equal(Model.ObjectiveText({ id = 1 }), nil, "text: no words and no count")

local player = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.45, y = 0.5 }
local function quest(map)
	map = map or 1
	return {
		title = "Quest",
		level = 18,
		min = 10,
		side = 2,
		zone = map,
		start = { map = map, x = 0.5, y = 0.5, name = "Quest giver", hub = map == 1 and "1:5" or nil },
		finish = { map = map, x = 0.5, y = 0.5, name = "Quest giver", hub = map == 1 and "1:5" or nil },
	}
end
local function prefs(journey)
	return { quests = true, dungeons = true, skipped = {}, optimisedRoute = true, journey = journey }
end

-- Quests 1 and 2 have kills 50 yd apart (one area); 3 is 150 yd off, 4 is a group quest beside 1 and 2, and 5 works the
-- same ground on another continent's map.
local function Fields()
	local fields = {
		quests = { [1] = quest(), [2] = quest(), [3] = quest(), [4] = quest(), [5] = quest(2) },
		zones = {
			[1] = { name = "Zone", min = 10, max = 20 },
			[2] = { name = "Elsewhere", min = 10, max = 20 },
		},
		maps = {
			[1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 },
			[2] = { name = "Elsewhere", continent = 1, cx = 0, cy = 0, sx = 1000, sy = 1000 },
		},
		continents = { [0] = { x = 0, y = 0 }, [1] = { x = 0, y = 0 } },
		hubs = { ["1:5"] = { name = "Lakeshire, Redridge" } },
		towns = { [1] = { { area = 5, x0 = 0.3, y0 = 0.3, x1 = 0.7, y1 = 0.7, cx = 0.5, cy = 0.5 } } },
	}
	local quests = fields.quests
	quests[1].need, quests[1].obj = { [0] = 8 }, { { 0, 200, 800, 30 } }
	quests[2].need, quests[2].obj = { [4] = 5 }, { { 4, 250, 800, 30 } }
	quests[3].need, quests[3].obj = { [0] = 4 }, { { 0, 400, 800, 0 } }
	quests[4].dungeon, quests[4].need, quests[4].obj = 36, { [0] = 6 }, { { 0, 225, 800, 30 } }
	quests[5].need, quests[5].obj = { [0] = 6 }, { { 0, 225, 800, 30 } }
	return fields
end

local kill = { type = "monster", done = false, have = 3, need = 8, text = "Gnoll slain: 3/8" }
local loot = { type = "item", done = false, have = 1, need = 5, text = "" }
local function Log(extra)
	local log = {
		[1] = { id = 1, title = "Gnolls", level = 18, complete = false, objectives = { kill } },
		[2] = { id = 2, title = "Pelts", level = 18, complete = false, objectives = { loot } },
	}
	for id, entry in pairs(extra or {}) do
		log[id] = entry
	end
	return log
end
local done = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }

-- Nearby quests are one visit, titled for every objective in it; each objective keeps its quest and its own count.
do
	local plan = Model.Plan(Fields(), player, done, Log(), prefs())
	local area = Find(plan.steps, "area:1:0")
	equal(Keys(plan.steps), "area:1:0", "merge: two nearby quests are one stop")
	equal(table.concat(area.quests, " "), "1 2", "merge: both quests ride on it")
	equal(#area.objectives, 2, "merge: one objective each")
	equal(area.title, "Complete 2 objectives · Zone", "title: counts every objective, in the zone")
	local first, second = area.objectives[1], area.objectives[2]
	equal(first.id .. " " .. tostring(Model.ObjectiveText(first)), "1 Gnoll slain: 3/8", "objectives: quest 1's words")
	equal(second.id .. " " .. tostring(Model.ObjectiveText(second)), "2 1/5", "objectives: quest 2's count, no words")

	-- A zone-less step names its first quest instead.
	local nameless = Fields()
	nameless.maps[1].name = nil
	local bare = Find(Model.Plan(nameless, player, done, Log(), prefs()).steps, "area:1:0")
	equal(bare and bare.zone, nil, "title: the data names no zone here")
	equal(bare and bare.title, "Complete 2 objectives · Gnolls", "title: the first quest stands in for it")

	-- One objective keeps the single-quest wording.
	local lone = Model.Plan(Fields(), player, done, { [1] = Log()[1] }, prefs())
	equal(Find(lone.steps, "area:1:0").title:find("Complete 2", 1, true), nil, "title: one objective is not 'shared'")
	local two = Fields()
	two.quests[1].need[4] = 5
	two.quests[1].obj[2] = { 4, 225, 800, 30 }
	local sameQuest = Log()[1]
	sameQuest.objectives[2] = loot
	local own = Find(Model.Plan(two, player, done, { [1] = sameQuest }, prefs()).steps, "area:1:0")
	equal(own.title, "Complete 2 objectives · Gnolls", "title: several objectives of one quest keep its name")
end

-- One of the two done: the full replan keeps the other's remaining count, and the step stops being shared.
do
	local fields, log = Fields(), Log()
	local plan = Model.Plan(fields, player, done, log, prefs())
	local original = Find(plan.steps, "area:1:0")
	log[1].objectives = { { type = "monster", done = true, have = 8, need = 8, text = "Gnoll slain: 8/8" } }
	log[2].objectives = { { type = "item", done = false, have = 3, need = 5, text = "" } }
	local refreshed = Model.Refresh(fields, player, done, log, prefs(), plan)
	local remaining = Find(refreshed.journeys[1].steps, "area:1:0")
	equal(table.concat(remaining.quests, " "), "2", "combat: only the unfinished objective stays")
	equal(Model.ObjectiveText(remaining.objectives[1]), "3/5", "combat: remaining progress is live")
	equal(#original.objectives, 2, "combat: prior snapshot is unchanged")
	equal(original.objectives[2].have, 1, "combat: prior count is unchanged")
end

do
	local log = Log({ [1] = { id = 1, title = "Gnolls", level = 18, complete = true } })
	local plan = Model.Plan(Fields(), player, done, log, prefs())
	equal(Keys(plan.steps), "turnin:1 area:2:4", "replan: the hand-in, then the work left")
	local area = Find(plan.steps, "area:2:4")
	equal(area ~= nil, true, "replan: the other quest's work stays, keyed by itself")
	equal(table.concat(area.quests, " "), "2", "replan: only the quest still under way")
	equal(#area.objectives, 1, "replan: one objective left")
	equal(Model.ObjectiveText(area.objectives[1]), "1/5", "replan: its remaining count is kept")
	equal(area.title:find("Complete 2", 1, true), nil, "replan: no longer titled as shared")
end

-- Far apart, on another map, or group against ordinary: separate visits.
do
	local log = Log({
		[3] = { id = 3, title = "Far", level = 18, complete = false, objectives = { kill } },
	})
	local steps = Model.Plan(Fields(), player, done, log, prefs()).steps
	equal(Find(steps, "area:1:0") ~= nil and Find(steps, "area:3:0") ~= nil, true, "apart: 150 yd off is its own visit")
	equal(table.concat(Find(steps, "area:1:0").quests, " "), "1 2", "apart: the nearby pair stays one")

	log = Log({
		[4] = { id = 4, title = "Group", level = 18, complete = false, objectives = { kill } },
	})
	steps = Model.Plan(Fields(), player, done, log, prefs()).steps
	local ordinary, group = Find(steps, "area:1:0"), Find(steps, "area:4:0")
	equal(ordinary and ordinary.kind, "area", "kinds: the ordinary pair is an area")
	equal(table.concat(ordinary and ordinary.quests or {}, " "), "1 2", "kinds: a group quest does not join it")
	equal(group and group.kind, "dungeon", "kinds: the group quest is a dungeon visit")
	equal(group and #group.objectives, 1, "kinds: alone, with its own objective")

	log = Log({
		[5] = { id = 5, title = "Over there", level = 18, complete = false, objectives = { kill } },
	})
	steps = Model.Plan(Fields(), player, done, log, prefs()).steps
	local here, there = Find(steps, "area:1:0"), Find(steps, "area:5:0")
	equal(table.concat(here and here.quests or {}, " "), "1 2", "maps: the other map's quest does not join")
	equal(there and there.map, 2, "maps: it keeps its own map")
	equal(there and #there.objectives, 1, "maps: and its own objective")
	local adjacent = Fields()
	adjacent.maps[2].continent = 0
	steps = Model.Plan(adjacent, player, done, log, prefs()).steps
	equal(#Find(steps, "area:1:0").quests, 2, "maps: overlapping coordinates on another floor do not join")
	equal(Find(steps, "area:5:0").map, 2, "maps: overlapping floor remains a separate visit")
end

-- A lap: the shared visit sits between its pickups and its hand-ins, which come back to the same town.
do
	local fields = Fields()
	fields.quests[3], fields.quests[4], fields.quests[5] = nil, nil, nil
	local plan = Model.Plan(fields, player, {}, {}, prefs("zone:1"))
	local steps = plan.steps
	equal(Keys(steps), "town:1:5 area:1:0 town:1:5:2", "lap: pickups, the shared area, hand-ins")
	equal(table.concat(steps[1].pickups, " "), "1 2", "lap: both quests are picked up first")
	equal(table.concat(steps[2].quests, " "), "1 2", "lap: and worked as one visit")
	equal(table.concat(steps[3].handins, " "), "1 2", "lap: and handed in after")
	equal(steps[2].title, "Complete 2 objectives · Zone", "lap: the visit is titled as shared")
end

-- The tracker puts each quest's own objective line under its row, grey; a quest with nothing to count has none.
local h = harness.load({
	spf = "v1",
	charDB = { journey = "zone:1413" },
	completed = { 844 },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	},
})
local shared = {
	key = "area:845:0",
	kind = "area",
	title = "Complete 2 objectives · The Barrens",
	quests = { 845, 843 },
	reason = "2 quests here",
	objectives = {
		{ id = 845, text = "Zhevra slain: 3/8", have = 3, need = 8 },
		{ id = 843, have = 1, need = 5 },
		{ id = 843, have = 2, need = 0 },
	},
}
h.ns.Guidance.CurrentStep = function()
	return shared
end
for _, guiding in ipairs({ false, true }) do
	h.ns.Integrations.Guiding = function()
		return guiding
	end
	h.tracker:LayoutContents()
	local block = h.tracker.liveBlocks[shared.key]
	local label = guiding and "tracker, guided" or "tracker"
	equal(block.header, shared.title, label .. ": the header describes every objective")
	equal(block.lines[1]:find("[13] The Zhevra", 1, true) ~= nil, true, label .. ": the first quest row")
	equal(block.lines[2]:find("Zhevra slain: 3/8", 1, true) ~= nil, true, label .. ": its words sit right under it")
	equal(block.lines[2]:find("|cff", 1, true) ~= nil, true, label .. ": coloured, not plain")
	equal(block.lines[3]:find("[23] Gann's Reclamation", 1, true) ~= nil, true, label .. ": the second quest row")
	equal(block.lines[4]:find("1/5", 1, true) ~= nil, true, label .. ": its count sits under it")
	equal(block.lines[5], guiding and shared.reason or block.lines[5], label .. ": nothing follows but the reason")
	equal(block.lines[4]:find("2/0", 1, true), nil, label .. ": an untallied kind adds no row")
end

-- The map tooltip lists the same lines, each under its quest, as "- text".
local lines = {}
local tooltip = setmetatable({}, {
	__index = function()
		return function() end
	end,
})
h.G.GameTooltip_AddHighlightLine = function(_, text)
	lines[#lines + 1] = text
end
h.ns.Pins.StepTooltip(tooltip, shared, 1)
local joined = table.concat(lines, "\n")
equal(joined:find("- Zhevra slain: 3/8", 1, true) ~= nil, true, "tooltip: a quest's words, dashed")
equal(joined:find("- 1/5", 1, true) ~= nil, true, "tooltip: another's count, dashed")
equal(joined:find("2/0", 1, true), nil, "tooltip: an untallied kind adds no line")

assert(#h.errors == 0, "errors: " .. table.concat(h.errors, "\n"))

print(("shared_visit_spec: %d checks passed"):format(checks))
