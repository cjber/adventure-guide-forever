-- Run from the repository root: luajit tests/model_spec.lua
local ns = {}
-- Core.lua for ns.L, the planner's copy; its load-time hooks into the client are stubbed, since only the copy is read.
local core = assert(loadfile("Core.lua"))
setfenv(
	core,
	setmetatable({
		EventUtil = { ContinueOnAddOnLoaded = function() end },
		SlashCmdList = {},
		CreateFrame = function()
			return { SetScript = function() end }
		end,
	}, { __index = _G })
)
core("AdventureGuideForever", ns)
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
-- Journeys (F2) are disjoint: carry holds the log, the zone's story its pickups; the first card is chosen by default.
local options = prefs()
local route = Model.Plan(data, player, {}, log, options)
local function Has(steps, key)
	local count = 0
	for _, step in ipairs(steps) do
		count = count + (step.key == key and 1 or 0)
	end
	return count
end
equal(route.journey, "carry", "carry is the first card")
equal(#route.journeys, 2, "carry and the zone's story")
equal(route.journeys[1].subline, "1 quest ready to hand in", "carry counts what is ready")
equal(route.journeys[1].reason, nil, "no reason unless a turn-in leads")
equal(route.journeys[1].map, route.steps[1].map, "a card turns the map to its first step")
for _, step in ipairs(route.steps) do
	equal(step.kind ~= "pickup", true, "carry holds no pickups: " .. step.key)
end
equal(Has(route.steps, "turnin:100"), 1, "the turn-in is carried")
options.journey = "story:1"
route = Model.Plan(data, player, {}, log, options)
equal(route.journey, "story:1", "the chosen card")
equal(route.journeys[2].title, "A Zone story", "the story is named after its zone")
equal(route.journeys[2].subline, "9 quests near your level", "the story counts its quests")
equal(#route.steps, 8, "one step per giver")
equal(route.steps[1].quests[1], 5, "the nearest step first")
for _, step in ipairs(route.steps) do
	equal(step.kind, "pickup", "the story holds pickups only")
end
options.journey = "gone"
equal(Model.Plan(data, player, {}, log, options).journey, "carry", "a vanished choice falls back to the first card")
local empty = prefs()
empty.quests = false
equal(#Model.Plan(data, player, {}, log, empty).journeys, 0, "activity filter")
local skip = prefs()
for _, step in ipairs(Model.Plan(data, player, {}, {}, prefs()).steps) do
	skip.skipped[step.key] = true
end
for _, journey in ipairs(Model.Plan(data, player, {}, log, skip).journeys) do
	for _, step in ipairs(journey.steps) do
		equal(skip.skipped[step.key], nil, "skipped steps removed")
	end
end
-- Pins keep their slot but are ordered by cost like every other step; a pickup pinned in another zone joins the story.
local pin = prefs()
pin.journey = "story:1"
local pins = {
	quests = { [10] = quest(0.9, 0.5, 2) },
	zones = { [1] = data.zones[1], [2] = { name = "Other", min = 30, max = 40 } },
}
for id = 1, 9 do
	pins.quests[id] = data.quests[id]
end
pin.pinned = { "pickup:2:0.9000:0.5000", "pickup:1:0.3000:0.5000", "pickup:2:0.9000:0.5000" }
local pinned = Model.Plan(pins, player, {}, log, pin)
equal(Has(pinned.steps, "pickup:2:0.9000:0.5000"), 1, "a pin keeps its slot, once")
equal(#pinned.steps, Model.MAX_STEPS, "pins count towards the cap")
equal(pinned.steps[#pinned.steps].key, "pickup:2:0.9000:0.5000", "the far pin is still ordered by cost")
equal(pinned.steps[#pinned.steps].pinned, true, "pin marker")
pin.skipped["pickup:2:0.9000:0.5000"] = true
equal(Has(Model.Plan(pins, player, {}, log, pin).steps, "pickup:2:0.9000:0.5000"), 0, "skip wins over pin")

-- The next-zone card: the zone that fits two levels on, when it is another zone with at least 5 quests open now.
-- Here has three quests at 18; There, which fits 20, has `count` at 20, the last opening at `min`.
local function Ahead(count, min)
	local zones = { [1] = { name = "Here", min = 16, max = 20 }, [2] = { name = "There", min = 20, max = 24 } }
	local ahead = { quests = {}, zones = zones }
	for id = 1, 3 do
		ahead.quests[id] = quest(id / 10, 0.5)
	end
	for id = 4, 3 + count do
		ahead.quests[id] = quest(id / 10, 0.5, 2)
		ahead.quests[id].level = 20
	end
	ahead.quests[3 + count].min = min or 10
	return ahead
end
local function Kinds(journeys)
	local kinds = {}
	for _, journey in ipairs(journeys) do
		kinds[#kinds + 1] = journey.key
	end
	return table.concat(kinds, " ")
end
local later = Model.Plan(Ahead(5), player, {}, {}, prefs())
equal(Kinds(later.journeys), "story:1 nextzone:2", "the next zone after the story")
equal(later.journeys[2].title, "Head to There at 20", "named for the level it fits")
equal(Kinds(Model.Plan(Ahead(4), player, {}, {}, prefs()).journeys), "story:1", "four quests are too few")
equal(Kinds(Model.Plan(Ahead(5, 20), player, {}, {}, prefs()).journeys), "story:1", "only quests open now count")
local there = prefs()
there.zone = 2
equal(Kinds(Model.Plan(Ahead(5), player, {}, {}, there).journeys), "story:2", "never the story's own zone")

local hub = { quests = { [1] = quest(0.1), [2] = quest(0.11) }, zones = data.zones }
local before = Model.Plan(hub, player, {}, {}, prefs()).steps[1]
local after = Model.Plan(hub, player, { [1] = true }, {}, prefs()).steps[1]
equal(#before.quests, 2, "cluster pickups")
equal(before.reason, "2 quests here", "cluster reason")
equal(before.key, after.key, "hub key survives quest completion")
equal(after.x, 0.11, "remaining known starter used")
local objectives = Model.Plan({ quests = {}, zones = {} }, player, {}, log, prefs())
equal(#objectives.steps, 2, "nearby objectives grouped; missing location omitted")
equal(#objectives.steps[1].quests, 2, "objective cluster membership, nearest first")
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
-- One cost in yards (F12): this continent by distance, then across the ocean, then a map with no geometry.
local tiers = { quests = {}, zones = data.zones, maps = {}, continents = { [0] = { x = 50000, y = 0 }, [1] = {} } }
tiers.continents[1] = { x = 0, y = 0 }
for id, place in ipairs({ { 7, 0.9 }, { 9, 0.1 }, { 3, 0.5 }, { 8, 0.2 } }) do
	tiers.quests[id] = quest(place[2], 0.5, place[1])
	tiers.quests[id].zone = 1
end
local function Map(continent, cx, cy, name)
	return { name = name, continent = continent, cx = cx, cy = cy, sx = 1000, sy = 1000 }
end
tiers.maps[1], tiers.maps[7], tiers.maps[8] = Map(1, 0, 0, "Home"), Map(1, 900, 0, "East"), Map(1, 300, 400, "North")
tiers.maps[9] = Map(0, 10, 0, "Far Shore")
local order = {}
for _, step in ipairs(Model.Plan(tiers, player, {}, {}, prefs()).steps) do
	order[#order + 1] = step.map
end
equal(table.concat(order, " "), "8 7 9 3", "this continent by distance, then over the sea, then no geometry")

-- A far turn-in never displaces a near step (F12): nine objectives here fill the route; with eight it comes last.
local function Objectives(count)
	local carried = {}
	for id = 1, count do
		carried[300 + id] =
			{ id = 300 + id, title = "Near", complete = false, level = 18, map = 1, x = 0.05 + id * 0.09, y = 0.5 }
	end
	carried[200] = { id = 200, title = "Over there", complete = true, level = 18, map = 9, x = 0.5, y = 0.5 }
	return carried
end
local shore = { quests = {}, zones = data.zones, maps = tiers.maps, continents = tiers.continents }
local full = Model.Plan(shore, player, {}, Objectives(9), prefs())
equal(#full.steps, Model.MAX_STEPS, "nine near objectives")
equal(Has(full.steps, "turnin:200"), 0, "the far turn-in waits for a free slot")
equal(full.journeys[1].subline, "1 quest ready to hand in", "but carry still counts it")
local room = Model.Plan(shore, player, {}, Objectives(8), prefs())
equal(room.steps[Model.MAX_STEPS].key, "turnin:200", "with room, the far turn-in comes last")
equal(room.steps[Model.MAX_STEPS].reason, "Hand in when you're in Far Shore", "and says where")
-- In an instance the player has no position: nothing measures from them, so the turn-in leads and is never dropped.
local lost = { level = player.level, side = player.side, raceBit = player.raceBit, classBit = player.classBit }
local blind = Model.Plan(shore, lost, {}, Objectives(9), prefs())
equal(blind.steps[1].key, "turnin:200", "without a position the turn-in leads")
equal(blind.journeys[1].reason, "Ready to hand in", "and gives the card its reason")
equal(#blind.steps, Model.MAX_STEPS, "and the objectives still fill the route")
-- Over the sea the route lands where the side's boat docks, not at the far shore's nearest point (F12).
local ferry = { quests = { quest(0.1, 0.5, 9), quest(0.9, 0.5, 9) }, zones = data.zones, maps = tiers.maps }
ferry.quests[1].zone, ferry.quests[2].zone, ferry.continents = 1, 1, tiers.continents
local dock = { continent = 0, x = 10, y = -400 } -- Far Shore's east end: map x 0.9
ferry.crossings = { { transport = 1, side = 2, a = { continent = 1, x = 0, y = 0 }, b = dock } }
equal(Model.Plan(ferry, player, {}, {}, prefs()).steps[1].key, "pickup:9:0.9000:0.5000", "lands at the dock")
ferry.crossings[1].side = 1
equal(Model.Plan(ferry, player, {}, {}, prefs()).steps[1].key, "pickup:9:0.1000:0.5000", "another side's boat")
local near = { quests = { [1] = quest(0.9), [2] = quest(0.4, 0.5, 8) }, zones = data.zones, maps = tiers.maps }
near.quests[2].zone = 1
equal(Model.Plan(near, player, {}, {}, prefs()).steps[1].map, 1, "the player's own map first")

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
