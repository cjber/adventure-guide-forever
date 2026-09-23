-- Run from the repository root: luajit tests/model_spec.lua
local ns = {}
assert(loadfile("Model.lua"))("AdventureGuideForever", ns)
local Model, checks = ns.Model, 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

for _, case in ipairs({
	{ 9, 4 },
	{ 10, 5 },
	{ 19, 5 },
	{ 20, 6 },
	{ 39, 7 },
	{ 40, 8 },
	{ 45, 9 },
	{ 50, 10 },
	{ 55, 11 },
	{ 60, 12 },
}) do
	equal(Model.IsGray(case[1] - case[2], case[1]), false, "green boundary " .. case[1])
	equal(Model.IsGray(case[1] - case[2] - 1, case[1]), true, "gray boundary " .. case[1])
end
equal(Model.IsGray(-1, 60), false, "scaling quest")

local player = { level = 18, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
local function quest(x, y, map)
	return {
		title = "Quest",
		level = 18,
		min = 10,
		side = 2,
		zone = map or 1,
		start = { map = map or 1, x = x or 0.5, y = y or 0.5, name = "Quest giver" },
		finish = { map = map or 1, x = 0.6, y = 0.5, name = "Quest ender" },
	}
end
local function prefs()
	return { quests = true, dungeons = false, legacy = false, professions = false, skipped = {}, pinned = {} }
end
local data = {
	build = "test",
	source = "fixture",
	quests = { [1] = quest() },
	zones = { [1] = { name = "Zone", min = 10, max = 20 } },
}
equal(Model.Eligible(data, player, {}, {}, 1), true, "ordinary eligible quest")
equal(Model.Eligible(data, player, { [1] = true }, {}, 1), false, "completed")
equal(Model.Eligible(data, player, {}, { [1] = {} }, 1), false, "already accepted")
equal(Model.Eligible(data, player, {}, {}, 99), false, "unknown ID")
for _, case in ipairs({
	{ "side", 1 },
	{ "min", 19 },
	{ "races", 1 },
	{ "classes", 1 },
	{ "repeatable", true },
	{ "start", false },
	{ "pre", { -2 } },
	{ "preAny", {} },
}) do
	local q = quest()
	q[case[1]] = case[2]
	local gated = { quests = { [1] = q }, zones = {} }
	equal(Model.Eligible(gated, player, {}, {}, 1), false, "eligibility gate " .. case[1])
end
local gated = quest()
gated.races, gated.classes, gated.pre, gated.preAny = 178, 64, { 2, 3 }, { 4, 5 }
local gates = { quests = { [1] = gated }, zones = {} }
equal(Model.Eligible(gates, player, { [2] = true, [3] = true, [5] = true }, {}, 1), true, "all and any prerequisites")

local gray, elsewhere = quest(0.2, 0.2), quest(0.5, 0.5, 2)
gray.level = 1
local offers =
	{ quests = { [1] = quest(), [2] = quest(), [3] = quest(0.2, 0.2), [4] = gray, [5] = elsewhere }, zones = {} }
local givers = Model.Givers(offers, player, { [3] = true }, {}, 1)
equal(#givers, 1, "one giver per NPC; gray, completed and other maps hidden")
equal(#givers[1].quests, 2, "an NPC's quests share one giver")
equal(givers[1].title, "Quest giver", "giver named after the NPC")
equal(Model.Eligible(gates, player, { [2] = true, [5] = true }, {}, 1), false, "missing all prerequisite")
equal(Model.Eligible(gates, player, { [2] = true, [3] = true }, {}, 1), false, "missing any prerequisite")
local a, b = quest(), quest()
a.group, b.group = 17, 17
local exclusive = { quests = { [1] = a, [2] = b }, zones = data.zones }
equal(Model.Eligible(exclusive, player, { [2] = true }, {}, 1), false, "completed exclusive sibling")
equal(Model.Eligible(exclusive, player, {}, { [2] = {} }, 1), false, "active exclusive sibling")
equal(#Model.Plan(exclusive, player, {}, {}, prefs()).steps[1].quests, 1, "recommend one exclusive choice")

data = { quests = {}, zones = {} }
for id = 1, 8 do
	data.quests[id] = quest(id / 10, 0.5)
end
data.zones[1] = { name = "Zone", min = 10, max = 20 }
data.quests[9] = quest(0.11, 0.5)
local log = {
	[100] = { id = 100, title = "Finished", complete = true, level = 18, map = 1, x = 0.9, y = 0.9 },
	[101] = { id = 101, title = "Unfinished", complete = false, level = 18, map = 1, x = 0.52, y = 0.5 },
	[102] = { id = 102, title = "Nearby", complete = false, level = 18, map = 1, x = 0.53, y = 0.5 },
	[103] = { id = 103, title = "Unknown location", complete = false, level = 18 },
}
local options = prefs()
local route = Model.Plan(data, player, {}, log, options)
equal(#route.steps, Model.MAX_STEPS, "step cap")
equal(route.steps[1].key, "turnin:100", "hand-ins first")
equal(route.steps[2].quests[1], 8, "greedy nearest pickup after turn-in")
equal(route.minutes, nil, "unknown travel does not invent minutes")
local empty = prefs()
empty.quests = false
equal(#Model.Plan(data, player, {}, log, empty).steps, 0, "activity filter")
local skip = prefs()
for _, step in ipairs(Model.Plan(data, player, {}, {}, prefs()).steps) do
	skip.skipped[step.key] = true
end
local remainder = Model.Plan(data, player, {}, log, skip)
for _, step in ipairs(remainder.steps) do
	equal(skip.skipped[step.key], nil, "skipped steps removed")
end
local pin = prefs()
pin.pinned = { route.steps[4].key, route.steps[3].key, route.steps[4].key }
local pinned = Model.Plan(data, player, {}, log, pin)
equal(pinned.steps[1].key, pin.pinned[1], "first pin")
equal(pinned.steps[2].key, pin.pinned[2], "second pin")
equal(pinned.steps[3].key, "turnin:100", "duplicate pin ignored")
equal(pinned.steps[1].pinned, true, "pin marker")
pin.skipped[pin.pinned[1]] = true
equal(Model.Plan(data, player, {}, log, pin).steps[1].key, pin.pinned[2], "skip wins over pin")

local hub = { quests = { [1] = quest(0.1), [2] = quest(0.11) }, zones = data.zones }
local before = Model.Plan(hub, player, {}, {}, prefs()).steps[1]
local after = Model.Plan(hub, player, { [1] = true }, {}, prefs()).steps[1]
equal(#before.quests, 2, "cluster pickups")
equal(before.reason, "2 quests here", "cluster reason")
equal(before.key, after.key, "hub key survives quest completion")
equal(after.x, 0.11, "remaining known starter used")
local objectives = Model.Plan({ quests = {}, zones = {} }, player, {}, log, prefs())
equal(#objectives.steps, 2, "nearby objectives grouped; missing location omitted")
equal(#objectives.steps[2].quests, 2, "objective cluster membership")
local withFinish = { quests = { [103] = quest() }, zones = data.zones }
local unknown = { [103] = log[103] }
equal(#Model.Plan(withFinish, player, {}, unknown, prefs()).steps, 0, "starter never becomes objective")
unknown[103].complete = true
equal(Model.Plan(withFinish, player, {}, unknown, prefs()).steps[1].x, 0.6, "bundled turn-in fallback")

local special = { quests = { [1] = quest(), [2] = quest(0.9) }, zones = data.zones }
special.quests[1].elite, special.quests[2].dungeon = true, 99
equal(#Model.Plan(special, player, {}, {}, prefs()).steps, 0, "group quests opt in")
local dungeon = prefs()
dungeon.quests, dungeon.dungeons = false, true
local groups = Model.Plan(special, player, {}, {}, dungeon)
equal(#groups.steps, 2, "dungeon-only activity")
equal(groups.steps[1].kind, "dungeon", "group kind")
equal(groups.steps[1].optional, true, "group optional marker")

local zones = { quests = {}, zones = {} }
for id = 1, 4 do
	zones.quests[id] = quest(0.5, 0.5, id)
	zones.quests[id].level = 17 + id
	zones.zones[id] = { name = "Zone " .. id, min = 10, max = 25 }
end
local choices = Model.Zones(zones, player, {}, {})
equal(#choices, 3, "top three zones")
equal(choices[1].map, 1, "best level fit first")
equal(choices[1].best, true, "best zone flag")
options.zone = 4
equal(Model.Plan(zones, player, {}, {}, options).steps[1].map, 4, "zone override beyond top three")
options.pinned = { Model.Plan(zones, player, {}, {}, prefs()).steps[1].key }
equal(Model.Plan(zones, player, {}, {}, options).steps[1].map, 1, "pinned pickup survives a zone change")
local travelData = { quests = { [1] = quest(0.5), [2] = quest(0.9) }, zones = data.zones }
local function travel(_, _, _, _, x)
	return x == 0.9 and 15 or 90
end
local timed = Model.Plan(travelData, player, {}, {}, prefs(), travel)
equal(timed.steps[1].quests[1], 2, "travel planner controls greedy order")
equal(timed.steps[1].seconds, 15, "seconds exposed")
equal(timed.minutes, 2, "total rounded minutes")
equal(
	Model.Plan(travelData, player, {}, {}, prefs(), function()
		return nil
	end).minutes,
	nil,
	"nil estimate fallback"
)

assert(loadfile("Data/Quests.lua"))("AdventureGuideForever", ns)
local count = 0
for id, q in pairs(ns.Data.quests) do
	count = count + 1
	assert(id > 0 and q.title and q.min >= 0 and q.side >= 1 and q.side <= 3)
	for _, place in pairs({ q.start, q.finish }) do
		assert(place.map > 0 and place.x >= 0 and place.x <= 1 and place.y >= 0 and place.y <= 1 and place.name)
	end
end
equal(count > 3000, true, "full dataset loaded")
player.map, player.x, player.y = 1413, 0.52, 0.3
local baseline = Model.Plan(ns.Data, player, {}, {}, prefs())
equal(#baseline.steps >= 3, true, "level 18 Horde route offers at least three steps")
local signature = {}
for _, step in ipairs(baseline.steps) do
	signature[#signature + 1] = step.key
end
for _ = 1, 100 do
	Model.Plan(ns.Data, player, {}, {}, prefs())
end
local started = os.clock()
for _ = 1, 1000 do
	Model.Plan(ns.Data, player, {}, {}, prefs())
end
local milliseconds = (os.clock() - started)
local rebuilt = Model.Plan(ns.Data, player, {}, {}, prefs())
for i, key in ipairs(signature) do
	equal(rebuilt.steps[i].key, key, "deterministic rebuild " .. i)
end
print(
	string.format("model_spec: %d checks passed; %d quests; warm Plan %.3f ms (1000 runs)", checks, count, milliseconds)
)
assert(milliseconds < 3, "warm full-data Plan exceeds 3 ms")
