local ns = {}
dofile("tests/harness.lua").model(ns)
local data = {
	quests = {},
	zones = { [1] = { name = "Zone", min = 10, max = 25 } },
	maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
	continents = { [0] = { x = 0, y = 0 } },
}
local log = {}
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
		obj = { { 0, x * 1000, 600, 10 } },
		xp = 1000,
	}
	log[id] = {
		id = id,
		title = "Quest " .. id,
		level = data.quests[id].level,
		complete = false,
		objectives = { { type = "monster", done = false, have = id == 1 and 3 or 0, need = 10 } },
	}
end
local player = { level = 19, maxLevel = 60, side = 1, raceBit = 1, classBit = 2, map = 1, x = 0.5, y = 0.5 }
local function first()
	local route = ns.Model.Plan(
		data,
		player,
		{},
		log,
		{ quests = true, dungeons = false, skipped = {}, journey = "zone:1" }
	)
	return route.steps[1]
end
assert(first().quests[1] == 2, "level 19: nearby green work beats a level 21 quest at 3/10")
log[1].objectives[1].have = 9
assert(first().quests[1] == 2, "near completion does not erase above-level difficulty")
data.quests[2].level, log[2].level = 21, 21
assert(first().quests[1] == 1, "equally difficult nearby work favours fewer remaining objectives")
log[1].complete = true
assert(first().kind == "turnin" and first().quests[1] == 1, "finished higher-level quests are safe to hand in")
print("difficulty_spec: ok")
