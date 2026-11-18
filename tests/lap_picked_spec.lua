-- #852: the committed order keeps steps past the step limit, and the pickups they hold keep their log room, so a
-- rebuild with nothing changed is the same route (docs/design.md §4.3). A level 7 Tauren in Mulgore with a 5-quest
-- log: the first rebuild adds Bloodhoof Village and pushes Camp Narache's pickup past the limit.
local ns = {}
ns.Data = dofile("tests/harness.lua").data()
dofile("tests/harness.lua").model(ns)
local Model, data = ns.Model, ns.Data

local failures = 0
local function check(ok, message)
	if not ok then
		failures = failures + 1
		print("FAIL " .. message)
	end
end

local function Keys(route, journey)
	local keys = {}
	for _, step in ipairs(route.steps) do
		keys[#keys + 1] = step.key
	end
	return (route.journey == journey and "" or tostring(route.journey) .. "|") .. table.concat(keys, " ")
end

local player = {
	side = 2,
	map = 1412,
	x = 0.4618,
	y = 0.673,
	logMax = 5,
	level = 7,
	classBit = 1,
	maxLevel = 60,
	raceBit = 2,
}
local completed = {
	[376] = true,
	[8744] = true,
	[96379] = true,
	[787] = true,
	[752] = true,
	[788] = true,
	[60860] = true,
	[747] = true,
}
local prefs = { quests = true, dungeons = false, skipped = {}, optimisedRoute = true }

local first = Model.Plan(data, player, completed, {}, prefs)
local key = first.journey
check(key == "zone:1412", "Mulgore leads: " .. tostring(key))
local again = Model.Plan(data, player, completed, {}, prefs, nil, nil, first)
local order = again.orders[key]
local beyond = false
for index = Model.MAX_STEPS + 1, #order do
	beyond = beyond or order[index] == "town:1412:818"
end
check(beyond, "the rebuild's order holds town:1412:818 past the step limit")
check(order.picked[98430], "the order keeps 98430's log room, picked up past the step limit")
local route = Keys(again, key)
for build = 3, 5 do
	local next = Model.Plan(data, player, completed, {}, prefs, nil, nil, again)
	check(Keys(next, key) == route, "build " .. build .. " keeps the route:\n  " .. route .. "\n  " .. Keys(next, key))
	again = next
end

if failures > 0 then
	error(failures .. " failure(s)")
end
print("lap_picked_spec: ok")
