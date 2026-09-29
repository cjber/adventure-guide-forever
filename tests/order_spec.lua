-- Run from the repository root: luajit tests/order_spec.lua
-- The route ordering (docs/design.md §4.1): Model.Nearest takes the nearest action at every step, finishes a town
-- before leaving it, and never revisits a stop; Model.Plan's route is nearest-first over the player's pickups, the
-- areas of the quests they carry, and their ready hand-ins.
local ns = {}
dofile("tests/harness.lua").model(ns)
local Model = ns.Model
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

--[[ Model.Nearest: the greedy order itself, on plain positions so the rule is exact ]]

local function Step(key, x, y, hub)
	return { key = key, x = x, y = y, continent = 1, known = true, r = 0, hub = hub }
end
local function Keys(path)
	local keys, seen = {}, {}
	for _, step in ipairs(path) do
		keys[#keys + 1] = step.key
		equal(seen[step.key], nil, "order: " .. step.key .. " placed once")
		seen[step.key] = true
	end
	return table.concat(keys, " ")
end
local function Town(step)
	return step.hub
end
local from = { x = 0, y = 0, continent = 1, known = true }
local function At(step)
	return step
end

-- Nearest first, whatever the kind: the nearest stop leads and the route grows from it.
equal(
	Keys(Model.Nearest(from, { Step("a", 100, 0, 1), Step("b", 300, 0, 1), Step("c", 50, 0, 2) }, At, Town)),
	"c a b",
	"nearest: the nearest stop leads, then the nearest of the rest"
)
-- The look-ahead: a stop in the town the route is already in comes before leaving it, though a rival is nearer.
equal(
	Keys(Model.Nearest(from, { Step("a", 100, 0, 1), Step("c", 105, 0, 2), Step("b", 110, 0, 1) }, At, Town)),
	"a b c",
	"nearest: the same town is finished before the route leaves it"
)
-- Without a town, the rule is the nearest stop alone.
equal(
	Keys(Model.Nearest(from, { Step("a", 100, 0, 1), Step("c", 105, 0, 2), Step("b", 110, 0, 1) }, At)),
	"a c b",
	"nearest: with no town, the nearest stop alone"
)
-- Ties break by key, so a rebuild gives the same order.
equal(
	Keys(Model.Nearest(from, { Step("b", 100, 0, 1), Step("a", 100, 0, 1) }, At, Town)),
	"a b",
	"nearest: a tie breaks by key"
)

--[[ Model.Plan: the same rule over pickups, the areas of carried quests, and ready hand-ins ]]

local data = {
	quests = {},
	zones = { [1] = { name = "Zone", min = 10, max = 25 } },
	maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
	continents = { [0] = { x = 0, y = 0 } },
}
for id, x in ipairs({ 0.3, 0.7 }) do
	data.quests[id] = {
		title = "Quest " .. id,
		level = id == 1 and 21 or 17,
		min = 10,
		side = 1,
		zone = 1,
		start = { map = 1, x = x, y = 0.5, name = "Giver " .. id, hub = id },
		finish = { map = 1, x = x, y = 0.5, name = "Giver " .. id, hub = id },
		need = { [0] = 10 },
		obj = { { 0, x * 1000, 500, 10 } },
		xp = 1000,
	}
end
local log = {}
for id in ipairs({ 1, 2 }) do
	log[id] = {
		id = id,
		title = "Quest " .. id,
		level = data.quests[id].level,
		complete = false,
		objectives = { { type = "monster", done = false, have = 0, need = 10 } },
	}
end
local player = { level = 19, maxLevel = 60, side = 1, raceBit = 1, classBit = 2, map = 1, x = 0.5, y = 0.5 }
local prefs = { quests = true, dungeons = false, skipped = {}, journey = "zone:1" }
local function first()
	return Model.Plan(data, player, {}, log, prefs).steps[1]
end

-- Equidistant work: the tie breaks by key, not by a quest's worth or difficulty.
equal(first().quests[1], 1, "plan: equidistant areas tie by key")
player.x = 0.6
equal(first().quests[1], 2, "plan: the nearer area leads")
player.x = 0.5
-- A finished quest's hand-in is safe to take, and stays on the route.
log[1].complete = true
local route = Model.Plan(data, player, {}, log, prefs).steps
local turnin
for _, step in ipairs(route) do
	turnin = turnin or (step.key == "turnin:1" and step or nil)
end
equal(turnin ~= nil and turnin.quests[1] == 1, true, "plan: a finished quest's hand-in is on the route")

print(("order_spec: %d checks passed"):format(checks))
