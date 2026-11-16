-- Count the Laps closure Journeys actually captures, and compare the whole Plan with the lap baseline.
local harness = dofile("tests/harness.lua")
local function same(a, b, path)
	path = path or "route"
	assert(type(a) == type(b), path .. " type")
	if type(a) ~= "table" then
		assert(a == b, path .. " value")
		return
	end
	for key, value in pairs(b) do
		same(a[key], value, path .. "." .. tostring(key))
	end
	for key in pairs(a) do
		assert(b[key] ~= nil, path .. " extra " .. tostring(key))
	end
end
local function run(case, planned, skipped, old, baseline)
	local ns = {}
	harness.model(ns)
	local calls, builds = 0, 0
	local log = {}
	local laps = ns.Planner.Laps.Laps
	ns.Planner.Laps.Laps = function(...)
		if select(11, ...) == "turnins" then
			calls = calls + 1
		end
		return laps(...)
	end
	if baseline then
		ns.Planner.Laps.Empty = function(data, player, prefs, card)
			return laps(data, player, {}, log, {}, { areas = {}, anchors = {} }, prefs, nil, nil, nil, card)
		end
	end
	local build = ns.Planner.Routing.Build
	ns.Planner.Routing.Build = function(...)
		builds = builds + 1
		return build(...)
	end
	assert(loadfile("Planning/Journeys.lua"))("AdventureGuideForever", ns)
	local world = {
		quests = {},
		zones = { [1] = { name = "Here", min = 10, max = 20 } },
		maps = { [1] = { name = "Here", continent = 1, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [1] = { x = 0, y = 0 } },
	}
	local player = { level = 16, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
	if case ~= "empty" then
		log[1] = { id = 1, title = "Hand in", level = 16, complete = case ~= "unfinished" }
		if case ~= "unplaced" then
			log[1].map, log[1].x, log[1].y = 1, 0.6, 0.5
		end
	end
	local prefs = {
		quests = false,
		dungeons = false,
		skipped = skipped and { absent = true, ["turnin:1"] = true } or {},
		optimisedRoute = planned,
		notInterested = case == "dismissed" and { turnins = true }
			or case == "dropped" and { ["quest:1"] = true }
			or {},
	}
	local last = old and { orders = { turnins = { "stale", picked = { [77] = true }, taken = { [88] = true } } } }
		or nil
	local result = ns.Model.Plan(world, player, {}, log, prefs, nil, nil, last)
	return result, calls, builds
end
local failures = {}
for _, case in ipairs({ "empty", "unfinished", "unplaced", "dropped", "dismissed", "valid" }) do
	for _, planned in ipairs({ false, true }) do
		for _, skipped in ipairs({ false, true }) do
			for _, old in ipairs({ false, true }) do
				local actual, calls, builds = run(case, planned, skipped, old, false)
				local baseline, _, baselineBuilds = run(case, planned, skipped, old, true)
				same(actual.orders, baseline.orders, "route.orders")
				same(actual, baseline)
				if case == "empty" and planned and not skipped then
					same(actual.orders.turnins, { picked = {}, taken = {} }, "cleaned order")
				end
				if case == "empty" and old and (skipped or not planned) then
					same(
						actual.orders.turnins,
						{ "stale", picked = { [77] = true }, taken = { [88] = true } },
						"retained order"
					)
				end
				local expected = case == "valid" and 1 or 0
				if calls ~= expected then
					failures[#failures + 1] = case .. ": Laps " .. calls .. " expected " .. expected
				end
				assert(builds == baselineBuilds, "empty producer must not add Build calls")
			end
		end
	end
end
print("empty_turnins_spec: 48 full Plan and route.orders baseline comparisons passed")
assert(#failures == 0, table.concat(failures, "\n"))
print("empty_turnins_spec: actual captured Laps calls empty=0, valid=1 passed")
