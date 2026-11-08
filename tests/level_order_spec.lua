-- Run from the repository root: luajit tests/level_order_spec.lua
-- #474: in Duskwood the route led with a red, optional quest while a green quest and a ready hand-in waited nearer
-- (docs/design.md §4.1). The nearest order now takes every stop that is work for now before a stop above the player's
-- level, so near-level and lower-level work and hand-ins already done come before a quest several levels above them;
-- within a tier distance still decides.
local ns = {}
dofile("tests/harness.lua").model(ns)
local Model = ns.Model
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- A quest at Duskwood's Darkshire: `id` starts and finishes at the same giver, and its one objective is `x`, `y`
-- with ring `r`. The reporter's high-level quest has a broad objective area whose centre is far out in the zone.
local function quest(title, level, x, y, r, needCount)
	return {
		title = title,
		level = level,
		min = 18,
		side = 1,
		zone = 1431,
		xp = 1000,
		start = { map = 1431, x = 0.798, y = 0.48, name = "Viktori Prism'Antras", hub = 42 },
		finish = { map = 1431, x = 0.798, y = 0.48, name = "Viktori Prism'Antras", hub = 42 },
		need = { [4] = needCount },
		obj = { { 4, x * 1000, y * 1000, r, 1431 } },
	}
end

local data = {
	quests = {},
	zones = { [1431] = { name = "Duskwood", min = 18, max = 30 } },
	maps = { [1431] = { name = "Duskwood", continent = 0, cx = 0, cy = 0, sx = 2700, sy = 1800 } },
	continents = { [0] = { x = 0, y = 0 } },
}
-- The reporter's quests: Look To The Stars at level 30, accepted and optional, and green Dusky Crab Cakes at 20
-- close beside the player. The broad level 30 area reaches Darkshire, so distance alone still leads with it.
data.quests[181] = quest("Look To The Stars", 30, 0.3, 0.85, 1450, 1)
data.quests[93] = quest("Dusky Crab Cakes", 20, 0.85, 0.56, 10, 6)
-- Jitters' Growling Gut, finished, is ready to hand in far from Darkshire.
data.quests[5] = quest("Jitters' Growling Gut", 20, 0.1, 0.1, 10, 0)

local player =
	{ level = 24, maxLevel = 60, side = 1, raceBit = 1, classBit = 2, map = 1431, x = 0.801, y = 0.524, logMax = 20 }
local log = {
	[181] = {
		id = 181,
		title = "Look To The Stars",
		level = 30,
		complete = false,
		objectives = { { type = "item", done = false, have = 0, need = 1 } },
	},
	[93] = {
		id = 93,
		title = "Dusky Crab Cakes",
		level = 20,
		complete = false,
		objectives = { { type = "item", done = false, have = 1, need = 6 } },
	},
	[5] = { id = 5, title = "Jitters' Growling Gut", level = 20, complete = true, map = 1431, x = 0.1, y = 0.1 },
}
local prefs = { quests = true, dungeons = false, skipped = {}, journey = "zone:1431" }

local route = Model.Plan(data, player, {}, log, prefs)
local function step(key)
	for index, each in ipairs(route.steps) do
		if each.key == key then
			return each, index
		end
	end
end

local high, highIndex = step("area:181:4")
local low, lowIndex = step("area:93:4")
local handin, handinIndex = step("turnin:5")
equal(high ~= nil, true, "level order: the accepted level 30 quest is on the route")
equal(low ~= nil, true, "level order: the accepted level 20 quest is on the route")
equal(handin ~= nil, true, "level order: the finished quest is on the route")
equal(high.optional, true, "level order: the level 30 quest is optional")
equal(low.optional, nil, "level order: the level 20 quest is not optional")
equal(lowIndex < highIndex, true, "level order: near-level work leads the higher-level quest")
equal(handinIndex < highIndex, true, "level order: the ready hand-in leads the higher-level quest")
equal(lowIndex, 1, "level order: the near-level work leads the route")

-- The other nearest path, Build (used by cards that are not laps), takes a stop for now before a stop above the
-- player, ahead of distance: the far low-level stop still leads the near high-level one.
local highStop = { key = "high", x = 10, y = 0, continent = 1, known = true, r = 0 }
local lowStop = { key = "low", x = 100, y = 0, continent = 1, known = true, r = 0 }
local order = Model.Nearest(
	{ x = 0, y = 0, continent = 1, known = true },
	{ highStop, lowStop },
	function(place)
		return place
	end,
	nil,
	nil,
	function(place)
		return place.key == "high" and 1 or 0
	end
)
equal(order[1].key, "low", "level order: Build takes work for now before a stop above the player")

-- The tier reads the quest level against the player's own ceiling, the "Maximum quest level above yours" setting
-- that already limits pickups (Model.AboveCeiling), two levels by default.
local tierData = {
	quests = {
		[1] = { level = 25 },
		[2] = { level = 20 },
		[3] = { level = 17 },
		[4] = { level = 22 },
		[5] = { level = 23 },
	},
}
local tierPlayer = { level = 20 }
local function tier(quests, tierLog)
	return Model.StopTier(tierData, tierLog or {}, tierPlayer, { quests = quests })
end
equal(tier({ 1 }), 1, "level order: a quest five levels above is above")
equal(tier({ 2 }), 0, "level order: a quest at the player's level is now")
equal(tier({ 3 }), 0, "level order: a quest below the player's level is now")
equal(tier({}), 0, "level order: a stop with no quest is now")
equal(tier({ 1 }, { [1] = { level = 25, complete = true } }), 0, "level order: a ready hand-in is now")
equal(tier({ 1, 3 }), 0, "level order: one quest for now makes the whole stop now")
equal(tier({ 4 }), 0, "level order: a quest two levels above is within the default ceiling")
equal(tier({ 5 }), 1, "level order: a quest three levels above is past the default ceiling")
tierPlayer.maxQuestLevelOffset = 3
equal(tier({ 5 }), 0, "level order: a higher ceiling setting makes that quest work for now")
tierPlayer.maxQuestLevelOffset = nil

-- A level 17 stop next door leads a level 20 stop across the map for a level 20 player: both are work for now, so
-- distance decides.
local nearStop = { key = "near", x = 10, y = 0, continent = 1, known = true, r = 0, quests = { 3 } }
local farStop = { key = "far", x = 100, y = 0, continent = 1, known = true, r = 0, quests = { 2 } }
local function tierRank(stop)
	return Model.StopTier(tierData, {}, tierPlayer, stop)
end
equal(tierRank(nearStop), 0, "level order: the level 17 stop next door is now")
equal(tierRank(farStop), 0, "level order: the level 20 stop across the map is now")
local nowOrder = Model.Nearest({ x = 0, y = 0, continent = 1, known = true }, { farStop, nearStop }, function(place)
	return place
end, nil, nil, tierRank)
equal(nowOrder[1].key, "near", "level order: distance decides between two stops for now")

print(("level_order_spec: %d checks passed"):format(checks))
