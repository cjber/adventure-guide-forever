-- Run from the repository root: luajit tests/carry_room_spec.lua
-- A low-level quest in the log, one with no pickup and no work the route can place, must not cost the carry card's
-- on-the-way pickups: its town keeps its giver, and a quest taken up since the last build never pushes a pickup the
-- route already made off it (docs/design.md §4.3). Regression for #442: Dwarven Outfitters (179, level 1) in the log
-- dropped Secure the Mountain (98322, level 8) from the route's towns in the real data.
local ns = {}
dofile("tests/harness.lua").model(ns)
local Model = ns.Model
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- A flat world a hundred yards to the 0.01 map unit, with nine towns along the middle of the map.
local function Place(x, hub)
	return { map = 1, x = x, y = 0.5, hub = "1:" .. hub, name = "Giver " .. hub }
end
local function Quest(x, hub)
	return {
		title = "Quest " .. hub,
		level = 20,
		min = 1,
		side = 1,
		zone = 1,
		start = Place(x, hub),
		finish = Place(x, hub),
		need = { [0] = 1 },
		obj = { { 0, x * 1000, 500, 30, 1 } },
	}
end
local data = {
	build = "test",
	source = "fixture",
	quests = {},
	zones = { [1] = { name = "Zone", min = 1, max = 30 } },
	maps = { [1] = { name = "Zone", continent = 1, cx = 0, cy = 0, sx = 10000, sy = 10000 } },
	continents = { [1] = { x = 0, y = 0 } },
	hubs = {},
	towns = { [1] = {} },
}
for hub = 1, 9 do
	local x = hub * 0.1
	data.hubs["1:" .. hub] = { name = "Town " .. hub }
	data.towns[1][#data.towns[1] + 1] = {
		area = hub,
		x0 = x - 0.02,
		x1 = x + 0.02,
		y0 = 0.48,
		y1 = 0.52,
		cx = x,
		cy = 0.5,
	}
end
-- Hand-in only: one town visit each, so the log's own route takes one action per town.
for hub = 1, 9 do
	data.quests[hub] = Quest(hub * 0.1, hub)
end
-- Three givers on the way, at the first three towns.
for offset = 0, 2 do
	local id = 1000 + offset
	data.quests[id] = Quest((offset + 1) * 0.1, offset + 1)
end
-- A low-level quest with nothing the route can place: no objectives, no finish. It is the shape of a grey quest
-- sitting in the log, such as 179 in the real data.
data.quests[3000] = {
	title = "Low-level",
	level = 1,
	min = 1,
	side = 1,
	zone = 1,
	start = Place(0.9, 9),
}
-- A quest with work far away, taken up in the second half: its area is one more action the log's route takes.
data.quests[3001] = Quest(0.9, 9)
data.quests[3001].obj = { { 0, 900, 900, 30, 1 } }

local player = {
	level = 20,
	maxLevel = 60,
	side = 1,
	raceBit = 1,
	classBit = 1,
	map = 1,
	x = 0.1,
	y = 0.5,
	logMax = 40,
}
local prefs = { quests = true, dungeons = false, skipped = {}, optimisedRoute = true }

-- The log's completed quests, handed in at a town each, and the client's waypoint on the data's finish.
local function Carried(hubs)
	local log = {}
	for hub = 1, hubs do
		local finish = data.quests[hub].finish
		log[hub] = { id = hub, title = data.quests[hub].title, level = 20, complete = true }
		log[hub].map, log[hub].x, log[hub].y = finish.map, finish.x, finish.y
	end
	return log
end

---@param route AGFRoute
local function Carry(route)
	for _, journey in ipairs(route.journeys) do
		if journey.kind == "carry" then
			return journey
		end
	end
end

-- The step key that offers `id` as a pickup, or nil.
local function Offering(journey, id)
	for _, step in ipairs(journey.steps) do
		for _, pickup in ipairs(step.pickups or {}) do
			if pickup == id then
				return step.key
			end
		end
	end
end

do -- The level 1 quest nothing places: it costs the card no action, so the town keeps its pickup.
	local log = Carried(9)
	local before = Carry(Model.Plan(data, player, {}, log, prefs))
	equal(Offering(before, 1000), "town:1:1", "before: the town offers its pickup")
	log[3000] = { id = 3000, title = data.quests[3000].title, level = 1, complete = false }
	local after = Carry(Model.Plan(data, player, {}, log, prefs))
	equal(Offering(after, 1000), "town:1:1", "low-level: the town still offers its pickup")
	equal(after.steps[1].key, before.steps[1].key, "low-level: step 1 holds")
end

do -- A quest taken up since the last build does not push the pickups the route already made off it.
	local log = Carried(7)
	local first = Model.Plan(data, player, {}, log, prefs)
	local before = Carry(first)
	local picked = {}
	for _, id in ipairs({ 1000, 1001, 1002 }) do
		equal(Offering(before, id) ~= nil, true, "committed: the card offers " .. id)
		picked[id] = Offering(before, id)
	end
	log[3001] = {
		id = 3001,
		title = data.quests[3001].title,
		level = 20,
		complete = false,
		objectives = { { type = "monster", done = false, have = 0, need = 1 } },
	}
	local again = Carry(Model.Plan(data, player, {}, log, prefs, nil, nil, first))
	for id, key in pairs(picked) do
		equal(Offering(again, id), key, "taken up: the card keeps its pickup " .. id)
	end
	equal(again.steps[1].key, before.steps[1].key, "taken up: step 1 holds")
end

print("carry_room_spec: " .. checks .. " checks passed")
