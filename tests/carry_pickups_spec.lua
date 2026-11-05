-- Run from the repository root: luajit tests/carry_pickups_spec.lua
-- Quests in your log suggests a few quests to pick up on its way while the client's log has room: sized to the free
-- slots, no more than a card's worth of actions, and only quests whose whole detour stays small.
local ns = {}
dofile("tests/harness.lua").model(ns)
local Model = ns.Model
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- A flat world: one zone a hundred yards to the 0.01 map unit, every giver and hand-in in one of two towns.
local function Place(x, y, hub, name)
	return { map = 1, x = x, y = y, hub = hub or 1, name = name or "Giver" }
end
local function Quest(x, y, hub)
	return {
		title = "Quest",
		level = 20,
		min = 10,
		side = 1,
		zone = 1,
		start = Place(x, y, hub),
		finish = Place(x, y, hub, "Ender"),
		need = { [0] = 1 },
		obj = { { 0, x * 1000, y * 1000, 30, 1 } },
	}
end
local data = {
	build = "test",
	source = "fixture",
	quests = {},
	zones = { [1] = { name = "Zone", min = 10, max = 30 } },
	maps = { [1] = { name = "Zone", continent = 1, cx = 0, cy = 0, sx = 10000, sy = 10000 } },
	continents = { [1] = { x = 0, y = 0 } },
	hubs = { [1] = { name = "Town One" }, [2] = { name = "Town Two" } },
	towns = { [1] = {} },
}
-- The carried quest's objective is the way the rest of these quests must be near.
data.quests[100] = Quest(0.5, 0.5)
for id = 1, 5 do
	data.quests[id] = Quest(0.5 + id * 0.01, 0.5)
end
-- A near giver whose work is far off the route: the whole quest has to sit on the way.
data.quests[6] = Quest(0.51, 0.5)
data.quests[6].obj = { { 0, 950, 500, 30, 1 } }
-- Far off the route: over 1,200 yards from every stop.
data.quests[9] = Quest(0.95, 0.5)

local function World(logMax)
	local player = {
		level = 20,
		maxLevel = 60,
		side = 1,
		raceBit = 1,
		classBit = 1,
		map = 1,
		x = 0.5,
		y = 0.5,
		logMax = logMax,
	}
	local log = {
		[100] = {
			id = 100,
			title = "Carried",
			level = 20,
			complete = false,
			objectives = { { type = "monster", done = false, have = 0, need = 1 } },
		},
	}
	return player, log, { quests = true, dungeons = false, skipped = {} }
end

---@param route AGFRoute
local function Carry(route)
	for _, journey in ipairs(route.journeys) do
		if journey.kind == "carry" then
			return journey
		end
	end
end

-- Every quest the carry card picks up, by ID.
---@param journey AGFJourney
local function Picked(journey)
	local picked = {}
	for _, step in ipairs(journey.steps) do
		for _, id in ipairs(step.pickups or {}) do
			picked[#picked + 1] = id
		end
	end
	return picked
end

do -- Room in the log: the nearby quests are worth picking up on the way.
	local player, log, prefs = World(40)
	local route = Model.Plan(data, player, {}, log, prefs)
	local carry = Carry(route)
	equal(carry.kind, "carry", "room: the carry card is offered")
	local picked = Picked(carry)
	equal(#picked, 3, "room: a few pickups, no more")
	for index, id in ipairs({ 1, 2, 3 }) do
		equal(picked[index], id, "room: the smallest detours first, " .. id)
	end
	-- The same route again: a rebuild keeps the pickups it chose, with the rest of its route.
	local again = Carry(Model.Plan(data, player, {}, log, prefs, nil, nil, route))
	equal(table.concat(Picked(again), ","), table.concat(picked, ","), "room: a rebuild keeps the pickups")
	equal(again.steps[1].key, carry.steps[1].key, "room: a rebuild keeps step 1")
end

do -- One free slot: one pickup, however many are near.
	local player, log, prefs = World(2)
	local picked = Picked(Carry(Model.Plan(data, player, {}, log, prefs)))
	equal(#picked, 1, "one free slot: one pickup")
	equal(picked[1], 1, "one free slot: the nearest")
end

do -- Full log: there is no slot to take anything, so the card holds only what is already carried.
	local player, log, prefs = World(1)
	local carry = Carry(Model.Plan(data, player, {}, log, prefs))
	equal(carry.kind, "carry", "full: the carry card still shows the carried quest")
	equal(#Picked(carry), 0, "full: no pickup is suggested")
	for _, step in ipairs(carry.steps) do
		equal(#(step.pickups or {}), 0, "full: no town offers a pickup: " .. step.key)
	end
end

do -- Detours stay small: a giver far off the route waits, and every one offered stands within 1,200 yards.
	local player, log, prefs = World(40)
	local carry = Carry(Model.Plan(data, player, {}, log, prefs))
	local picked = Picked(carry)
	equal(#picked, 3, "detour: the near quests fill the free, short route")
	equal(picked[1] == 9, false, "detour: the far quest is never offered")
	equal(#carry.steps <= Model.MAX_STEPS, true, "detour: the card keeps its actions bounded")
	for _, id in ipairs(picked) do
		equal(id == 6 or id == 9, false, "detour: quest " .. id .. " keeps its work on the way")
		local gap = math.sqrt((data.quests[id].start.x - player.x) ^ 2 + (data.quests[id].start.y - player.y) ^ 2)
		equal(gap * 10000 <= 1200, true, "detour: quest " .. id .. " stands on the way")
	end
	for _, step in ipairs(carry.steps) do
		for _, id in ipairs(step.pickups or {}) do
			equal(id == 9, false, "detour: the far giver never joins " .. step.key)
		end
	end
end

print("carry_pickups_spec: " .. checks .. " checks passed")
