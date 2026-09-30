-- Run from the repository root: luajit tests/route_order_spec.lua
-- The route order setting (docs/design.md §4.1): the default nearest order takes the nearest actionable stop at every
-- step, recomputed from the player, so a far story pickup never jumps ahead of nearer work. The opt-in planned
-- (beta) order still fronts the story's chapter. A quest's pickup precedes its own objectives, and its hand-in
-- follows them, in both orders.
local ns = {}
dofile("tests/harness.lua").model(ns)
local Model = ns.Model
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- A quest whose objective sits beside `x` on map 1, started and finished in `hub`'s town.
local function quest(x, hub)
	return {
		title = "Quest",
		level = 18,
		min = 10,
		side = 2,
		zone = 1,
		xp = 1000,
		start = { map = 1, x = x, y = 0.5, name = "Giver", hub = hub },
		finish = { map = 1, x = x, y = 0.5, name = "Giver", hub = hub },
		obj = { { 0, x * 1000, 500, 10 } },
		need = { [0] = 5 },
	}
end

local data = {
	quests = {},
	zones = { [1] = { name = "Zone", min = 10, max = 25 } },
	maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
	continents = { [0] = { x = 0, y = 0 } },
	hubs = { [5] = { name = "Far Town" }, [6] = { name = "Near Town" } },
}
-- The story: a proven chain 1 > 2, its pickup in a far town, its work beside that town.
data.quests[1] = quest(0.9, 5)
data.quests[2] = quest(0.92, 5)
data.quests[1].next, data.quests[2].pre = 2, { 1 }
-- Work already in the log, its objective beside the player: the nearer thing to do.
data.quests[10] = quest(0.52, 6)

local player = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
local log = {
	[10] = {
		id = 10,
		title = "In progress",
		level = 18,
		complete = false,
		objectives = { { type = "monster", done = false, have = 0, need = 5 } },
	},
}

local function route(planned)
	local prefs = { quests = true, dungeons = false, skipped = {}, journey = "zone:1", optimisedRoute = planned }
	return Model.Plan(data, player, {}, log, prefs)
end

-- The 1-based place of `key` in the chosen card's steps, or nil when it is not drawn.
local function nth(steps, key)
	for index, step in ipairs(steps) do
		if step.key == key then
			return index
		end
	end
	return nil
end

local nearest = route(false)
local planned = route(true)
equal(nearest.journey, "zone:1", "nearest: the chosen card")
equal(planned.journey, "zone:1", "planned: the chosen card")

local function area10(card)
	for _, step in ipairs(card.steps) do
		if step.key:find("^area:10:", 1) then
			return step.key
		end
	end
end

-- The nearer in-progress objective leads the nearest order; the far chapter pickup does not jump ahead of it.
local inProgress, farTown = area10(nearest), "town:5"
equal(inProgress ~= nil, true, "nearest: the in-progress objective is on the route")
equal(nth(nearest.steps, inProgress) < nth(nearest.steps, farTown), true, "nearest: nearer work before the far pickup")
-- The planned order still fronts the chapter's pickup.
equal(nth(planned.steps, farTown) < nth(planned.steps, inProgress), true, "planned: the chapter pickup leads")

-- In both orders a quest's pickup precedes its own objective, and its hand-in follows.
for _, case in ipairs({ { "nearest", nearest }, { "planned", planned } }) do
	local name, drawn = case[1], case[2]
	local pickup, objective, handin =
		nth(drawn.steps, farTown), nth(drawn.steps, "area:1:0"), nth(drawn.steps, "town:5:2")
	equal(pickup ~= nil and objective ~= nil, true, name .. ": the chapter's pickup and objective are drawn")
	equal(pickup < objective, true, name .. ": the pickup precedes its objective")
	equal(handin ~= nil and handin > objective, true, name .. ": the hand-in follows the objective")
end

-- The chapter frames the card in both orders, even when the nearest order places the pickup past the shown steps.
equal(nearest.journeys[1].subline, "Chapter 1 of 2", "nearest: the card still tells its chapter")
equal(planned.journeys[1].subline, "Chapter 1 of 2", "planned: the card tells its chapter")

-- The setting wiring: absent is the default nearest order; the opt-in flag is the planned (beta) order.
do
	local plain = dofile("tests/harness.lua").load({})
	equal(plain.ns.Setting("optimisedRoute"), false, "setting: default off")
	equal(plain.ns.Prefs().optimisedRoute, false, "setting: the planner reads nearest")
	local opted = dofile("tests/harness.lua").load({ planned = true })
	equal(opted.ns.Setting("optimisedRoute"), true, "setting: opt-in on")
	equal(opted.ns.Prefs().optimisedRoute, true, "setting: the planner reads planned")
end

print(("route_order_spec: %d checks passed"):format(checks))
