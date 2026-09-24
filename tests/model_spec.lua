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

local player = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
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
	return { quests = true, dungeons = false, skipped = {} }
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
data.quests[1].start.hub, data.quests[9].start.hub = 1, 1 -- one town by the data's hub, never by distance alone
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
equal(route.chosen, false, "with none chosen the route is the first card's, not a choice")
equal(#route.journeys, 2, "carry and the zone's story")
equal(route.journeys[1].subline, "1 ready to hand in, 2 in progress", "carry counts what is ready, then the rest")
equal(route.journeys[1].reason, nil, "no reason unless a turn-in leads")
equal(route.journeys[1].map, route.steps[1].map, "a card turns the map to its first step")
for _, step in ipairs(route.steps) do
	equal(#(step.pickups or {}), 0, "carry holds no pickups: " .. step.key)
end
equal(Has(route.steps, "turnin:100"), 1, "the turn-in is carried")
options.journey = "story:1"
route = Model.Plan(data, player, {}, log, options)
equal(route.journey, "story:1", "the chosen card")
equal(route.chosen, true, "and it is a choice")
equal(route.journeys[2].title, "Zone story", "the story is named after its zone")
equal(route.journeys[2].subline, "9 quests near your level", "the story counts its quests")
equal(#route.steps, 8, "one step per giver")
equal(route.steps[1].quests[1], 5, "the nearest step first")
for _, step in ipairs(route.steps) do
	equal(step.kind == "hub" and #step.handins == 0, true, "the story holds pickups only")
end
options.journey = "gone"
equal(Model.Plan(data, player, {}, log, options).journey, "carry", "a vanished choice falls back to the first card")
equal(Model.Plan(data, player, {}, log, options).chosen, false, "and reads as none chosen")
local empty = prefs()
empty.quests = false
local carriedOnly = Model.Plan(data, player, {}, log, empty).journeys
equal(#carriedOnly, 1, "the activity filter leaves only what you carry")
equal(carriedOnly[1] and carriedOnly[1].key, "carry", "the carry card stays with both filters off")
-- F15: a group quest in the log is never hidden by the dungeon filter, finished or under way.
data.quests[100], data.quests[101] = quest(), quest()
data.quests[100].elite, data.quests[101].dungeon = true, 36
local kept = Model.Plan(data, player, {}, log, prefs())
equal(kept.journey, "carry", "carry is chosen")
equal(Has(kept.steps, "turnin:100"), 1, "an elite turn-in shows with dungeons off")
equal(Has(kept.steps, "objective:101"), 1, "a dungeon quest under way shows with dungeons off")
data.quests[100], data.quests[101] = nil, nil
local skip = prefs()
for _, step in ipairs(Model.Plan(data, player, {}, {}, prefs()).steps) do
	skip.skipped[step.key] = true
end
for _, journey in ipairs(Model.Plan(data, player, {}, log, skip).journeys) do
	for _, step in ipairs(journey.steps) do
		equal(skip.skipped[step.key], nil, "skipped steps removed")
	end
end
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
equal(later.journeys[2].title, "Head to There", "named for its zone")
equal(later.journeys[2].reason, "For level 20", "the level it fits under the name")
local capped = { level = 18, maxLevel = 19, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
equal(Model.Plan(Ahead(5), capped, {}, {}, prefs()).journeys[2].reason, "For level 19", "never past the cap")
capped.maxLevel = 18
equal(Kinds(Model.Plan(Ahead(5), capped, {}, {}, prefs()).journeys), "story:1", "and none at the cap")
local standing = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 2, x = 0.5, y = 0.5 }
equal(Kinds(Model.Plan(Ahead(5), standing, {}, {}, prefs()).journeys), "story:1", "never the zone the player is in")
equal(Kinds(Model.Plan(Ahead(4), player, {}, {}, prefs()).journeys), "story:1", "four quests are too few")
equal(Kinds(Model.Plan(Ahead(5, 20), player, {}, {}, prefs()).journeys), "story:1", "only quests open now count")
-- At 22 There fits both now and two levels on; the next zone is never the story's own, and Here holds too few.
local later22 = { level = 22, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
equal(Kinds(Model.Plan(Ahead(5), later22, {}, {}, prefs()).journeys), "story:2", "never the story's own zone")

local hub = { quests = { [1] = quest(0.1), [2] = quest(0.11), [3] = quest(0.09) }, zones = data.zones }
hub.quests[1].start.hub, hub.quests[2].start.hub = 7, 7
local before = Model.Plan(hub, player, {}, {}, prefs()).steps[1]
local after = Model.Plan(hub, player, { [1] = true }, {}, prefs()).steps[1]
equal(#before.quests, 2, "one step per town")
equal(before.reason, "2 to pick up", "a town counts what it offers")
equal(before.title, "Quest giver", "an unnamed town takes its busiest giver's name")
equal(before.kind, "hub", "a town is a hub stop")
equal(#Model.Plan(hub, player, {}, {}, prefs()).steps, 2, "a giver nearby in no town of theirs is a step of its own")
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
equal(groups.steps[1].group, 1, "a group quest counts in its town")
equal(groups.steps[1].optional, true, "group optional marker")

local zones = { quests = {}, zones = {} }
for id = 1, 4 do
	zones.quests[id] = quest(0.5, 0.5, id)
	zones.quests[id].level = 17 + id
	zones.zones[id] = { name = "Zone " .. id, min = 10, max = 25 }
end
equal(Model.Plan(zones, player, {}, {}, prefs()).journeys[1].key, "story:1", "the story is the best level fit's")
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
equal(full.journeys[1].subline, "9 in progress", "carry counts the near objectives")
equal(full.journeys[1].reason, "1 to hand in across the sea", "and the far turn-in, never as ready")
local room = Model.Plan(shore, player, {}, Objectives(8), prefs())
equal(room.steps[Model.MAX_STEPS].key, "turnin:200", "with room, the far turn-in comes last")
equal(room.steps[Model.MAX_STEPS].reason, "Hand in when you're in Far Shore", "and says where")
-- In an instance the player has no position: nothing measures from them, so the turn-in leads and is never dropped.
local lost = {
	level = player.level,
	maxLevel = player.maxLevel,
	side = player.side,
	raceBit = player.raceBit,
	classBit = player.classBit,
}
local blind = Model.Plan(shore, lost, {}, Objectives(9), prefs())
equal(blind.steps[1].key, "turnin:200", "without a position the turn-in leads")
equal(blind.journeys[1].subline, "1 ready to hand in, 9 in progress", "unplaced, the turn-in counts as ready")
equal(blind.journeys[1].reason, nil, "and the card repeats nothing")
equal(#blind.steps, Model.MAX_STEPS, "and the objectives still fill the route")
-- Over the sea the route lands where the side's boat docks, not at the far shore's nearest point (F12).
local ferry = { quests = { quest(0.1, 0.5, 9), quest(0.9, 0.5, 9) }, zones = data.zones, maps = tiers.maps }
ferry.quests[1].zone, ferry.quests[2].zone, ferry.continents = 1, 1, tiers.continents
local dock = { continent = 0, x = 10, y = -400 } -- Far Shore's east end: map x 0.9
ferry.crossings = { { transport = 1, side = 2, a = { continent = 1, x = 0, y = 0 }, b = dock } }
equal(Model.Plan(ferry, player, {}, {}, prefs()).steps[1].key, "hub:9:0.9000:0.5000", "lands at the dock")
ferry.crossings[1].side = 1
equal(Model.Plan(ferry, player, {}, {}, prefs()).steps[1].key, "hub:9:0.1000:0.5000", "another side's boat")
local near = { quests = { [1] = quest(0.9), [2] = quest(0.4, 0.5, 8) }, zones = data.zones, maps = tiers.maps }
near.quests[2].zone = 1
equal(Model.Plan(near, player, {}, {}, prefs()).steps[1].map, 1, "the player's own map first")

-- Stories (F4): a chain from `next`, with a total only when the data proves where it ends.
local tale = { quests = {}, zones = data.zones }
for id = 1, 10 do
	tale.quests[id] = quest()
end
tale.quests[1].next, tale.quests[2].next = 2, 3 -- 1 > 2 > 3: proven
tale.quests[4].next, tale.quests[5].next = 5, 99 -- 4 > 5 > (missing)
tale.quests[6].next, tale.quests[7].next, tale.quests[8].next = 8, 8, 9 -- 6 and 7 both lead into 8 > 9
tale.quests[2].pre = { 1 }
local story = Model.Story(tale, 2)
equal(story and story.chapter, 2, "story: the chapter")
equal(story and story.total, 3, "story: a proven total")
equal(story and table.concat(story.members, " "), "1 2 3", "story: members from the head")
equal(Model.Story(tale, 2), story, "story: memoised")
equal(Model.Story(tale, 5).total, nil, "story: a dangling next proves no end")
equal(Model.Story(tale, 5).chapter, 2, "story: but the chapter stands")
equal(Model.Story(tale, 8), nil, "story: no chapter where the way back forks")
equal(Model.Story(tale, 9), nil, "story: nor after it")
equal(Model.Story(tale, 6).total, 3, "story: each head walks its own way through")
equal(Model.Story(tale, 10), nil, "story: a lone quest is no story")
equal(Model.Story(tale, 99), nil, "story: nor a quest the data lacks")
tale.quests[3].preAny = { 1, 4 }
tale = { quests = tale.quests, zones = tale.zones } -- a new data table: the memo is per data
equal(Model.Story(tale, 1).total, nil, "story: a preAny member proves nothing")

-- The story card (F4): the zone's chain the player can take up, its chapter in place of the count, and the step
-- that takes it up says so; one already started comes before one to begin.
local saga = { quests = {}, zones = data.zones }
for id = 1, 5 do
	saga.quests[id] = quest(id / 10, 0.5)
end
saga.quests[1].next, saga.quests[2].next, saga.quests[2].pre, saga.quests[3].pre = 2, 3, { 1 }, { 2 }
saga.quests[4].next = 5
local card = Model.Plan(saga, player, {}, {}, prefs()).journeys[1]
equal(card.subline, "Chapter 1 of 3", "story card: the longer chain to begin")
equal(card.reason, "Begins a new story", "story card: begins")
card = Model.Plan(saga, player, { [1] = true }, {}, prefs()).journeys[1]
equal(card.subline, "Chapter 2 of 3", "story card: a started chain first")
equal(card.reason, "Continues a story you started", "story card: continues")
equal(card.story.chapter, 2, "story card: carries its chain")
local lead
for _, step in ipairs(card.steps) do
	lead = step.quests[1] == 2 and step or lead
end
equal(lead and lead.chapter, "Chapter 2 of 3", "story card: its step tells the chapter")
equal(lead and lead.reason, "Continues a story you started", "story card: and why")
saga = { quests = saga.quests, zones = saga.zones } -- a new data table: Story's memo is per data
saga.quests[3].next = 99
equal(
	Model.Plan(saga, player, { [1] = true }, {}, { quests = true, skipped = {} }).journeys[1].subline,
	"Chapter 2",
	"story card: no total unproven"
)
-- Skipping the chapter's pickup leaves the card to the zone's count: no step on it takes the chain up.
local skipLead = prefs()
skipLead.skipped["hub:1:0.4000:0.5000"] = true
card = Model.Plan(saga, player, {}, {}, skipLead).journeys[1]
equal(card.subline, "3 quests near your level", "story card: a skipped chapter is no chapter")
equal(card.story == nil and card.reason == nil, true, "story card: nor its chain or reason")
-- The same in combat, where the cheap rebuild keeps the last card less the skipped step.
card = Model.Refresh(saga, player, {}, {}, skipLead, Model.Plan(saga, player, {}, {}, prefs())).journeys[1]
equal(card.subline, "3 quests near your level", "story card: a chapter skipped in combat is no chapter")
equal(card.story == nil and card.reason == nil, true, "story card: nor its chain or reason, in combat")
-- A pickup taken in combat leaves the cheap rebuild's cards at once, its chapter's chain with it as a skip's does.
local taken = { [4] = { id = 4, title = "Quest", level = 18, complete = false, map = 1, x = 0.4, y = 0.5 } }
local fought = Model.Refresh(saga, player, {}, taken, prefs(), Model.Plan(saga, player, {}, {}, prefs()))
local offered = {}
for _, journey in ipairs(fought.journeys) do
	for _, step in ipairs(journey.kind ~= "carry" and journey.steps or {}) do
		for _, id in ipairs(step.quests) do
			offered[id] = true
		end
	end
end
equal(offered[4], nil, "combat rebuild: a quest taken mid-fight is no longer a pickup")
equal(offered[1], true, "combat rebuild: the other pickups stay")
equal(fought.journeys[1].kind, "carry", "combat rebuild: the taken quest is carried")
equal(fought.journeys[2].story, nil, "combat rebuild: the taken chapter takes its chain with it")
-- A chapter 1 with a prerequisite of its own begins its story on the card and on its row alike.
local sequel = { quests = { [1] = quest(0.1), [2] = quest(0.2), [3] = quest(0.3) }, zones = data.zones }
sequel.quests[2].pre, sequel.quests[2].next, sequel.quests[3].pre = { 1 }, 3, { 2 }
card = Model.Plan(sequel, player, { [1] = true }, {}, prefs()).journeys[1]
equal(card.reason, "Begins a new story", "story card: a chapter 1 after another quest begins")
equal(card.steps[1].detail, "Begins a new story", "story card: and its row says the same")

-- Towns (docs/plan.md §7.2): one stop per hub merges its pickups and the hand-ins whose live waypoint agrees with the
-- data's finish, titled by the town's flight master; a waypoint elsewhere stays a turn-in of its own.
local function Town()
	local town = {
		quests = {},
		zones = data.zones,
		maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [0] = { x = 0, y = 0 } },
		hubs = { [5] = { name = "Lakeshire, Redridge" } },
	}
	for id, x in ipairs({ 0.5, 0.52, 0.54, 0.56 }) do
		town.quests[id] = quest(x, 0.5)
		town.quests[id].start.hub, town.quests[id].start.name = 5, id % 2 == 0 and "Marris" or "Osgood"
	end
	town.quests[4].elite = true
	for _, id in ipairs({ 10, 11, 12 }) do
		town.quests[id] = quest(0.9, 0.9)
		town.quests[id].finish = { map = 1, x = 0.58, y = 0.5, name = "Marris", hub = 5 }
	end
	return town
end
local function Carried()
	return {
		[10] = { id = 10, title = "Ten", complete = true, level = 18, map = 1, x = 0.6, y = 0.52 },
		[11] = { id = 11, title = "Eleven", complete = true, level = 18, map = 1, x = 0.58, y = 0.5 },
		[12] = { id = 12, title = "Twelve", complete = true, level = 18, map = 1, x = 0.9, y = 0.9 },
	}
end
local visitor = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.3, y = 0.5 }
local townPrefs = prefs()
townPrefs.dungeons, townPrefs.journey = true, "story:1"
local town = Town()
local toured = Model.Plan(town, visitor, {}, Carried(), townPrefs)
local stop = toured.steps[1]
equal(#toured.steps, 1, "town: one stop for the town")
equal(stop.key, "hub:5", "town: keyed by its hub")
equal(stop.detail, "2 to hand in, 4 to pick up", "town: counts both")
equal(stop.title, "Lakeshire, Redridge", "town: named by its flight master")
equal(table.concat(stop.quests, " "), "10 11 1 2 3 4", "town: hand-ins first, then by ID")
equal(table.concat(stop.givers, " "), "Marris Osgood", "town: its givers, once each")
equal(stop.group, 1, "town: the elite quest needs a group")
equal(stop.x, 0.5, "town: its point is the giver nearest the player, never a centre")
-- The card's hub line and group count (docs/plan.md §7.4): its first stop's place and the stops after it.
local function Chosen(plan)
	for _, journey in ipairs(plan.journeys) do
		if journey.key == plan.journey then
			return journey
		end
	end
end
local townCard = Chosen(toured)
equal(townCard.hub, "Lakeshire, Redridge", "card: the hub line names its first stop's place")
equal(townCard.more, #townCard.steps - 1, "card: and counts the stops after it")
equal(townCard.group, 1, "card: the elite quest needs a group")
local carriedCard = toured.journeys[1]
equal(Has(carriedCard.steps, "turnin:12"), 1, "town: a waypoint 350 yd from the data's finish stays a turn-in")
equal(carriedCard.steps[1].key, "handin:5", "town: the carry card's agreeing hand-ins share the town's stop")
equal(carriedCard.steps[1].detail, "2 to hand in", "town: and count as hand-ins")
equal(carriedCard.subline, "3 ready to hand in", "town: the carry card counts every hand-in")
-- A skip is the card's own: the carry card's town and the story card's are different stops.
local townSkip = prefs()
townSkip.dungeons, townSkip.journey = true, "story:1"
townSkip.skipped[carriedCard.steps[1].key] = true
local skippedTown = Model.Plan(town, visitor, {}, Carried(), townSkip)
equal(skippedTown.steps[1] and skippedTown.steps[1].key, "hub:5", "skip: the carry card's town leaves the story's")
equal(skippedTown.steps[1].detail, "2 to hand in, 4 to pick up", "skip: with its hand-ins")
townSkip.skipped = { ["hub:5"] = true }
skippedTown = Model.Plan(town, visitor, {}, Carried(), townSkip)
equal(skippedTown.journeys[1].steps[1].key, carriedCard.steps[1].key, "skip: the story's town leaves the carry card's")
equal(skippedTown.journeys[1].subline, "3 ready to hand in", "skip: and its count")
-- Each step's place and zone, for the "NPC, zone" line: the town's name, else its busiest giver; a turn-in names the
-- data's NPC only where its waypoint agrees with the data's finish; the zone is the client's map name, else the data's.
equal(stop.place, "Lakeshire, Redridge", "place: a unnamedPlan town")
equal(stop.zone, "Zone", "place: the data's map name without the client's")
local far
for _, step in ipairs(carriedCard.steps) do
	far = step.key == "turnin:12" and step or far
end
equal(far and far.place, nil, "place: no NPC for a waypoint away from the data's finish")
local unnamed = Town()
unnamed.hubs = nil
unnamed.quests[13] = quest(0.9, 0.9)
unnamed.quests[13].finish = { map = 1, x = 0.7, y = 0.5, name = "Verner" }
local ledger = Carried()
ledger[13] = { id = 13, title = "Thirteen", complete = true, level = 18, map = 1, x = 0.7, y = 0.55 }
local client = function(map)
	return map == 1 and "Les Carmines" or nil
end
local unnamedPlan = Model.Plan(unnamed, visitor, {}, ledger, townPrefs, client)
equal(unnamedPlan.steps[1].place, "Marris", "place: an unnamed town's busiest giver")
equal(unnamedPlan.steps[1].title, "Marris", "place: who titles the town")
equal(unnamedPlan.steps[1].zone, "Les Carmines", "place: the client's map name first")
local agreed
for _, step in ipairs(unnamedPlan.journeys[1].steps) do
	agreed = step.key == "turnin:13" and step or agreed
end
equal(agreed and agreed.place, "Verner", "place: a turn-in 50 yd from the data's finish names its NPC")
-- In combat a pickup taken and a quest handed in leave the town, which stays while it holds any.
local fight = Carried()
local takenHere = { id = 1, title = "Quest", complete = false, level = 18 }
fight[10], fight[1] = nil, takenHere
local foughtHere = Model.Refresh(town, visitor, { [10] = true }, fight, townPrefs, toured)
stop = foughtHere.steps[1]
equal(stop and stop.key, "hub:5", "town, combat: the stop stays")
equal(stop and stop.detail, "1 to hand in, 3 to pick up", "town, combat: recounted")
equal(stop and table.concat(stop.quests, " "), "11 2 3 4", "town, combat: less what went")
equal(stop and stop.x, 0.58, "town, combat: the point leaves a giver with nothing left")
local grouped = Carried()
grouped[4] = takenHere
equal(Chosen(Model.Refresh(town, visitor, {}, grouped, townPrefs, toured)).group, 0, "card, combat: recounts its group")
equal(toured.steps[1].detail, "2 to hand in, 4 to pick up", "town, combat: the last build is untouched")
local emptied = Model.Refresh(
	town,
	visitor,
	{ [10] = true, [11] = true, [12] = true },
	{ [1] = takenHere, [2] = takenHere, [3] = takenHere, [4] = takenHere },
	townPrefs,
	toured
)
equal(#emptied.steps, 0, "town, combat: an empty town goes")
-- Within a town: hand-ins first, then a quest grey at the next level, then nearest the player's level, then by ID; the
-- givers and the hand-in Show quest opens follow that order.
local levelled = Town()
levelled.quests[1].level, levelled.quests[2].level, levelled.quests[4].level = 20, 13, 17
local ledgered = Carried()
ledgered[11].level = 13
stop = Model.Plan(levelled, visitor, {}, ledgered, townPrefs).steps[1]
equal(table.concat(stop.quests, " "), "11 10 2 3 4 1", "town order: hand-ins, grey soon, level distance, ID")
equal(table.concat(stop.givers, " "), "Marris Osgood", "town order: givers as their quests come")
equal(stop.handins[1], 11, "town order: Show quest opens the hand-in grey soonest")
stop = Model.Plan(levelled, visitor, {}, {}, townPrefs).steps[1]
equal(table.concat(stop.quests, " "), "2 3 4 1", "town order: pickups only")
equal(table.concat(stop.givers, " "), "Marris Osgood", "town order: the grey-soon quest's giver first")
-- A hand-in whose next chapter starts in the same town says so, once Check proves that chapter open after it; the
-- chapter itself waits for the rebuild after the turn-in.
local chained = Town()
chained.quests[10].next = 30
chained.quests[30] = quest(0.52, 0.5)
chained.quests[30].start.hub, chained.quests[30].pre = 5, { 10 }
local handing = { [10] = Carried()[10] }
local chainPlan = Model.Plan(chained, visitor, {}, handing, townPrefs)
stop = chainPlan.steps[1]
equal(stop.reason, "Opens the next chapter here", "chain: the town says the hand-in opens the next chapter")
equal(stop.detail, "1 to hand in, 4 to pick up", "chain: and still counts its quests")
equal(table.concat(stop.pickups, " "), "1 2 3 4", "chain: the next chapter is no pickup before the turn-in")
local lone = chainPlan.journeys[1].steps[1]
equal(lone.key, "handin:5", "chain: the carry card's town")
equal(lone.detail, "Opens the next chapter here", "chain: a lone hand-in's row says it")
chained.quests[30].races = 1 -- Human only; the visitor is an Orc
stop = Model.Plan(chained, visitor, {}, handing, townPrefs).steps[1]
equal(stop.reason, "1 to hand in, 4 to pick up", "chain: nothing said when the next chapter is not the player's")
-- A next chapter the data gives no start (an item starts it) opens nowhere the town can claim.
chained.quests[30].races, chained.quests[30].start = nil, nil
chainPlan = Model.Plan(chained, visitor, {}, handing, townPrefs)
equal(chainPlan.steps[1].reason, "1 to hand in, 4 to pick up", "chain: nothing said when the next chapter has no start")
equal(chainPlan.journeys[1].steps[1].detail, "ready to hand in", "chain: nor on the carry card")
-- The data's `next` is display-only: a next chapter already open without the hand-in is not one it opens.
chained.quests[30].start, chained.quests[30].pre = quest(0.52, 0.5).start, nil
chained.quests[30].start.hub = 5
stop = Model.Plan(chained, visitor, {}, handing, townPrefs).steps[1]
equal(stop.reason, "1 to hand in, 5 to pick up", "chain: nothing said when the hand-in does not gate the next chapter")
-- One quest keeps the single step's title.
town.quests[2], town.quests[3], town.quests[4] = nil, nil, nil
town = { quests = town.quests, zones = town.zones, maps = town.maps, continents = town.continents, hubs = town.hubs }
stop = Model.Plan(town, visitor, {}, {}, townPrefs).steps[1]
equal(stop.title, "Pick up quests: Osgood", "town: a lone pickup keeps its title")

-- Selection weighs worth against travel (docs/plan.md §7.3); with one step to choose, the worth decides which.
local function Field()
	return {
		quests = {},
		zones = data.zones,
		maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [0] = { x = 0, y = 0 } },
	}
end
-- The keys of the steps `plan` returns with room for only `steps` of them.
local function Only(steps, plan)
	Model.MAX_STEPS = steps
	local ok, result = pcall(plan)
	Model.MAX_STEPS = 9
	assert(ok, result)
	local keys = {}
	for _, step in ipairs(result) do
		keys[#keys + 1] = step.key
	end
	return table.concat(keys, " ")
end
local field = Field()
field.quests[1] = quest(0.35, 0.5) -- 50 yd, a lone giver
for id = 2, 6 do -- 100 yd, five quests in one town
	field.quests[id] = quest(0.4, 0.5)
	field.quests[id].start.hub = 3
end
local function FieldSteps()
	return Model.Plan(field, visitor, {}, {}, prefs()).steps
end
equal(Only(1, FieldSteps), "hub:3", "value: a slightly farther five-quest town beats a nearer lone quest")
for id = 2, 6 do
	field.quests[id].start.x = 0.7
end
equal(Only(1, FieldSteps), "hub:1:0.3500:0.5000", "value: but not one 400 yd away")
local carrying = {
	[20] = { id = 20, title = "Normal", complete = false, level = 18, map = 1, x = 0.2, y = 0.5 },
	[21] = { id = 21, title = "Grey soon", complete = false, level = 13, map = 1, x = 0.4, y = 0.5 },
}
equal(
	Only(1, function()
		return Model.Plan(Field(), visitor, {}, carrying, prefs()).journeys[1].steps
	end),
	"objective:21",
	"value: a quest grey at the next level goes before an equidistant one"
)
-- A finished quest waits for nothing: a grey hand-in keeps its worth and goes before a nearer objective.
local finishing = {
	[30] = { id = 30, title = "Grey, done", complete = true, level = 10, map = 1, x = 0.4, y = 0.5 },
	[31] = { id = 31, title = "Under way", complete = false, level = 18, map = 1, x = 0.35, y = 0.5 },
}
equal(
	Only(1, function()
		return Model.Plan(Field(), visitor, {}, finishing, prefs()).journeys[1].steps
	end),
	"turnin:30",
	"value: a grey hand-in is never weak"
)
local red = Field()
red.quests[1], red.quests[2], red.quests[3] = quest(0.32, 0.5), quest(0.45, 0.5), quest(0.15, 0.5)
red.quests[1].level = 23
local function RedSteps()
	return Model.Plan(red, visitor, {}, {}, prefs()).steps
end
equal(Only(2, RedSteps):find("0.3200", 1, true), nil, "value: a stop of red quests only waits, though nearest")
equal(#RedSteps(), 3, "value: and is still on a route with room for it")

-- No zone the level fits (a city's quests only): no story card, and no error.
local city = { quests = { [1] = quest(0.5, 0.5, 9) }, zones = data.zones }
equal(#Model.Plan(city, player, {}, {}, prefs()).journeys, 0, "story card: none without a zone")

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
-- F15: quests filed under a dungeon or raid carry its instance Map.ID, and every such instance is named.
local flagged, raids = 0, 0
for _, q in pairs(ns.Data.quests) do
	if q.dungeon then
		flagged, raids = flagged + 1, raids + (q.raid and 1 or 0)
		assert(ns.Data.instances[q.dungeon].name ~= "", q.title)
	end
end
equal(flagged, 223, "dungeon and raid quests flagged")
equal(raids, 90, "raid quests flagged")

-- Story against an independent walk over every chain head in the data (F4 acceptance): a head is a quest with a
-- `next` that no quest's `next` names. The walker recurses where Model.Story loops, and asserts each total rule
-- on its own: no total on a chain that touches a dangling `next`, a `preAny` or a multi-`pre`.
local quests, named, heads = ns.Data.quests, {}, {}
for _, q in pairs(quests) do
	if q.next then
		named[q.next] = (named[q.next] or 0) + 1
	end
end
for id, q in pairs(quests) do
	if q.next and not named[id] then
		heads[#heads + 1] = id
	end
end
table.sort(heads)
local function Chain(id, members, seen)
	local q = quests[id]
	if not q then
		return members, "dangles"
	elseif seen[id] then
		return members, "loops"
	end
	seen[id], members[#members + 1] = true, id
	if q.preAny or (q.pre and #q.pre > 1) then
		local rest = Chain(q.next, members, seen)
		return rest, "gated"
	end
	if not q.next then
		return members, nil
	end
	return Chain(q.next, members, seen)
end
-- Pinned: the plan's pre-check estimated about 499 and 316; these are the design's three rules applied exactly.
local totals, textOnly = 0, 0
for _, head in ipairs(heads) do
	local members, flaw = Chain(head, {}, {})
	story = Model.Story(ns.Data, head)
	if #members < 2 then
		equal(story, nil, "walk: a head whose next dangles at once is no story " .. head)
	else
		equal(story.chapter, 1, "walk: a head is chapter 1 " .. head)
		equal(table.concat(story.members, " "), table.concat(members, " "), "walk: members " .. head)
		equal(story.total, (not flaw) and #members or nil, "walk: total " .. head .. " " .. tostring(flaw))
		totals, textOnly = totals + (story.total and 1 or 0), textOnly + (story.total and 0 or 1)
		-- A later member has its own story unless the way back to the head forks: two quests name it as next.
		local forked = false
		for index = 2, #members do
			local id = members[index]
			local member = Model.Story(ns.Data, id)
			forked = forked or named[id] > 1
			checks = checks + 1
			if forked then
				assert(member == nil, "walk: no chapter past a fork " .. id)
			else
				assert(member and member.chapter == index and member.members[1] == head, "walk: chapter of " .. id)
			end
		end
	end
end
equal(#heads, 815, "walk: chain heads in the data")
equal(totals, 581, "walk: heads whose total the data proves")
equal(textOnly, 226, "walk: heads shown as a chapter only")
equal(#heads - totals - textOnly, 8, "walk: heads whose next dangles at once")

-- Why-not and the planner never disagree (F5 acceptance): every quest, for each fixture character with completed
-- quests and a log (the first quests it could take moved into the log), is eligible exactly when every line is met.
local characters, mismatches, fixtures = dofile("tests/fixtures/characters.lua"), 0, 0
for _, fixture in ipairs(characters.list) do
	local who, done, carried = characters.Resolve(ns.Data, fixture)
	local moved, fresh = 0, next(done) == nil
	for id = 1, 10000 do
		if moved < 10 and Model.Eligible(ns.Data, who, done, carried, id) then
			-- A fixture with nothing done (human60) gets its first five done; the next five go in the log.
			if fresh and moved < 5 then
				done[id] = true
			else
				carried[id] = { id = id, title = "", complete = false, level = 1 }
			end
			moved = moved + 1
		end
	end
	assert(next(done) and next(carried), fixture.name .. ": completed quests and a log")
	fixtures = fixtures + 1
	for id in pairs(ns.Data.quests) do
		local all = true
		for _, line in ipairs(Model.Why(ns.Data, who, done, carried, id)) do
			all = all and line.met
		end
		mismatches = mismatches + (all == Model.Eligible(ns.Data, who, done, carried, id) and 0 or 1)
	end
end
equal(fixtures >= 5, true, "why: five fixtures or more")

-- F15: a dungeon card only with dungeons on, and never a step that is not an eligible giver's data place.
local function Valid(place)
	return place and place.map > 0 and place.x >= 0 and place.x <= 1 and place.y >= 0 and place.y <= 1
end
local cards, placeless, offCards = 0, 0, 0
for _, fixture in ipairs(characters.list) do
	local who, done, carried, cardPrefs = characters.Resolve(ns.Data, fixture)
	for _, dungeons in ipairs({ true, false }) do
		cardPrefs.dungeons = dungeons
		for _, journey in ipairs(Model.Plan(ns.Data, who, done, carried, cardPrefs).journeys) do
			if journey.kind == "dungeon" then
				cards, offCards = cards + 1, offCards + (dungeons and 0 or 1)
				for _, step in ipairs(journey.steps) do
					for _, id in ipairs(step.quests) do
						local given = ns.Data.quests[id]
						local fine = Valid(given.start)
							and not given.raid
							and Model.Eligible(ns.Data, who, done, carried, id)
						placeless = placeless + (fine and 0 or 1)
					end
				end
			end
		end
	end
end
equal(cards > 0, true, "dungeon card: offered to a fixture with dungeons on")
equal(placeless, 0, "dungeon card: every step an eligible giver with a data place")
equal(offCards, 0, "dungeon card: none with dungeons off")
-- The Deadmines card's title: the client's name when it has one (Spanish here), the data's when it answers nil.
local function DeadminesTitle(clientName)
	for _, fixture in ipairs(characters.list) do
		if fixture.name == "human18_westfall" then
			local who, done, carried, cardPrefs = characters.Resolve(ns.Data, fixture)
			local planned = Model.Plan(ns.Data, who, done, carried, cardPrefs, nil, function()
				return clientName
			end)
			for _, journey in ipairs(planned.journeys) do
				if journey.key == "dungeon:36" then
					return journey.title
				end
			end
		end
	end
end
equal(DeadminesTitle("Las Minas de la Muerte"), "Las Minas de la Muerte", "dungeon card: the client's name first")
equal(DeadminesTitle(nil), "Deadmines", "dungeon card: the data's name otherwise")
equal(mismatches, 0, "why: Eligible == every Why line met, for every quest and fixture")

-- The lines themselves: the design's copy, the client's names first, a suppressed start alone.
local horde = { level = 10, maxLevel = 60, side = 2, raceBit = 2, classBit = 1, map = 1, x = 0.5, y = 0.5 }
local q = ns.Data.quests[83] -- Red Linen Goods: Alliance races, level 4
local function Texts(lines)
	local out = {}
	for _, line in ipairs(lines) do
		out[#out + 1] = (line.met and "+ " or "- ") .. line.text
	end
	return table.concat(out, " | ")
end
equal(q.title, "Red Linen Goods", "why: the fixture quest")
equal(
	Texts(Model.Why(ns.Data, horde, {}, {}, 83)),
	"- Alliance only | + Requires level 4 | - Races: Human, Dwarf, Night Elf, Gnome",
	"why: side, level and races"
)
local names = {
	race = function(id)
		return id == 1 and "Humain" or nil
	end,
}
equal(
	Model.Why(ns.Data, horde, {}, {}, 83, names)[3].text,
	"Races: Humain, Dwarf, Night Elf, Gnome",
	"why: the client's names win"
)
local custom = { quests = { quest(), quest(), quest() }, zones = {} }
custom.quests[1].pre, custom.quests[1].preAny, custom.quests[1].classes = { 2 }, { 2, 3 }, 1
custom.quests[2].title, custom.quests[3].title = "First", "Second"
equal(
	Texts(Model.Why(custom, player, { [2] = true }, {}, 1)),
	"+ Horde only | + Requires level 10 | - Classes: Warrior | + Completed: First | + Requires one of: First, Second",
	"why: classes and prerequisites"
)
custom = { quests = custom.quests, zones = {} } -- a new data table: the index of groups is memoised per data
custom.quests[2].start, custom.quests[1].group, custom.quests[3].group = nil, 5, 5
equal(Texts(Model.Why(custom, player, {}, {}, 2)), "- The guide can't tell where this starts", "why: one line")
equal(
	Texts(Model.Why(custom, player, {}, { [1] = {} }, 3)),
	"+ Horde only | + Requires level 10 | - You chose Quest instead",
	"why: an exclusive choice"
)
equal(Texts(Model.Why(custom, player, { [3] = true }, {}, 3)):sub(1, 18), "- You've done this", "why: done")
local pair = { quests = { [1] = quest(), [2] = quest() }, zones = data.zones }
pair.quests[1].group, pair.quests[2].group = 7, 7
equal(
	Texts(Model.Why(pair, player, { [1] = true }, {}, 1)),
	"- You've done this | + Horde only | + Requires level 10",
	"why: a done choice is not its own rival"
)
equal(
	Texts(Model.Why(pair, player, { [1] = true }, {}, 2)),
	"+ Horde only | + Requires level 10 | - You chose Quest instead",
	"why: the other's"
)

-- F5 search: the player's side and both sides, a plain case-insensitive title match, by title then ID, 10 at most;
-- the client's title wins over the data's.
local wolves = { quests = {}, zones = {} }
for id = 1, 14 do
	wolves.quests[id] = quest()
	wolves.quests[id].title = "Wolf pack"
end
wolves.quests[13].title, wolves.quests[13].side = "A wolf hunt", 1
wolves.quests[14].title, wolves.quests[14].side = "Big wolf", 3
wolves.quests[5].title = "Sheep"
local found = Model.Search(wolves, player, "WOLF", function(id)
	return id == 12 and "Aardwolf" or nil
end)
equal(table.concat(found, " "), "12 14 1 2 3 4 6 7 8 9", "search: side, order and limit")
equal(#Model.Search(wolves, player, "wolf."), 0, "search: plain, not a pattern")
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
