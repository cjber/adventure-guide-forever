-- Run from the repository root: luajit tests/planner_offers_spec.lua
-- Dungeon alternatives and high-level-zone errands retain distinct recommendations.
local ns = {}
dofile("tests/harness.lua").model(ns)
local Model = ns.Model
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function has(list, value, label)
	checks = checks + 1
	for _, v in ipairs(list) do
		if v == value then
			return
		end
	end
	assert(false, label .. ": " .. tostring(value) .. " not found in list")
end

local function at(x, y, map)
	return { map = map or 1, x = x or 0.5, y = y or 0.5, name = "Giver" }
end

local player = { level = 21, maxLevel = 60, side = 1, raceBit = 1, classBit = 1, map = 1, x = 0.5, y = 0.5 }

-- Minimal data: two dungeons each with eligible quests, no zone quests (forces stranded path).
local data = {
	build = "test",
	source = "fixture",
	quests = {
		[1] = { title = "WC Quest 1", level = 21, min = 18, side = 1, start = at(0.3, 0.5, 1), dungeon = 43 },
		[2] = { title = "WC Quest 2", level = 21, min = 18, side = 1, start = at(0.4, 0.5, 1), dungeon = 43 },
		[3] = { title = "DM Quest 1", level = 21, min = 18, side = 1, start = at(0.5, 0.5, 1), dungeon = 36 },
		[4] = { title = "DM Quest 2", level = 21, min = 18, side = 1, start = at(0.6, 0.5, 1), dungeon = 36 },
		[5] = { title = "DM Quest 3", level = 21, min = 18, side = 1, start = at(0.7, 0.5, 1), dungeon = 36 },
	},
	instances = {
		[43] = { name = "Wailing Caverns", low = 15, high = 25 },
		[36] = { name = "The Deadmines", low = 18, high = 23 },
	},
	maps = { [1] = { continent = 1, cx = 0, cy = 0, sx = 1, sy = 1 } },
	hubs = {},
	zones = {},
}

