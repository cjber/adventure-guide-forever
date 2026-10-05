-- Run from the repository root: luajit tests/lead_spec.lua
-- The leading story zone is sticky (Planning/Journeys.lua): while the zone the story led with still has work, the next
-- build keeps it, even when another zone's ranking has just overtaken it. Two zones whose ranks trade places between
-- two plans must not move the lead; it moves only once the zone has nothing left.
local ns = {}
dofile("tests/harness.lua").model(ns)
local Model, checks = ns.Model, 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function quest(map, x, level, min)
	return {
		title = "Quest",
		level = level,
		min = min or 10,
		side = 2,
		zone = map,
		start = { map = map, x = x, y = 0.5, name = "Quest giver" },
		finish = { map = map, x = x, y = 0.5, name = "Quest ender" },
	}
end

-- Here fits level 18; There's quests open at 19 and its zone reaches higher, so There's ranking overtakes Here's
-- between the two builds. Here still has three quests a level on, so the story has work to stay for.
local data = { quests = {}, zones = {} }
data.zones[1] = { name = "Here", min = 16, max = 20 }
data.zones[2] = { name = "There", min = 18, max = 26 }
for id = 1, 3 do
	data.quests[id] = quest(1, id / 10, 18)
end
for id = 4, 9 do
	data.quests[id] = quest(2, id / 10, 19, 19)
end

local function player(level, map)
	return { level = level, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = map or 3, x = 0.5, y = 0.5 }
end
local function prefs()
	return { quests = true, dungeons = false, skipped = {}, optimisedRoute = true }
end
local function lead(route)
	local card = route.journeys[1]
	return card and card.kind == "story" and card.zone or nil
end

local first = Model.Plan(data, player(18, 1), {}, {}, prefs())
equal(lead(first), 1, "the story leads with Here at 18")
-- With no lead carried, the ranking now puts There first: the two zones have traded places.
local alone = Model.Plan(data, player(19), {}, {}, prefs())
equal(lead(alone), 2, "There's ranking overtakes Here's at 19 with no lead carried")
-- The next build keeps Here while it still has work, so the story does not flip back and forth.
local second = Model.Plan(data, player(19), {}, {}, prefs(), nil, nil, first)
equal(lead(second), 1, "the next build keeps Here")
equal(second.lead, 1, "the route carries the lead on")
-- Once Here has no work left, the lead moves on and the route carries the new zone.
local spent = { quests = {}, zones = data.zones }
spent.quests[4] = quest(2, 0.4, 19, 19)
local moved = Model.Plan(spent, player(19), {}, {}, prefs(), nil, nil, second)
equal(lead(moved), 2, "the lead moves once Here has nothing left")
equal(moved.lead, 2, "and the route carries the new lead")
equal(moved.left, 1, "Here is the zone the story left")

print(("lead_spec: %d checks"):format(checks))
