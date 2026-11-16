-- ID-only admission avoids objective work without changing placed membership or held rows.
local ns = {}
dofile("tests/harness.lua").model(ns)
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local reads = {}
local data = { quests = {}, maps = { [1] = { name = "Here" } } }
local log = {}
for id = 1, 7 do
	local fields = { need = { [1] = 2 }, obj = { { 1, id * 100, 500, 10, 1 } } }
	data.quests[id] = setmetatable({ level = 16, zone = 1 }, {
		__index = function(_, key)
			if key == "need" then
				reads[id] = (reads[id] or 0) + 1
			end
			return fields[key]
		end,
	})
	log[id] = { id = id, title = "Quest " .. id, level = 16, complete = false }
end
-- Admitted unfinished and completed rows with no placement must retain their held=false value.
data.quests[4] = { level = 16 }
log[5].complete = true
log[6].complete = true
log[6].map, log[6].x, log[6].y = 1, 0.6, 0.5
local player = { level = 16 }
local function run(belongs, admit)
	local steps, stops, plan = {}, {}, { areas = {}, anchors = {} }
	local held = ns.Planner.Steps.LogSteps(data, player, log, {}, belongs, stops, steps, plan, admit)
	-- Anchors are keyed by freshly allocated step tables; compare them by stable step key.
	local anchors = {}
	for _, area in ipairs(plan.areas) do
		equal(plan.anchors[area] ~= nil, true, "area retains its anchor")
		anchors[area.key] = plan.anchors[area]
	end
	return { steps = steps, stops = stops, areas = plan.areas, anchors = anchors, held = held }
end
local function same(actual, expected, label)
	if type(expected) ~= "table" then
		equal(actual, expected, label)
		return
	end
	equal(type(actual), "table", label)
	for key, value in pairs(expected) do
		same(actual[key], value, label .. "." .. tostring(key))
	end
	for key in pairs(actual) do
		equal(expected[key] ~= nil, true, label .. " has no extra " .. tostring(key))
	end
end
local function chain(id)
	return id == 1 or id == 4 or id == 5 or id == 6
end
local baseline = run(chain)
reads = {}
local filtered = run(chain, chain)
equal(reads[2] or 0, 0, "excluded unrelated chain does not read objective slots")
equal(reads[3] or 0, 0, "second unrelated chain does not read objective slots")
equal(reads[7] or 0, 0, "excluded dropped quest does not read objective slots")
equal((reads[1] or 0) > 0, true, "admitted quest uses actual Nodes objective work")
same(filtered, baseline, "admitted steps, order, stops, areas, anchors and held unchanged")
equal(filtered.held[4], false, "unplaced unfinished quest stays held")
equal(filtered.held[5], false, "unplaced completed quest stays held")
equal(filtered.held[6] ~= nil, true, "placed completed quest stays held")

-- Turnins admits completed IDs, then still requires a valid place.
local function complete(id)
	return log[id].complete == true and id ~= 7
end
local function placedComplete(id, place)
	return complete(id) and place ~= nil
end
local oldTurnins = run(placedComplete)
reads = {}
local turnins = run(placedComplete, complete)
same(turnins, oldTurnins, "completed membership still depends on placement")
equal(turnins.held[5], nil, "unplaced completed quest excluded by belongs")
for _, id in ipairs({ 1, 2, 3, 7 }) do
	equal(reads[id] or 0, 0, "unfinished quest avoids Turnins objective work " .. id)
end

-- Rejected completed IDs also skip hand-in placement and never reach belongs.
local placeReads, belongsCalls = 0, 0
local rejected = setmetatable({ id = 8, title = "Rejected complete", complete = true, level = 16 }, {
	__index = function(_, key)
		if key == "poi" then
			placeReads = placeReads + 1
		end
	end,
})
local rejectedHeld = ns.Planner.Steps.LogSteps(data, player, { [8] = rejected }, {}, function()
	belongsCalls = belongsCalls + 1
	return true
end, {}, {}, { areas = {}, anchors = {} }, function()
	return false
end)
equal(placeReads, 0, "rejected completed ID skips hand-in placement")
equal(belongsCalls, 0, "rejected ID never reaches placed membership")
equal(next(rejectedHeld), nil, "rejected ID has no held row")

-- Without admission, all IDs still reach the place-dependent predicate in sorted order.
local seen = {}
reads = {}
local zone = run(function(id, place)
	seen[#seen + 1] = id
	return place ~= nil and place.x < 0.4
end)
for id = 1, 7 do
	equal(seen[id], id, "legacy belongs order " .. id)
end
equal((reads[2] or 0) > 0, true, "legacy path still resolves objectives before belongs")
equal(zone.held[1] ~= nil, true, "zone holds matching placed quest")
equal(zone.held[6], nil, "zone excludes other placement")
equal(zone.held[4], nil, "zone excludes unplaced quest")
-- Exercise the real card callers with and without the optional optimization. Reload Journeys after
-- installing the wrapper because its LogSteps reference is local, just as Steps' Nodes reference is.
local function routeWithoutAdmission(legacy)
	local modelNS = {}
	dofile("tests/harness.lua").model(modelNS)
	local logSteps = modelNS.Planner.Steps.LogSteps
	local admissions = 0
	modelNS.Planner.Steps.LogSteps = function(world, who, entries, ready, belongs, stops, steps, plan, admit)
		admissions = admissions + (admit and 1 or 0)
		return logSteps(world, who, entries, ready, belongs, stops, steps, plan, not legacy and admit or nil)
	end
	assert(loadfile("Planning/Journeys.lua"))("AdventureGuideForever", modelNS)
	local world = { quests = {}, zones = { [1] = { name = "Here", min = 10, max = 20 } } }
	local entries = {}
	for id = 1, 8 do
		world.quests[id] = {
			title = "Quest " .. id,
			level = 16,
			min = 10,
			side = 2,
			zone = 1,
			start = { map = 1, x = id / 10, y = 0.5, name = "Giver" },
			finish = { map = 1, x = id / 10, y = 0.5, name = "Ender" },
			need = { [1] = 2 },
			obj = { { 1, id * 100, 500, 10, 1 } },
		}
		if id % 2 == 1 then
			world.quests[id].next = id + 1
		else
			world.quests[id].pre = { id - 1 }
		end
		if id % 2 == 1 then
			entries[id] = { id = id, title = "Quest " .. id, level = 16, complete = id == 3 or id == 5 }
		end
	end
	world.quests[5].finish = nil -- Complete, admitted to tracked/chain, but unplaced.
	local who = {
		level = 16,
		maxLevel = 60,
		side = 2,
		raceBit = 2,
		classBit = 64,
		map = 1,
		x = 0.5,
		y = 0.5,
		tracked = { [1] = true, [3] = true, [5] = true, [7] = true },
	}
	local prefs = {
		quests = true,
		dungeons = false,
		skipped = {},
		optimisedRoute = true,
		journey = "chain:3",
		notInterested = { ["quest:7"] = true },
	}
	local route = modelNS.Model.Plan(world, who, {}, entries, prefs)
	equal(admissions >= 3, true, "tracked, turnins and chain callers supply admission")
	return route
end
same(
	routeWithoutAdmission(false),
	routeWithoutAdmission(true),
	"real route and cards retain identity, contents and order"
)
print("log_steps_filter_spec: " .. checks .. " checks passed")