local function prefs(extra)
	local p = { quests = true, dungeons = true, skipped = {}, optimisedRoute = true }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function keys(journeys)
	local ks = {}
	for _, j in ipairs(journeys) do
		ks[#ks + 1] = j.key
	end
	return ks
end

-- Both dungeons have eligible quests: both should appear as dungeon cards.
do
	local route = Model.Plan(data, player, {}, {}, prefs())
	local ks = keys(route.journeys)
	has(ks, "dungeon:36", "Deadmines offered when it has eligible quests")
	has(ks, "dungeon:43", "Wailing Caverns offered when it has eligible quests")
end

-- The dungeon with more quests sorts first (Deadmines has 3, WC has 2).
do
	local route = Model.Plan(data, player, {}, {}, prefs())
	local first, second
	for _, j in ipairs(route.journeys) do
		if j.kind == "dungeon" then
			if not first then
				first = j.key
			elseif not second then
				second = j.key
			end
		end
	end
	equal(first, "dungeon:36", "dungeon with more quests sorts first")
	equal(second, "dungeon:43", "dungeon with fewer quests sorts second")
end

-- Useful dungeon choices beat a high-level instance with recently unlocked quests.
do
	local ranked = {
		build = "ranking",
		source = "fixture",
		hubs = {},
		zones = {},
		maps = data.maps,
		instances = {
			[36] = { name = "Deadmines", low = 18, high = 23 },
			[43] = { name = "Wailing Caverns", low = 15, high = 25 },
			[48] = { name = "Blackfathom Deeps", low = 24, high = 32 },
			[90] = { name = "Gnomeregan", low = 29, high = 38 },
		},
		quests = {},
	}
	local log = {}
	for index, instance in ipairs({ 36, 36, 43, 48, 90 }) do
		local id, point = 100 + index, at(instance == 36 and 0.8 or 0.51, 0.5)
		ranked.quests[id] = {
			title = "Dungeon errand " .. id,
			level = 21,
			min = instance == 90 and 20 or 10,
			side = 1,
			start = point,
			finish = point,
			dungeon = instance,
		}
		log[id] = { complete = true }
	end
	local function Order()
		local ids = {}
		for _, journey in ipairs(Model.Plan(ranked, player, {}, log, prefs()).journeys) do
			if journey.kind == "dungeon" then
				ids[#ids + 1] = journey.instance
			end
		end
		return table.concat(ids, ",")
	end
	equal(Order(), "36,43,48,90", "level fit precedes accepted count and newness")
	log[102] = nil
	equal(Order(), "43,36,48,90", "equal fit and accepted counts prefer nearer travel")
end

-- A dismissed dungeon does not appear.
do
	local p = prefs({ notInterested = { ["dungeon:36"] = { title = "The Deadmines" } } })
	local route = Model.Plan(data, player, {}, {}, p)
	local ks = keys(route.journeys)
	has(ks, "dungeon:43", "undismissed dungeon still appears")
	for _, k in ipairs(ks) do
		equal(k == "dungeon:36", false, "dismissed dungeon does not appear")
	end
end

-- Stranded fallback offers must respect dismissed quests even with the dungeon toggle off.
do
	local route = Model.Plan(
		data,
		player,
		{},
		{},
		prefs({ dungeons = false, notInterested = { ["quest:3"] = { title = "DM Quest 1" } } })
	)
	for _, journey in ipairs(route.journeys) do
		for _, step in ipairs(journey.steps) do
			for _, id in ipairs(step.quests) do
				equal(id == 3, false, "fallback does not offer a dismissed quest")
			end
		end
	end
end

-- The chosen dungeon is preserved while it has quests (it appears even after level changes).
do
	local p = prefs({ journey = "dungeon:43" })
	local route = Model.Plan(data, player, {}, {}, p)
	local ks = keys(route.journeys)
	has(ks, "dungeon:43", "chosen dungeon preserved while it has quests")
	has(ks, "dungeon:36", "unchosen dungeon also offered alongside the chosen one")
end

-- No fake questless routes: a dungeon with all quests completed is not offered.
do
	local completed = { [1] = true, [2] = true }
	local route = Model.Plan(data, player, completed, {}, prefs())
	local ks = keys(route.journeys)
	for _, k in ipairs(ks) do
		equal(k == "dungeon:43", false, "dungeon with no remaining quests does not appear")
	end
end

-- A zone above the player's level ranks after normal suitable zones.
do
	local zdata = {
		build = "test",
		source = "fixture",
		quests = {
			-- Zone 1: normal zone (min=10, max=20, player level 21 - just above max but quests still ok)
			[10] = { title = "Low zone Q", level = 20, min = 10, side = 1, start = at(0.3, 0.5, 2), zone = 2 },
			-- Zone 2: high zone (min=25, player is level 21 - below min)
			[11] = { title = "High zone Q", level = 22, min = 21, side = 1, start = at(0.4, 0.5, 3), zone = 3 },
		},
		instances = {},
		maps = {
			[1] = { continent = 1, cx = 0, cy = 0, sx = 1, sy = 1 },
			[2] = { continent = 1, cx = 100, cy = 0, sx = 1, sy = 1 },
			[3] = { continent = 1, cx = 200, cy = 0, sx = 1, sy = 1 },
		},
		hubs = {},
		zones = {
			[2] = { name = "Normal Zone", min = 10, max = 20 },
			[3] = { name = "High Zone", min = 25, max = 35 },
		},
	}
	local zplayer = { level = 21, maxLevel = 60, side = 1, raceBit = 1, classBit = 1, map = 1, x = 0.5, y = 0.5 }
	zdata.instances = data.instances
	zdata.quests[1], zdata.quests[3] = data.quests[1], data.quests[3]
	local kept = Model.Plan(zdata, zplayer, {}, {}, prefs({ journey = "dungeon:43", dungeons = false }))
	equal(kept.chosen, true, "chosen dungeon remains after disabling alternatives")
	equal(kept.journey, "dungeon:43", "chosen dungeon keeps its identity")
	for _, card in ipairs(kept.journeys) do
		equal(card.key == "dungeon:36", false, "unchosen dungeon respects opt-out")
	end
	local zroute = Model.Plan(zdata, zplayer, {}, {}, prefs())
	-- Find zone cards and check their order: normal zone (min <= level) before high zone (min > level).
	local zoneCards = {}
	for _, j in ipairs(zroute.journeys) do
		if j.zone then
			zoneCards[#zoneCards + 1] = j
		end
	end
	if #zoneCards >= 2 then
		local firstMin = zdata.zones[zoneCards[1].zone].min
		local secondMin = zdata.zones[zoneCards[2].zone].min
		equal(firstMin <= zplayer.level, true, "first zone card has min <= player.level (normal zone)")
		equal(secondMin > zplayer.level, true, "second zone card has min > player.level (above zone)")
	end
end

-- Accepting every available dungeon quest must not remove its journey.
do
	local log = {
		[3] = { id = 3, title = "DM Quest 1", level = 21, complete = false },
		[4] = { id = 4, title = "DM Quest 2", level = 21, complete = false },
		[5] = { id = 5, title = "DM Quest 3", level = 21, complete = false },
	}
	local inputs = { dungeonEntrances = { [36] = at(0.2, 0.3) } }
	local route = Model.Plan(data, player, {}, log, prefs(), nil, nil, nil, inputs)
	has(keys(route.journeys), "dungeon:36", "accepted dungeon quests retain Deadmines")
	local card
	for _, journey in ipairs(route.journeys) do
		if journey.instance == 36 then
			card = journey
		end
	end
	equal(card.steps[1].entrance, 36, "unknown objective points lead to the known entrance")
	equal(#card.steps[1].quests, 3, "one entrance stop holds all unplaced quests")
	equal(card.steps[1].title, ns.L.GO_TO_ENTRANCE, "entrance is not described as an objective location")
	local dismissed =
		Model.Plan(data, player, {}, log, prefs({ notInterested = { ["dungeon:36"] = true } }), nil, nil, nil, inputs)
	for _, journey in ipairs(dismissed.journeys) do
		equal(journey.key == "dungeon:36", false, "dismissal remains respected")
	end
	local after = { [3] = log[3], [4] = log[4] }
	local updated = Model.Refresh(data, player, { [5] = true }, after, prefs(), route)
	local retained
	for _, journey in ipairs(updated.journeys) do
		if journey.instance == 36 then
			retained = journey
		end
	end
	equal(#retained.steps[1].quests, 2, "combat refresh prunes a finished dungeon quest")
	local finished = { [3] = true, [4] = true, [5] = true }
	local empty = Model.Refresh(data, player, finished, {}, prefs(), updated)
	for _, journey in ipairs(empty.journeys) do
		equal(journey.key == "dungeon:36", false, "empty dungeon stops disappear in combat")
	end
	local skipped =
		Model.Plan(data, player, {}, log, prefs({ skipped = { ["entrance:36"] = true } }), nil, nil, nil, inputs)
	for _, journey in ipairs(skipped.journeys) do
		equal(journey.key == "dungeon:36", false, "skipped entrance is respected")
	end
	local unknown = Model.Plan(data, player, {}, log, prefs())
	for _, journey in ipairs(unknown.journeys) do
		equal(journey.key == "dungeon:36", false, "unknown entrance does not invent a route")
	end
end

print(("planner_offers_spec: %d checks passed"):format(checks))
