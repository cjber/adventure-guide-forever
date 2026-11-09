-- Run from the repository root: luajit tests/current_zone_card_spec.lua
-- The zone the player stands in gets its own next-zone card when the sticky lead keeps the story elsewhere (#552):
-- standing there no longer suppresses the card, and the story zone is never offered twice.
local ns = {}
dofile("tests/harness.lua").model(ns)
local Model, checks = ns.Model, 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function quest(map, x, level)
	return {
		title = "Quest",
		level = level,
		min = 10,
		side = 2,
		zone = map,
		start = { map = map, x = x, y = 0.5, name = "Quest giver" },
		finish = { map = map, x = x, y = 0.5, name = "Quest ender" },
	}
end

-- Two zones that both fit level 16: Here has three quests, There has six, so with no lead the ranking puts There
-- first.
local data = { quests = {}, zones = {} }
data.zones[1] = { name = "Here", min = 10, max = 20 }
data.zones[2] = { name = "There", min = 10, max = 20 }
for id = 1, 3 do
	data.quests[id] = quest(1, id / 10, 16)
end
for id = 4, 9 do
	data.quests[id] = quest(2, id / 10, 16)
end

local function player(level, map)
	return { level = level, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = map, x = 0.5, y = 0.5 }
end
local function prefs(lead)
	return { quests = true, dungeons = false, skipped = {}, optimisedRoute = true, lead = lead }
end
local function cards(route)
	local story, nextzone = nil, {}
	for _, journey in ipairs(route.journeys) do
		if journey.kind == "story" then
			story = journey.zone
		elseif journey.kind == "nextzone" then
			nextzone[journey.key] = true
		end
	end
	return story, nextzone
end

-- The lead keeps Here as the story while the player stands in There: There is still offered, exactly once.
local kept = Model.Plan(data, player(16, 2), {}, {}, prefs(1))
local story, nextzone = cards(kept)
equal(story, 1, "the lead keeps zone 1 as the story")
equal(nextzone["zone:1"], nil, "and zone 1 is not offered again")
equal(nextzone["zone:2"], true, "the zone the player stands in gets its own card")

-- With no lead, There is the story, so it has no next-zone card of its own.
local here = Model.Plan(data, player(16, 2), {}, {}, prefs())
story, nextzone = cards(here)
equal(story, 2, "with no lead the story is the zone the player stands in")
equal(nextzone["zone:2"], nil, "and that zone is not offered twice")

print(("current_zone_card_spec: %d checks"):format(checks))
