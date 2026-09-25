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
-- A breadcrumb is open only while the quest it leads to is neither done nor in the log.
local crumb = { quests = { [1] = quest(), [2] = quest(0.2, 0.2) }, zones = data.zones }
crumb.quests[1].breadcrumb = 2
equal(Model.Eligible(crumb, player, {}, {}, 1), true, "breadcrumb: open before its target")
equal(Model.Eligible(crumb, player, { [2] = true }, {}, 1), false, "breadcrumb: closed once its target is done")
equal(Model.Eligible(crumb, player, {}, { [2] = {} }, 1), false, "breadcrumb: closed while its target is in the log")
equal(#Model.Plan(crumb, player, {}, {}, prefs()).steps, 2, "breadcrumb: a pickup beside its target's")
do -- Missing In Action at 19: open from its minimum, but red, so never offered; the map's "!" still shows it.
	local fits, red, orange = quest(), quest(0.2, 0.2), quest(0.8, 0.8)
	fits.level = player.level + 2
	red.level, red.min, red.start.name = player.level + 5, player.level, "Corporal Keeshan"
	orange.level, orange.start.name = player.level + 3, "Orange giver"
	local camp = { quests = { [1] = fits, [2] = red, [3] = orange }, zones = data.zones }
	local offered = {}
	for _, step in ipairs(Model.Plan(camp, player, {}, {}, prefs()).steps) do
		for _, id in ipairs(step.quests) do
			offered[id] = true
		end
	end
	equal(offered[1], true, "a yellow quest, two levels up, is offered")
	equal(offered[2], nil, "a red quest is never offered")
	equal(offered[3], nil, "nor an orange one: too hard alone")
	equal(#Model.Givers(camp, player, {}, {}, 1), 3, "their givers still show on the map")
end

data = { quests = {}, zones = {} }
for id = 1, 8 do
	data.quests[id] = quest(id / 10, 0.5)
end
data.zones[1] = { name = "Zone", min = 10, max = 20 }
data.quests[9] = quest(0.11, 0.5)
data.quests[1].start.hub, data.quests[9].start.hub = 1, 1 -- one town by the data's hub, never by distance alone
local log = {
	[100] = { id = 100, title = "Finished", complete = true, level = 18, map = 2, x = 0.9, y = 0.9 },
	[101] = { id = 101, title = "Unfinished", complete = false, level = 18, map = 2, x = 0.52, y = 0.5 },
	[102] = { id = 102, title = "Nearby", complete = false, level = 18, map = 2, x = 0.53, y = 0.5 },
	[103] = { id = 103, title = "Unknown location", complete = false, level = 18 },
}
-- Journeys (F2) are disjoint: the zone's story leads with its pickups and the log's quests done on its map, carry
-- follows with the rest of the log (here all on another map); the first card is the route while none is chosen.
local options = prefs()
local route = Model.Plan(data, player, {}, log, options)
local function Has(steps, key)
	local count = 0
	for _, step in ipairs(steps) do
		count = count + (step.key == key and 1 or 0)
	end
	return count
end
equal(route.journey, "zone:1", "the story is the first card")
equal(route.chosen, false, "with none chosen the route is the first card's, not a choice")
equal(#route.journeys, 2, "the zone's story and carry")
do
	local carry = route.journeys[2]
	equal(carry.key, "carry", "carry follows the story")
	equal(carry.subline, "1 ready to hand in, 3 in progress", "carry counts every quest, placed or not")
	equal(carry.reason, nil, "no reason unless a turn-in leads")
	equal(carry.map, carry.steps[1].map, "a card turns the map to its first step")
	for _, step in ipairs(carry.steps) do
		equal(#(step.pickups or {}), 0, "carry holds no pickups: " .. step.key)
	end
	equal(Has(carry.steps, "turnin:100"), 1, "the turn-in is carried")
end
options.journey = "zone:1"
route = Model.Plan(data, player, {}, log, options)
equal(route.journey, "zone:1", "the chosen card")
equal(route.chosen, true, "and it is a choice")
equal(route.journeys[1].title, "Zone story", "the story is named after its zone")
equal(route.journeys[1].subline, "9 quests near your level", "the story counts its quests")
equal(#route.steps, 8, "one step per giver")
equal(route.steps[1].quests[1], 5, "the nearest step first")
for _, step in ipairs(route.steps) do
	equal(step.kind == "town" and #step.handins == 0, true, "the story holds no log quest off its map")
end
options.journey = "gone"
equal(Model.Plan(data, player, {}, log, options).journey, "zone:1", "a vanished choice falls back to the first card")
equal(Model.Plan(data, player, {}, log, options).chosen, false, "and reads as none chosen")
local empty = prefs()
empty.quests = false
local carriedOnly = Model.Plan(data, player, {}, log, empty).journeys
equal(#carriedOnly, 1, "the activity filter leaves only what you carry")
equal(carriedOnly[1] and carriedOnly[1].key, "carry", "the carry card stays with both filters off")
-- F15: a group quest in the log is never hidden by the dungeon filter, finished or under way.
data.quests[100], data.quests[101] = quest(), quest()
data.quests[100].elite, data.quests[101].dungeon = true, 36
do
	local kept = Model.Plan(data, player, {}, log, prefs()).journeys[2]
	equal(kept.key, "carry", "carry holds them")
	equal(Has(kept.steps, "turnin:100"), 1, "an elite turn-in shows with dungeons off")
	equal(Has(kept.steps, "area:101:0"), 1, "a dungeon quest under way shows with dungeons off")
end
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
-- The next-zone cards: the zones that fit two levels on, when another zone with at least 5 quests there then and 3 open
-- now.
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
equal(Kinds(later.journeys), "zone:1 zone:2", "the next zone after the story")
equal(later.journeys[2].title, "Head to There", "named for its zone")
equal(later.journeys[2].reason, "For level 20", "the level it fits under the name")
-- "Not interested" (roadmap #17): a zone so marked is never a card, chosen or not, and the next best takes its place.
local uninterested = prefs()
uninterested.notInterested = { ["zone:1"] = { title = "Here story" } }
equal(
	Kinds(Model.Plan(Ahead(5), player, {}, {}, uninterested).journeys),
	"zone:2",
	"not interested: the next zone steps up"
)
uninterested.journey = "zone:1"
equal(Kinds(Model.Plan(Ahead(5), player, {}, {}, uninterested).journeys), "zone:2", "not interested: even when chosen")
uninterested.notInterested = { ["zone:2"] = { title = "Head to There" } }
equal(Kinds(Model.Plan(Ahead(5), player, {}, {}, uninterested).journeys), "zone:1", "not interested: no next zone")
local wasOffered = Model.Plan(Ahead(5), player, {}, {}, prefs())
equal(
	Kinds(Model.Refresh(Ahead(5), player, {}, {}, uninterested, wasOffered).journeys),
	"zone:1",
	"not interested: in combat"
)
local capped = { level = 18, maxLevel = 19, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
equal(Model.Plan(Ahead(5), capped, {}, {}, prefs()).journeys[2].reason, "For level 19", "never past the cap")
-- At the cap the zones that fit now are still there to head to, with no level to name.
capped.maxLevel = 18
local capCards = Model.Plan(Ahead(5), capped, {}, {}, prefs()).journeys
equal(Kinds(capCards), "zone:1 zone:2", "at the cap, the zones that fit now")
equal(capCards[2].reason, nil, "and no level past the cap")
local standing = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 2, x = 0.5, y = 0.5 }
-- Standing in There, which fits too, makes it the story (design §2.10), and the next zone is never the zone you are in.
equal(Kinds(Model.Plan(Ahead(5), standing, {}, {}, prefs()).journeys), "zone:2", "the story is the zone you stand in")
-- A zone within the player's level range stays their story while they stand in it, though most of its quests are
-- already taken up and it ranks below the three that fit best.
local mostlyTaken = Ahead(5)
mostlyTaken.zones[3] = { name = "Taken", min = 15, max = 19 }
mostlyTaken.quests[20] = quest(0.5, 0.5, 3)
for map = 4, 6 do
	mostlyTaken.zones[map] = { name = "Busy " .. map, min = 16, max = 20 }
	for n = 1, 6 do
		mostlyTaken.quests[map * 100 + n] = quest(n / 10, 0.5, map)
	end
end
local inTaken = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 3, x = 0.5, y = 0.5 }
equal(
	Kinds(Model.Plan(mostlyTaken, inTaken, {}, {}, prefs()).journeys):match("^zone:3 "),
	"zone:3 ",
	"in range: its story"
)
inTaken.level = 20
equal(Kinds(Model.Plan(mostlyTaken, inTaken, {}, {}, prefs()).journeys):match("zone:3"), nil, "past its range: not")
local capital = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 9, x = 0.5, y = 0.5 }
equal(Kinds(Model.Plan(Ahead(5), capital, {}, {}, prefs()).journeys), "zone:1 zone:2", "a zone with none: level fit")
equal(Kinds(Model.Plan(Ahead(4), player, {}, {}, prefs()).journeys), "zone:1", "four quests are too few")
equal(Kinds(Model.Plan(Ahead(5, 20), player, {}, {}, prefs()).journeys), "zone:1 zone:2", "4 open now, 5 at 20")
local thin = Ahead(5, 20)
thin.quests[6].min, thin.quests[7].min = 20, 20
equal(Kinds(Model.Plan(thin, player, {}, {}, prefs()).journeys), "zone:1", "2 open now are too few")
-- At 22 There fits both now and two levels on; the next zone is never the story's own, and Here holds too few.
local later22 = { level = 22, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 3, x = 0.5, y = 0.5 }
equal(Kinds(Model.Plan(Ahead(5), later22, {}, {}, prefs()).journeys), "zone:2", "never the story's own zone")
later22.map = 1
equal(Kinds(Model.Plan(Ahead(5), later22, {}, {}, prefs()).journeys), "zone:1 zone:2", "in Here, There is next")
-- The offer rules only gate new choices (design §2.10): a chosen zone stays while it has a step.
local function Choose(key)
	local chosen = prefs()
	chosen.journey = key
	return chosen
end
equal(Kinds(Model.Plan(Ahead(4), player, {}, {}, Choose("zone:2")).journeys), "zone:1 zone:2", "chosen: under 5 quests")
local arrived = Model.Plan(Ahead(4), standing, {}, {}, Choose("zone:2"))
equal(Kinds(arrived.journeys), "zone:2", "chosen: standing in the zone it heads to")
equal(arrived.journeys[1].title, "There story", "chosen: which is now the zone's story")
equal(arrived.chosen, true, "chosen: and still chosen")
local away22 = { level = 22, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 3, x = 0.5, y = 0.5 }
local kept22 = Model.Plan(Ahead(5), away22, {}, {}, Choose("zone:1")).journeys
equal(Kinds(kept22), "zone:2 zone:1", "chosen: a level-up keeps the chosen zone")
equal(kept22[2].title, "Head to Here", "chosen: heading there")
-- The chosen dungeon stays with its instance while it has pickups, whichever has the most.
local halls = { quests = {}, zones = data.zones, instances = { [36] = { name = "Few" }, [48] = { name = "Many" } } }
for id = 1, 5 do
	halls.quests[id] = quest(id / 10, 0.5)
	halls.quests[id].dungeon = id <= 2 and 36 or 48
end
local delve = Choose("dungeon:36")
delve.quests, delve.dungeons = false, true
-- Roadmap #21: with no zone ahead and no story, dungeons off still leaves the dungeon card, not nothing.
equal(Kinds(Model.Plan(halls, player, {}, {}, prefs()).journeys), "dungeon:48", "stranded: dungeons off, a card")
delve.journey = nil
equal(Model.Plan(halls, player, {}, {}, delve).journeys[2].key, "dungeon:48", "chosen: unchosen, the most quests")
delve.journey = "dungeon:36"
equal(Model.Plan(halls, player, {}, {}, delve).journeys[2].key, "dungeon:36", "chosen: the chosen instance stays")
-- Not interested (roadmap #17) in the busier instance: the other takes its card.
delve.journey, delve.notInterested = nil, { ["dungeon:48"] = { title = "Many" } }
equal(Model.Plan(halls, player, {}, {}, delve).journeys[2].key, "dungeon:36", "not interested: the next dungeon")

do
	-- Roadmap #15: the dungeon card's reason counts the log's quests that end inside, and only those.
	local function Inside(entries)
		for _, journey in ipairs(Model.Plan(halls, player, {}, entries, delve).journeys) do
			if journey.key == "dungeon:36" then
				return journey.reason
			end
		end
	end
	delve.notInterested = nil
	halls.quests[6], halls.quests[7], halls.quests[8] = quest(0.6, 0.5), quest(0.7, 0.5), quest(0.8, 0.5)
	halls.quests[6].dungeon, halls.quests[7].dungeon, halls.quests[8].raid, halls.quests[8].dungeon = 36, 36, true, 36
	delve.journey = "dungeon:36"
	equal(Inside({}), nil, "inside: none carried, no reason")
	equal(Inside({ [6] = { id = 6, level = 18 } }), "1 of your quests ends inside Few", "inside: one")
	equal(
		Inside({
			[6] = { id = 6, level = 18 },
			[7] = { id = 7, level = 18 },
			[8] = { id = 8, level = 18 },
			[3] = { id = 3 },
		}),
		"2 of your quests end inside Few",
		"inside: two, never a raid's or another dungeon's"
	)
	halls.quests[6], halls.quests[7], halls.quests[8], delve.journey = nil, nil, nil, nil

	-- Roadmap #21: at the cap there is no level ahead, so the dungeon card comes without the Dungeons toggle and a chain
	-- that leads into an instance is a story, after the zones that fit now. Here holds the story; on a map with no zone,
	-- 50 leads to 51 inside the Hall.
	local function Stranded()
		local fixture = Ahead(5)
		fixture.instances = { [36] = { name = "Hall" } }
		fixture.quests[50], fixture.quests[51] = quest(0.2, 0.5, 3), quest(0.3, 0.5, 3)
		fixture.quests[50].next, fixture.quests[51].pre, fixture.quests[51].dungeon = 51, { 50 }, 36
		fixture.quests[52] = quest(0.4, 0.5, 3)
		fixture.quests[52].dungeon = 36
		return fixture
	end
	local atCap = { level = 18, maxLevel = 18, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
	local stranded = Model.Plan(Stranded(), atCap, {}, {}, prefs())
	equal(
		Kinds(stranded.journeys),
		"zone:1 zone:2 dungeon:36 chain:50",
		"at the cap: the dungeon and the way in, toggle off"
	)
	equal(stranded.stranded, true, "at the cap: stranded")
	local way = stranded.journeys[4]
	equal(way.kind .. " · " .. way.title, "story · The way into Hall", "the way in: a story named for the instance")
	equal(way.subline .. " · " .. way.reason, "Chapter 1 of 2 · Begins a new story", "the way in: its chapter")
	local onward = Model.Plan(Stranded(), atCap, { [50] = true }, {}, prefs())
	equal(Kinds(onward.journeys), "zone:1 zone:2 dungeon:36 chain:50", "the way in: its next chapter is inside")
	equal(onward.journeys[4].reason, "Continues a story you started", "the way in: continues")
	equal(onward.journeys[3].subline, "2 quests for this dungeon", "at the cap: every instance quest open now")
	local roomy = Model.Plan(Stranded(), player, {}, {}, prefs())
	equal(Kinds(roomy.journeys), "zone:1 zone:2", "below the cap with a next zone: neither")
	equal(roomy.stranded, nil, "below the cap: not stranded")
	equal(
		Kinds(Model.Plan(Stranded(), player, {}, {}, Choose("chain:50")).journeys),
		"zone:1 zone:2 chain:50",
		"chosen"
	)
	local wayOff = prefs()
	wayOff.notInterested = { ["chain:50"] = "The way into Hall" }
	equal(
		Kinds(Model.Plan(Stranded(), atCap, {}, {}, wayOff).journeys),
		"zone:1 zone:2 dungeon:36",
		"not interested: the way in"
	)
	local unnamed = Stranded()
	unnamed.instances = {}
	equal(
		Kinds(Model.Plan(unnamed, atCap, {}, {}, prefs()).journeys),
		"zone:1 zone:2",
		"an instance the data can't name: neither"
	)
	-- The story's own chain is never offered twice: in Here, 1 leads to 2 inside the Hall.
	local ownChain = Stranded()
	ownChain.quests[1].next, ownChain.quests[2].pre, ownChain.quests[2].dungeon = 2, { 1 }, 36
	local told = Model.Plan(ownChain, atCap, {}, {}, prefs())
	equal(Kinds(told.journeys), "zone:1 zone:2 dungeon:36 chain:50", "the story's chain: the story's alone")
	equal(told.journeys[1].subline, "Chapter 1 of 2", "the story's chain: it leads the story")
end

-- The diversions (roadmap R4): the story, carry and the zones to head to keep their slots; the calling, a dungeon and a
-- battleground share the rest, the one whose newest quest opened at the highest level first, then in that order on a
-- tie. Here's story holds 1-3; There holds 4-8 (a zone to head to); the Hall 9-10 and the calling 11 are on a map with
-- no zone of their own. Four cards here, so one slot is left to share.
local function Diversions(nextMin, hallMin, callingMin)
	local fixture = { quests = {}, zones = Ahead(0).zones, instances = { [36] = { name = "Hall" } } }
	for id = 1, 3 do
		fixture.quests[id] = quest(id / 10, 0.5)
	end
	for id = 4, 8 do
		fixture.quests[id] = quest(id / 10, 0.5, 2)
		fixture.quests[id].level = 20
	end
	fixture.quests[8].min = nextMin
	for id = 9, 10 do
		fixture.quests[id] = quest(id / 20, 0.5, 3)
		fixture.quests[id].dungeon, fixture.quests[id].min = 36, hallMin
	end
	fixture.quests[11] = quest(0.9, 0.5, 3)
	fixture.quests[11].classes, fixture.quests[11].min = 64, callingMin
	fixture.quests[100] = quest()
	return fixture
end
local both = prefs()
both.dungeons = true
local inLog = { [100] = { id = 100, title = "Carried", level = 18, complete = true, map = 3, x = 0.5, y = 0.5 } }
local function Diverted(fixture, choices, entries)
	return Kinds(Model.Plan(fixture, player, {}, entries or {}, choices).journeys)
end
local sixCards = Model.MAX_JOURNEYS
Model.MAX_JOURNEYS = 4
equal(
	Diverted(Diversions(10, 10, 10), both),
	"zone:1 zone:2 calling dungeon:36",
	"diversions: a tie, the calling first"
)
equal(Diverted(Diversions(18, 10, 10), both), "zone:1 zone:2 calling dungeon:36", "diversions: after the zones")
equal(Diverted(Diversions(18, 10, 10), both, inLog), "zone:1 carry zone:2 calling", "diversions: carry leaves one slot")
equal(
	Diverted(Diversions(16, 17, 10), both, inLog),
	"zone:1 carry zone:2 dungeon:36",
	"diversions: a dungeon just opened"
)
equal(Diverted(Diversions(16, 17, 18), both, inLog), "zone:1 carry zone:2 calling", "diversions: a calling just opened")
local hall = prefs()
hall.dungeons, hall.journey = true, "dungeon:36"
equal(
	Diverted(Diversions(18, 10, 10), hall, inLog),
	"zone:1 carry zone:2 dungeon:36",
	"diversions: the chosen one stays"
)
equal(Diverted(Diversions(18, 10, 10), prefs(), inLog), "zone:1 carry zone:2 calling", "diversions: dungeons off")
local combat = Model.Plan(Diversions(10, 10, 18), player, {}, {}, both)
equal(
	Kinds(Model.Refresh(Diversions(10, 10, 18), player, {}, inLog, both, combat).journeys),
	"zone:1 carry zone:2 calling",
	"diversions: in combat a new carry card pushes out the last"
)
Model.MAX_JOURNEYS = sixCards

-- Your calling (roadmap #7): the class quests open now as one card, its reason naming the quest it leads with.
local function Calling(fixture, completed, choices)
	for _, journey in ipairs(Model.Plan(fixture, player, completed or {}, {}, choices or prefs()).journeys) do
		if journey.kind == "calling" then
			return journey
		end
	end
end
local task = Calling(Diversions(10, 10, 10))
equal(task.key, "calling", "calling: its key")
equal(task.title, "Your calling", "calling: its title")
equal(task.subline, "1 quest for your class", "calling: counts its quests")
equal(task.reason, "A task for your class: Quest", "calling: from a giver the data doesn't call a trainer")
local trained = Diversions(10, 10, 10)
trained.quests[11].start.trainer = 7
equal(Calling(trained).reason, "Your class trainer has a task: Quest", "calling: the player's class trainer")
trained.quests[11].start.trainer = 1
equal(Calling(trained).reason, "A task for your class: Quest", "calling: another class's trainer is no trainer here")
local every = Diversions(10, 10, 10)
every.quests[11].classes = 1 + 2 + 4 + 8 + 16 + 64 + 128 + 256 + 1024
equal(Calling(every), nil, "calling: a quest for every class is no calling")
local several = Diversions(10, 10, 10)
several.quests[11].classes = 1 + 2 + 4 + 8 + 16 + 64 + 128 + 1024
equal(Calling(several), nil, "calling: a quest for every class but one is no calling")
local raid = Diversions(10, 10, 10)
raid.quests[11].dungeon, raid.quests[11].raid = 36, true
equal(Calling(raid, nil, both), nil, "calling: never a raid's quest")
-- No zone card offers a raid's quest either (F15), outdoors or in, whatever it's filed under, nor ranks a zone by one.
local function Offered(journeys, id)
	for _, journey in ipairs(journeys) do
		for _, step in ipairs(journey.steps) do
			for _, questID in ipairs(step.quests) do
				if questID == id then
					return journey.key
				end
			end
		end
	end
end
local raidQuests = Diversions(10, 10, 10)
raidQuests.quests[12], raidQuests.quests[13] = quest(0.95, 0.5), quest(0.95, 0.5, 2)
raidQuests.quests[12].dungeon, raidQuests.quests[12].raid = 36, true
raidQuests.quests[13].elite, raidQuests.quests[13].raid = true, true
local raidPlan = Model.Plan(raidQuests, player, {}, {}, both).journeys
equal(Offered(raidPlan, 12), nil, "raid: never on the story, filed under an instance")
equal(Offered(raidPlan, 13), nil, "raid: nor on the next zone, typed a raid outdoors")
equal(Offered(raidPlan, 1), "zone:1", "raid: the story's own quests stay")
local raidOnly = { quests = {}, zones = Ahead(0).zones }
for id = 1, 6 do
	raidOnly.quests[id] = quest(id / 10, 0.5, 2)
	raidOnly.quests[id].raid = id > 1
end
raidOnly.quests[7] = quest(0.5, 0.5)
equal(Kinds(Model.Plan(raidOnly, player, {}, {}, both).journeys), "zone:1", "raid: never ranks a zone")
local other = Diversions(10, 10, 10)
other.quests[11].classes = 1
equal(Calling(other), nil, "calling: another class's quest")
local nothanks = prefs()
nothanks.notInterested = { calling = { title = "Your calling" } }
equal(Calling(Diversions(10, 10, 10), nil, nothanks), nil, "calling: not interested")
local noquests = prefs()
noquests.quests = false
equal(Calling(Diversions(10, 10, 10), nil, noquests), nil, "calling: quests off")
-- Chapters follow the story rules (docs/design.md §2.3).
local chain = Diversions(10, 10, 10)
chain.quests[11].next = 12
chain.quests[12] = quest(0.8, 0.5, 3)
chain.quests[12].classes, chain.quests[12].pre = 64, { 11 }
local begun = Calling(chain)
equal(begun.subline, "Chapter 1 of 2", "calling: a chain's chapter")
equal(begun.story and begun.story.chapter, 1, "calling: its track")
equal(begun.steps[1].reason, "Begins a new story", "calling: its step begins the chain")
local went = Calling(chain, { [11] = true })
equal(went.subline, "Chapter 2 of 2", "calling: the next chapter")
equal(went.steps[1].reason, "Continues a story you started", "calling: and continues it")

local hub = { quests = { [1] = quest(0.1), [2] = quest(0.11), [3] = quest(0.09) }, zones = data.zones }
hub.quests[1].start.hub, hub.quests[2].start.hub = 7, 7
local before = Model.Plan(hub, player, {}, {}, prefs()).steps[1]
local after = Model.Plan(hub, player, { [1] = true }, {}, prefs()).steps[1]
equal(#before.quests, 2, "one step per town")
equal(before.reason, "2 to pick up", "a town counts what it offers")
equal(before.title, "Quest giver", "an unnamed town takes its busiest giver's name")
equal(before.kind, "town", "a town is a visit")
equal(#Model.Plan(hub, player, {}, {}, prefs()).steps, 2, "a giver nearby in no town of theirs is a step of its own")
equal(before.key, after.key, "a town's key survives quest completion")
equal(after.x, 0.11, "remaining known starter used")
local objectives = Model.Plan({ quests = {}, zones = {} }, player, {}, log, prefs())
equal(#objectives.steps, 2, "nearby objectives grouped; missing location omitted")
do
	local cluster
	for _, step in ipairs(objectives.steps) do
		cluster = cluster or (step.key == "area:101:0" and step or nil)
	end
	equal(cluster and #cluster.quests, 2, "objective cluster membership, lowest ID's key")
	equal(cluster and cluster.kind, "area", "an area visit")
end
local withFinish = { quests = { [103] = quest() }, zones = data.zones }
local unknown = { [103] = log[103] }
equal(#Model.Plan(withFinish, player, {}, unknown, prefs()).steps, 0, "starter never becomes objective")
unknown[103].complete = true
equal(Model.Plan(withFinish, player, {}, unknown, prefs()).steps[1].x, 0.6, "bundled turn-in fallback")

-- A quest under way (the live client gives it no waypoint) is done at the data's area for each open objective: the
-- client's objectives fill the data's need slots by type, kills and uses 0-3, collects 4-7, explores 16, each kind in
-- order, trusted only when the counts agree. The client's point for the quest stands in when they don't, or the data
-- places no open objective. Nothing placed, it has no step and still counts.
do
	local areas = { quests = { [1] = quest(), [2] = quest(), [3] = quest() }, zones = data.zones }
	areas.quests[1].need = { [0] = 5, [4] = 3 }
	areas.quests[1].obj = { { 0, 200, 300, 40 }, { 4, 700, 800, 0 }, { 4, 710, 810, 0, 2 } }
	areas.quests[2].need, areas.quests[2].obj = { [16] = 1 }, { { 16, 400, 400, 0 } }
	local function At(entry, id)
		local underway = { [id or 1] = entry }
		entry.id, entry.title, entry.level, entry.complete = id or 1, "Under way", 18, false
		for _, journey in
			ipairs(Model.Plan(areas, player, { [1] = true, [2] = true, [3] = true }, underway, prefs()).journeys)
		do
			for _, step in ipairs(journey.steps) do
				if step.quests[1] == (id or 1) then
					return ("%d %.3f,%.3f"):format(step.map, step.x, step.y), journey, step
				end
			end
		end
	end
	local kill, collect, event, unslotted =
		{ type = "monster", done = true, have = 5, need = 5 },
		{ type = "item", done = false, have = 1, need = 3 },
		{ type = "event", done = false, have = 0, need = 1 },
		{ type = "log", done = false, have = 0, need = 1 }
	local where, _, first = At({})
	equal(where, "1 0.200,0.300", "area: the lowest open slot's first area, with no objectives read")
	equal(first.key, "area:1:0", "area: keyed by its first quest and slot")
	equal(first.r, 40, "area: its ring is its area's")
	equal(At({ objectives = { collect, kill } }), "1 0.700,0.800", "area: the kill done, the collect's first area")
	equal(At({ objectives = { kill } }), "1 0.200,0.300", "area: counts that disagree leave every slot open")
	equal(At({ objectives = { unslotted, kill } }), "1 0.200,0.300", "area: a type with no slot leaves every slot open")
	equal(At({ objectives = { event } }, 2), "1 0.400,0.400", "area: an explore fills slot 16")
	equal(
		At({ objectives = { collect, kill }, poi = { map = 1, x = 0.3, y = 0.6 } }),
		"1 0.700,0.800",
		"area: objectives that line up keep the data's area over the client's point"
	)
	equal(
		At({ objectives = { kill }, poi = { map = 1, x = 0.3, y = 0.6 } }),
		"1 0.300,0.600",
		"area: the client's point wins when they don't"
	)
	equal(At({ map = 1, x = 0.9, y = 0.1 }), "1 0.900,0.100", "area: as does a waypoint, when the client gives one")
	local _, journey = At({}, 3)
	equal(journey, nil, "area: a quest the data places nowhere has no step")
end

-- Each open objective is an area visit of its own, and areas that nearly touch merge, the lowest quest's and slot's
-- key naming the visit and its ring wide enough for all of them. Each objective keeps the client's count and words when
-- they line up, and the town its quest is handed in at.
do
	local fields = { quests = { [1] = quest(), [2] = quest(), [3] = quest() }, zones = data.zones }
	fields.maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } }
	fields.continents = { [0] = { x = 0, y = 0 } }
	fields.quests[1].need = { [0] = 8, [4] = 5 }
	fields.quests[1].obj = { { 0, 200, 500, 40 }, { 4, 700, 500, 30 } }
	fields.quests[1].finish = { map = 1, x = 0.6, y = 0.5, name = "Ender", hub = 9 }
	fields.quests[2].need, fields.quests[2].obj = { [0] = 10 }, { { 0, 250, 500, 30 } } -- 50 yd from 1's kills
	fields.quests[3].need, fields.quests[3].obj = { [4] = 4 }, { { 4, 350, 500, 0 } } -- 150 yd off: its own
	local kill = { type = "monster", done = false, have = 3, need = 8, text = "Gnoll slain: 3/8" }
	local loot = { type = "item", done = false, have = 1, need = 5, text = "" }
	local carried = {
		[1] = { id = 1, title = "Both", level = 18, complete = false, objectives = { kill, loot } },
		[2] = { id = 2, title = "Near", level = 18, complete = false },
		[3] = { id = 3, title = "Apart", level = 18, complete = false },
	}
	local done = { [1] = true, [2] = true, [3] = true }
	local plan = Model.Plan(fields, player, done, carried, prefs())
	-- A lap goes out once: an area of a later lap waits on the story, which counts its quest.
	local byKey = {}
	for _, journey in ipairs(plan.journeys) do
		for _, step in ipairs(journey.steps) do
			byKey[step.key] = byKey[step.key] or step
		end
	end
	local shared, loots = byKey["area:1:0"], byKey["area:1:4"]
	local apart = Model.Plan(fields, player, done, { [3] = carried[3] }, prefs()).steps[1]
	equal(shared and shared.kind, "area", "areas: the kills, an area visit")
	equal(shared and table.concat(shared.quests, " "), "1 2", "areas: the nearby quest joins it")
	equal(shared and shared.reason, "2 quests here", "areas: counts its quests")
	equal(shared and #shared.objectives, 2, "areas: one objective each")
	local mine, theirs = shared.objectives[1], shared.objectives[2]
	equal(mine.id .. " " .. mine.slot .. " " .. mine.have .. "/" .. mine.need, "1 0 3/8", "areas: the client's count")
	equal(mine.text, "Gnoll slain: 3/8", "areas: and its words")
	equal(mine.finish, "town:9", "areas: the town it is handed in at")
	equal(theirs.id .. " " .. tostring(theirs.have) .. "/" .. theirs.need, "2 nil/10", "areas: else the data's count")
	equal(theirs.finish, "town:1:0.6000:0.5000", "areas: a hand-in in no town is a town of its own")
	equal(math.floor(shared.r + 0.5), 80, "areas: the ring covers both, 50 yd off with 30 yd of its own")
	equal(loots and loots.quests[1], 1, "areas: the collect, another visit for the same quest")
	equal(loots and loots.objectives[1].text, nil, "areas: no empty words")
	equal(apart and apart.key, "area:3:4", "areas: a quest 150 yd off is its own visit")
	equal(apart and apart.r, 0, "areas: a single point's ring")
	-- The story's lap takes 1 and 2, and 3 waits for the lap after: the story counts all three, and no carry card.
	local counts = {}
	for _, journey in ipairs(plan.journeys) do
		counts[#counts + 1] = journey.subline
	end
	equal(table.concat(counts, " | "), "3 in progress, 1 of them on later laps", "areas: the story counts each quest")
	-- In combat an area keeps its objectives of the quests still carried, and recounts.
	local fought = { [1] = carried[1], [3] = carried[3] }
	local refreshed = Model.Refresh(fields, player, done, fought, prefs(), plan)
	local kept
	for _, step in ipairs(refreshed.journeys[1].steps) do
		kept = step.key == "area:1:0" and step or kept
	end
	equal(kept and #kept.objectives, 1, "areas, combat: the objective of a quest gone goes")
	equal(kept and kept.reason, "quests in progress", "areas, combat: recounted")
	equal(#shared.objectives, 2, "areas, combat: the last build is untouched")
end

-- The zone the player stands in leads when they carry its quests, though nothing is left there to pick up and another
-- zone's pickups rank better; carry holds the rest of the log.
do
	local world = {
		quests = {},
		zones = { [1] = { name = "Here", min = 15, max = 25 }, [2] = { name = "There", min = 17, max = 19 } },
	}
	for id = 1, 6 do
		world.quests[id] = quest(id / 10, 0.5, id <= 3 and 1 or 2)
		world.quests[id].need, world.quests[id].obj = { [0] = 1 }, { { 0, id * 100, 500, 0 } }
	end
	world.quests[7] = quest(0.5, 0.5, 3)
	local carried, done = {}, { [1] = true, [2] = true, [3] = true }
	for _, id in ipairs({ 1, 2, 3, 7 }) do
		carried[id], done[id] = { id = id, title = "Carried", level = 18, complete = false }, nil
	end
	local here = Model.Plan(world, player, done, carried, prefs())
	equal(here.journeys[1].key, "zone:1", "standing: the zone you carry quests in is card 1")
	equal(here.journeys[1].subline, "3 in progress", "standing: its card counts them")
	equal(here.journeys[2] and here.journeys[2].key, nil, "standing: nothing else placed, no carry card")
	carried[7].complete = true
	here = Model.Plan(world, player, done, carried, prefs())
	equal(here.journeys[2] and here.journeys[2].subline, "1 ready to hand in", "standing: carry holds the rest")
end

local special = { quests = { [1] = quest(), [2] = quest(0.9), [3] = quest(0.1) }, zones = data.zones }
special.quests[1].elite, special.quests[2].dungeon = true, 99
-- Roadmap #16: an outdoor elite is a zone's quest (optional, badged); only an instance's quest waits behind Dungeons.
local outdoor = Model.Plan(special, player, {}, {}, prefs())
local elite
for _, step in ipairs(outdoor.steps) do
	equal(step.quests[1] ~= 2, true, "the instance quest waits behind Dungeons")
	elite = step.quests[1] == 1 and step or elite
end
equal(#outdoor.steps, 2, "an outdoor elite shows with dungeons off, beside the zone's solo quest")
equal(elite ~= nil and elite.group, 1, "badged for a group")
equal(elite.optional, true, "and optional")
-- Being optional, an outdoor elite never picks the zone: a zone with only elites open has no card.
local elitesOnly = { quests = { [1] = quest() }, zones = data.zones }
elitesOnly.quests[1].elite = true
equal(#Model.Plan(elitesOnly, player, {}, {}, prefs()).journeys, 0, "an elite alone never draws a zone card")
local dungeon = prefs()
dungeon.quests, dungeon.dungeons = false, true
local groups = Model.Plan(special, player, {}, {}, dungeon)
equal(#groups.steps, 1, "dungeon-only activity holds the instance quest alone")
equal(groups.steps[1].quests[1], 2, "not the outdoor elite")
equal(groups.steps[1].group, 1, "a group quest counts in its town")
equal(groups.steps[1].optional, true, "group optional marker")

local zones = { quests = {}, zones = {} }
for id = 1, 4 do
	zones.quests[id] = quest(0.5, 0.5, id)
	zones.quests[id].level = 17 + id
	zones.zones[id] = { name = "Zone " .. id, min = 10, max = 25 }
end
equal(Model.Plan(zones, player, {}, {}, prefs()).journeys[1].key, "zone:1", "the story is the best level fit's")
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
equal(Model.Plan(ferry, player, {}, {}, prefs()).steps[1].key, "town:9:0.9000:0.5000", "lands at the dock")
ferry.crossings[1].side = 1
equal(Model.Plan(ferry, player, {}, {}, prefs()).steps[1].key, "town:9:0.1000:0.5000", "another side's boat")
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
equal(card.reason, "A chain begins with Quest giver", "story card: begins, with the giver the data names")
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
-- World-voiced reasons (roadmap #3), one per card, by priority: a started story, then quests about to turn grey (two
-- or more), then the chain's giver, then a named first town with three pickups; else the plain line.
do
	local function Voice(quests, completed, hubs, level)
		local world = { quests = quests, zones = data.zones, hubs = hubs }
		local at =
			{ level = level or 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
		return Model.Plan(world, at, completed or {}, {}, prefs()).journeys[1]
	end
	local function Town(count, level)
		local quests = {}
		for id = 1, count do
			quests[id] = quest(0.5, 0.5)
			quests[id].start.hub, quests[id].level = 7, level or 18
		end
		return quests
	end
	local sentinel = { [7] = { name = "Sentinel Hill, Westfall" } }
	equal(Voice(Town(3), nil, sentinel).reason, "Sentinel Hill needs hands", "voice: a named town with three pickups")
	equal(Voice(Town(2), nil, sentinel).reason, nil, "voice: two are no call for hands")
	equal(Voice(Town(3)).reason, nil, "voice: a town the data doesn't name says nothing")
	equal(Voice(Town(3), nil, { [7] = { name = "Crossroads" } }).reason, "Crossroads needs hands", "voice: a lone name")
	-- At 20 a level-14 quest is green and grey at 21 (the green range grows at 20).
	equal(
		Voice(Town(3, 14), nil, sentinel, 20).reason,
		"3 quests will soon turn grey",
		"voice: grey risk before a town"
	)
	-- At the level cap no quest turns grey: there is no next level.
	equal(Voice(Town(3, 48), nil, sentinel, 60).reason, "Sentinel Hill needs hands", "voice: no grey risk at the cap")
	local lone = Town(3, 14)
	lone[2].level, lone[3].level = 20, 20
	equal(Voice(lone, nil, sentinel, 20).reason, "Sentinel Hill needs hands", "voice: one going grey is not enough")
	local chained = Town(3, 14)
	chained[1].next, chained[2].pre, chained[1].start.name = 2, { 1 }, "Gryan Stoutmantle"
	equal(Voice(chained, nil, sentinel, 20).reason, "2 quests will soon turn grey", "voice: grey risk before the giver")
	equal(
		Voice(chained, nil, sentinel).reason,
		"A chain begins with Gryan Stoutmantle",
		"voice: the giver before a town"
	)
	equal(
		Voice(chained, { [1] = true }, sentinel, 20).reason,
		"Continues a story you started",
		"voice: a started story first"
	)
	chained[1].start.name = ""
	equal(Voice(chained, nil, sentinel).reason, "Begins a new story", "voice: an unnamed giver keeps the plain line")
	-- The next-zone card speaks the same way, and keeps its level otherwise.
	local bound = Ahead(5)
	bound.hubs = { [2] = { name = "Sentinel Hill, Westfall" } }
	for id = 4, 8 do
		bound.quests[id].start.hub = 2
	end
	equal(
		Model.Plan(bound, player, {}, {}, prefs()).journeys[2].reason,
		"Sentinel Hill needs hands",
		"voice: next zone"
	)
end
-- Skipping the chapter's pickup leaves the card to the zone's count: no step on it takes the chain up.
local skipLead = prefs()
skipLead.skipped["town:1:0.4000:0.5000"] = true
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
equal(fought.journeys[2].kind, "carry", "combat rebuild: the taken quest is carried until the full build")
equal(fought.journeys[1].story, nil, "combat rebuild: the taken chapter takes its chain with it")
-- A chapter 1 with a prerequisite of its own begins its story on the card and on its row alike.
local sequel = { quests = { [1] = quest(0.1), [2] = quest(0.2), [3] = quest(0.3) }, zones = data.zones }
sequel.quests[2].pre, sequel.quests[2].next, sequel.quests[3].pre = { 1 }, 3, { 2 }
card = Model.Plan(sequel, player, { [1] = true }, {}, prefs()).journeys[1]
equal(card.reason, "A chain begins with Quest giver", "story card: a chapter 1 after another quest begins")
equal(card.steps[1].detail, "Begins a new story", "story card: and its row says it begins too")

-- Towns (docs/plan.md §7.2): one stop per hub merges its pickups and the hand-ins whose live waypoint agrees with the
-- data's finish, titled by the town's flight master; a waypoint elsewhere stays a turn-in of its own. The log's quests
-- here are handed in on the story's zone, so its card holds them: there is no carry card.
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
townPrefs.dungeons, townPrefs.journey = true, "zone:1"
local town = Town()
local toured = Model.Plan(town, visitor, {}, Carried(), townPrefs)
local stop = toured.steps[1]
equal(#toured.steps, 2, "town: one stop for the town, the far turn-in apart")
equal(stop.key, "town:5", "town: keyed by its hub")
equal(stop.detail, "2 to hand in, 4 to pick up", "town: counts both")
equal(stop.title, "Lakeshire, Redridge", "town: named by its flight master")
equal(table.concat(stop.quests, " "), "10 11 1 2 3 4", "town: hand-ins first, then by ID")
equal(table.concat(stop.givers, " "), "Marris Osgood", "town: its givers, once each")
equal(stop.group, 1, "town: the elite quest needs a group")
equal(stop.optional, nil, "town: one elite quest never dims the whole town")
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
equal(Has(toured.steps, "turnin:12"), 1, "town: a waypoint 350 yd from the data's finish stays a turn-in")
equal(#toured.journeys, 1, "town: no carry card, the story holds the log")
equal(townCard.subline, "3 ready to hand in, 4 quests near your level", "town: the story counts every hand-in first")
-- Skipping the town takes its hand-ins with it, from the route and the count.
local townSkip = prefs()
townSkip.dungeons, townSkip.journey, townSkip.skipped = true, "zone:1", { ["town:5"] = true }
local skippedTown = Model.Plan(town, visitor, {}, Carried(), townSkip)
equal(skippedTown.steps[1] and skippedTown.steps[1].key, "turnin:12", "skip: the far turn-in is left")
equal(Chosen(skippedTown).subline, "1 ready to hand in, 4 quests near your level", "skip: and its count")
-- Each step's place and zone, for the "NPC, zone" line: the town's name, else its busiest giver; a turn-in names the
-- data's NPC only where its waypoint agrees with the data's finish; the zone is the client's map name, else the data's.
equal(stop.place, "Lakeshire, Redridge", "place: a unnamedPlan town")
equal(stop.zone, "Zone", "place: the data's map name without the client's")
local far
for _, step in ipairs(toured.steps) do
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
equal(stop and stop.key, "town:5", "town, combat: the stop stays")
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
local eliteLeft = Model.Refresh(
	town,
	visitor,
	{ [10] = true, [11] = true, [12] = true },
	{ [1] = takenHere, [2] = takenHere, [3] = takenHere },
	townPrefs,
	toured
)
equal(eliteLeft.steps[1] and eliteLeft.steps[1].optional, true, "town, combat: optional once only the elite is left")
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
equal(table.concat(stop.follow, " "), "30", "chain: the town follows its hand-in with the chapter it opens")
chained.quests[30].races = 1 -- Human only; the visitor is an Orc
stop = Model.Plan(chained, visitor, {}, handing, townPrefs).steps[1]
equal(stop.reason, "1 to hand in, 4 to pick up", "chain: nothing said when the next chapter is not the player's")
equal(#stop.follow, 0, "chain: and nothing follows")
-- A next chapter the data gives no start (an item starts it) opens nowhere the town can claim.
chained.quests[30].races, chained.quests[30].start = nil, nil
chainPlan = Model.Plan(chained, visitor, {}, handing, townPrefs)
equal(chainPlan.steps[1].reason, "1 to hand in, 4 to pick up", "chain: nothing said when the next chapter has no start")
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
equal(Only(1, FieldSteps), "town:3", "value: a slightly farther five-quest town beats a nearer lone quest")
for id = 2, 6 do
	field.quests[id].start.x = 0.7
end
equal(Only(1, FieldSteps), "town:1:0.3500:0.5000", "value: but not one 400 yd away")
local carrying = {
	[20] = { id = 20, title = "Normal", complete = false, level = 18, map = 1, x = 0.2, y = 0.5 },
	[21] = { id = 21, title = "Grey soon", complete = false, level = 13, map = 1, x = 0.4, y = 0.5 },
}
equal(
	Only(1, function()
		return Model.Plan(Field(), visitor, {}, carrying, prefs()).journeys[1].steps
	end),
	"area:21:0",
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
equal(Only(2, RedSteps):find("0.3200", 1, true), nil, "value: a red quest is never first, though nearest")
equal(#RedSteps(), 2, "value: nor on the route at all")

-- Laps (docs/design.md §4.3): the story's town hands out its quests, the lap goes out to their areas and comes back to
-- hand them in, a second visit keyed ":2". A quest worth far less per yard than the town's others waits, and the log's
-- limit caps the pickups, the best worth per yard first.
do
	local lapped = {
		quests = {},
		zones = data.zones,
		maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [0] = { x = 0, y = 0 } },
		hubs = { [5] = { name = "Lakeshire, Redridge" } },
	}
	for id, spot in ipairs({ { 560, 500 }, { 500, 600 }, { 470, 600 }, { 900, 900 } }) do
		local given = quest(0.5, 0.5)
		given.start.hub, given.finish = 5, { map = 1, x = 0.5, y = 0.5, name = "Quest giver", hub = 5 }
		given.xp, given.need, given.obj = 1000 - id * 10, { [0] = 5 }, { { 0, spot[1], spot[2], 20 } }
		lapped.quests[id] = given
	end
	lapped.quests[4].xp = 100 -- 550 yd off for a tenth of the XP
	local walker = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.45, y = 0.5 }
	local function Keys(steps)
		local keys = {}
		for _, step in ipairs(steps) do
			keys[#keys + 1] = step.key
		end
		return table.concat(keys, " ")
	end
	local steps = Model.Plan(lapped, walker, {}, {}, Choose("zone:1")).steps
	equal(steps[1].key, "town:5", "laps: the town first")
	equal(table.concat(steps[1].pickups, " "), "1 2 3", "laps: its quests, less the one worth little per yard")
	equal(steps[#steps].key, "town:5:2", "laps: back to the town, a second visit")
	equal(table.concat(steps[#steps].handins, " "), "1 2 3", "laps: handing in what the lap did")
	equal(steps[#steps].reason, "3 to hand in", "laps: counted as hand-ins")
	equal(Keys(steps), "town:5 area:2:0 area:1:0 town:5:2", "laps: the town, the areas (2 and 3's merged), the town")
	walker.logMax = 2
	steps = Model.Plan(lapped, walker, {}, {}, Choose("zone:1")).steps
	-- 2 and 3 share an area, so each costs less than 1.
	equal(table.concat(steps[1].pickups, " "), "2 3", "laps, full log: as many as the log takes, best per yard")
	equal(Keys(steps), "town:5 area:2:0 town:5:2", "laps, full log: only their area")
	local held = { [9] = { id = 9, title = "Held", level = 18, complete = false } }
	walker.logMax = 1
	steps = Model.Plan(lapped, walker, {}, held, Choose("zone:1")).steps
	equal(steps[1] and steps[1].pickups and #steps[1].pickups, nil, "laps, log full: nothing to pick up")
end

-- No zone the level fits (a city's quests only): no story card, and no error.
local city = { quests = { [1] = quest(0.5, 0.5, 9) }, zones = data.zones }
equal(#Model.Plan(city, player, {}, {}, prefs()).journeys, 0, "story card: none without a zone")

-- Roadmap #5 (R3): a chosen journey's route stops to train only in a town it passes anyway (a stop's hub, or within
-- 100 yards of one), once, at a trainer who teaches the player's spells to train; the step has no quests.
local academy = {
	quests = {},
	zones = data.zones,
	maps = tiers.maps,
	continents = tiers.continents,
	hubs = { [5] = { name = "Crossroads, The Barrens" } },
	npcs = {
		[900] = { class = 7, upto = 60, side = 2, place = { map = 1, x = 0.52, y = 0.5, name = "Trainer", hub = 5 } },
		[901] = { class = 7, upto = 60, side = 2, place = { map = 1, x = 0.53, y = 0.5, name = "Neighbour", hub = 5 } },
		[902] = { class = 7, upto = 60, side = 2, place = { map = 1, x = 0.2, y = 0.5, name = "Elsewhere", hub = 6 } },
		[903] = { class = 7, upto = 60, side = 2, place = { map = 1, x = 0.45, y = 0.5, name = "Townless" } },
		[904] = {
			class = 7,
			upto = 60,
			from = 20,
			side = 2,
			place = { map = 1, x = 0.5, y = 0.5, name = "Portals", hub = 5 },
		},
		[905] = { class = 7, upto = 6, side = 2, place = { map = 1, x = 0.5, y = 0.5, name = "Novices", hub = 5 } },
		[906] = { class = 8, upto = 60, side = 2, place = { map = 1, x = 0.5, y = 0.5, name = "Mage", hub = 5 } },
		[907] = { class = 7, upto = 60, side = 1, place = { map = 1, x = 0.5, y = 0.5, name = "Alliance", hub = 5 } },
	},
}
for id = 1, 3 do
	academy.quests[id] = quest(0.5 + id / 1000)
	academy.quests[id].start.hub = 5
end
local trainee = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.3, y = 0.5 }
trainee.train = { count = 2, level = 18 }
local function Trainers(steps)
	local found = {}
	for _, step in ipairs(steps) do
		found[#found + 1] = step.kind == "trainer" and step or nil
	end
	return found
end
local schooled = Model.Plan(academy, trainee, {}, {}, Choose("zone:1"))
local lesson = Trainers(schooled.steps)
equal(#lesson, 1, "trainer: one stop, in the town the route passes")
equal(lesson[1].key, "trainer:900", "trainer: the town's first trainer who teaches the spells")
equal(lesson[1].title, "Train in Crossroads", "trainer: titled by its town")
equal(lesson[1].reason .. "|" .. lesson[1].detail, "2 new spells|2 new spells", "trainer: the spells waiting")
equal(lesson[1].place .. "|" .. lesson[1].zone, "Trainer|Home", "trainer: the NPC and the zone")
equal(#lesson[1].quests, 0, "trainer: no quests")
equal(#schooled.steps, 2, "trainer: beside the town's stop")
equal(#Trainers(Model.Plan(academy, trainee, {}, {}, prefs()).steps), 0, "trainer: no journey chosen, no stop")
equal(#Trainers(Model.Plan(academy, player, {}, {}, Choose("zone:1")).steps), 0, "trainer: nothing to train")
local skipTrainer = Choose("zone:1")
skipTrainer.skipped["trainer:900"] = true
equal(#Trainers(Model.Plan(academy, trainee, {}, {}, skipTrainer).steps), 0, "trainer: skipped, none")
-- Without the two, the town's others teach portals only, novices only, another class, or the other side.
local taught = { academy.npcs[900], academy.npcs[901] }
academy.npcs[900], academy.npcs[901], trainee.train.level = nil, nil, 7
equal(#Trainers(Model.Plan(academy, trainee, {}, {}, Choose("zone:1")).steps), 0, "trainer: none teaches the spells")
academy.npcs[900], academy.npcs[901] = taught[1], taught[2]
trainee.train.count = 1
equal(Trainers(Model.Plan(academy, trainee, {}, {}, Choose("zone:1")).steps)[1].reason, "1 new spell", "trainer: one")
local sparring = Model.Refresh(academy, trainee, {}, {}, Choose("zone:1"), schooled)
equal(#Trainers(sparring.steps), 1, "trainer: combat's cheap rebuild keeps the stop")
-- Another town's cluster (Razor Hill is several hubs), but within the town linkage (100 yards) of the stop: near.
for id = 1, 3 do
	academy.quests[id].start.hub = 7
end
equal(#Trainers(Model.Plan(academy, trainee, {}, {}, Choose("zone:1")).steps), 1, "trainer: a stop 20 yards off")
for id = 1, 3 do
	academy.quests[id].start.x = 0.65 + id / 1000
end
equal(#Trainers(Model.Plan(academy, trainee, {}, {}, Choose("zone:1")).steps), 0, "trainer: never a detour")
-- A route through two trainers' towns stops to train once.
local towns = { quests = {}, zones = academy.zones, maps = academy.maps, continents = academy.continents }
towns.hubs, towns.npcs = academy.hubs, academy.npcs
for id, place in ipairs({ { 0.501, 5 }, { 0.502, 5 }, { 0.201, 6 }, { 0.202, 6 } }) do
	towns.quests[id] = quest(place[1])
	towns.quests[id].start.hub = place[2]
end
local twice = Model.Plan(towns, trainee, {}, {}, Choose("zone:1")).steps
equal(#twice, 3, "trainer: a route through two trainers' towns")
equal(#Trainers(twice), 1, "trainer: stops to train once")
-- A trainer's stop ahead of its town leaves the card the town's reason.
local stopTown = { quests = {}, zones = academy.zones, maps = academy.maps, continents = academy.continents }
stopTown.hubs, stopTown.npcs = academy.hubs, academy.npcs
for id = 1, 3 do
	stopTown.quests[id] = quest(0.5 + id / 1000)
	stopTown.quests[id].start.hub = 5
end
local ahead = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.6, y = 0.5 }
ahead.train = trainee.train
local stopCard = Model.Plan(stopTown, ahead, {}, {}, Choose("zone:1")).journeys[1]
equal(
	stopCard.steps[1].kind .. "|" .. tostring(stopCard.reason),
	"trainer|Crossroads needs hands",
	"trainer: the town keeps its reason"
)
academy.hubs = nil
equal(Model.TownName(academy, academy.npcs[902].place), "Home", "town: the map's name without a flight master")
equal(
	Model.TownName(academy, academy.npcs[902].place, function()
		return "Client"
	end),
	"Client",
	"town: the client's name first"
)

-- Roadmap #11: rested XP under one bubble (a twentieth of the level's XP) and an innkeeper of the player's side in the
-- last stop's town (its hub, or within 100 yards): that stop's reason is the inn. Resting ticks it off; unknown rest,
-- the cap, plenty of rest or no inn there leave the stop's own reason.
do
	local function Weary(fields)
		local weary = { level = 18, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.3, y = 0.5 }
		weary.rested, weary.xpMax = 0, 10000
		for key, value in pairs(fields or {}) do
			weary[key] = value ~= false and value or nil
		end
		return weary
	end
	equal(Model.RestLow(Weary()), true, "rest: none is low")
	equal(Model.RestLow(Weary({ rested = 499 })), true, "rest: under a bubble is low")
	equal(Model.RestLow(Weary({ rested = 500 })), false, "rest: a bubble is enough")
	equal(Model.RestLow(Weary({ rested = 1, xpMax = false })), false, "rest: some, with no bar to measure it by")
	equal(Model.RestLow(Weary({ rested = 0, xpMax = false })), true, "rest: none, with no bar")
	equal(Model.RestLow(Weary({ rested = false })), false, "rest: unknown is never low")
	equal(Model.RestLow(Weary({ level = 60 })), false, "rest: nothing to rest for at the cap")
	local inns = {
		quests = {},
		zones = data.zones,
		maps = tiers.maps,
		continents = tiers.continents,
		hubs = { [5] = { name = "Crossroads, The Barrens" }, [6] = { name = "Camp Taurajo, The Barrens" } },
		npcs = {
			[950] = { inn = true, side = 2, place = { map = 1, x = 0.54, y = 0.5, name = "Innkeeper", hub = 5 } },
		},
	}
	for id, place in ipairs({ { 0.401, 6 }, { 0.501, 5 }, { 0.502, 5 } }) do
		inns.quests[id] = quest(place[1])
		inns.quests[id].start.hub = place[2]
	end
	local REST = "Rest at the inn here"
	local function Ends(traveller)
		return Model.Plan(inns, traveller, {}, {}, Choose("zone:1")).steps
	end
	local plain = Ends(Weary({ rested = 5000 }))
	equal(#plain, 2, "rest: two towns")
	equal(plain[2].hub, 5, "rest: the inn's town last")
	local firstReason, lastReason = plain[1].reason, plain[2].reason
	local weary = Ends(Weary())
	equal(weary[1].reason, firstReason, "rest: the first stop keeps its reason")
	equal(weary[2].reason, REST, "rest: the last stop's reason is the inn")
	equal(weary[2].detail, plain[2].detail, "rest: its detail stays")
	equal(#weary, 2, "rest: a reason, never a step")
	equal(Ends(Weary({ resting = true }))[2].reason, lastReason, "rest: resting ticks it off")
	equal(Ends(Weary({ rested = false }))[2].reason, lastReason, "rest: unknown rest, no line")
	equal(Ends(Weary({ maxLevel = 18 }))[2].reason, lastReason, "rest: the cap")
	inns.npcs[950].side = 1
	equal(Ends(Weary())[2].reason, lastReason, "rest: the other side's innkeeper")
	inns.npcs[950].side, inns.npcs[950].place.hub = 3, nil
	equal(Ends(Weary())[2].reason, REST, "rest: no hub, within the town linkage")
	inns.npcs[950].place.x = 0.7
	equal(Ends(Weary())[2].reason, lastReason, "rest: no hub, too far")
	inns.npcs[950].place.x, inns.npcs[950].place.hub = 0.4, 6
	equal(Ends(Weary())[2].reason, lastReason, "rest: an inn only on the way is no ending")
end

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
do
	local flagged, raids = 0, 0
	for _, q in pairs(ns.Data.quests) do
		if q.dungeon then
			flagged, raids = flagged + 1, raids + (q.raid and 1 or 0)
			assert(ns.Data.instances[q.dungeon].name ~= "", q.title)
		end
	end
	equal(flagged, 223, "dungeon and raid quests flagged")
	equal(raids, 90, "raid quests flagged")
end
-- A raid's quest filed outdoors (typed Raid): Zul'Gurub's Paragons of Power, given on Yojamba Isle, are on no card for
-- a level-60 paladin standing there, dungeons on or off.
do
	local typed = 0
	for _, q in pairs(ns.Data.quests) do
		typed = typed + ((q.raid and not q.dungeon) and 1 or 0)
	end
	equal(typed, 83, "raid quests filed outdoors")
	equal(ns.Data.quests[8053].raid and not ns.Data.quests[8053].dungeon, true, "Paragons of Power: a raid's, outdoors")
	local yojamba = { level = 60, maxLevel = 60, side = 1, raceBit = 1, classBit = 2, map = 1434, x = 0.15, y = 0.15 }
	for _, dungeons in ipairs({ false, true }) do
		local choices = prefs()
		choices.dungeons = dungeons
		local journeys = Model.Plan(ns.Data, yojamba, {}, {}, choices).journeys
		for id = 8053, 8079 do
			equal(Offered(journeys, id), nil, "Paragons of Power: never offered " .. id)
		end
	end
end

-- Honest coverage (#23): a log quest the data lacks, or a quest Forever added on this map that the data lacks.
do
	local known = { quests = { [1] = quest(0.5, 0.5, 9) }, forever = { quests = { [7] = { 1 } }, areas = {} } }
	equal(Model.Unlisted(known, 7, {}, { [1] = {} }), false, "unlisted: every quest known")
	equal(Model.Unlisted(known, 7, {}, { [2] = {} }), true, "unlisted: a log quest the data lacks")
	equal(Model.Unlisted({ quests = {} }, 7, {}, {}), false, "unlisted: no Forever slice loaded")
	equal(Model.Unlisted({ quests = {}, forever = known.forever }, nil, {}, {}), false, "unlisted: no known map")
	equal(Model.Unlisted({ quests = {}, forever = known.forever }, 7, {}, {}), true, "unlisted: an added quest here")
	equal(
		Model.Unlisted({ quests = {}, forever = known.forever }, 7, { [1] = true }, {}),
		false,
		"unlisted: every added quest here finished"
	)
	equal(Model.Unlisted({ quests = {}, forever = known.forever }, 8, {}, {}), false, "unlisted: none on another map")
	-- The generated slice against the bundled data: Westfall's added quests are unknown to it, the Barrens has none.
	assert(loadfile("Data/Forever.lua"))("AdventureGuideForever", ns)
	local forever = ns.Data.forever
	---@cast forever -?
	equal(forever.areas[16591], true, "unlisted: Riverglades is an added area")
	equal(forever.areas[40], nil, "unlisted: Westfall is not")
	equal(Model.Unlisted(ns.Data, 1436, {}, {}), true, "unlisted: Westfall has added quests")
	equal(Model.Unlisted(ns.Data, 1413, {}, {}), false, "unlisted: the Barrens has none")
end

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
do
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
end

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

-- F15: a dungeon card only with dungeons on or no next zone (roadmap #21: human60, at the cap), and never a step that
-- is not an eligible giver's data place.
do
	local function Valid(place)
		return place and place.map > 0 and place.x >= 0 and place.x <= 1 and place.y >= 0 and place.y <= 1
	end
	local cards, placeless, offCards, strandedCards = 0, 0, 0, 0
	for _, fixture in ipairs(characters.list) do
		local who, done, carried, cardPrefs = characters.Resolve(ns.Data, fixture)
		for _, dungeons in ipairs({ true, false }) do
			cardPrefs.dungeons = dungeons
			local planned = Model.Plan(ns.Data, who, done, carried, cardPrefs)
			for _, journey in ipairs(planned.journeys) do
				if journey.kind == "dungeon" then
					local off = dungeons and 0 or 1
					cards, offCards = cards + 1, offCards + (planned.stranded and 0 or off)
					strandedCards = strandedCards + (planned.stranded and off or 0)
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
	equal(strandedCards > 0, true, "dungeon card: at the cap even with dungeons off")
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
end
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
custom.quests[1].classes, custom.quests[1].pre, custom.quests[1].preAny, custom.quests[1].breadcrumb = nil, nil, nil, 2
equal(
	Texts(Model.Why(custom, player, {}, {}, 1)),
	"+ Horde only | + Requires level 10 | + Only until you take First",
	"why: breadcrumb"
)
equal(
	Texts(Model.Why(custom, player, {}, { [2] = {} }, 1)),
	"+ Horde only | + Requires level 10 | - Only until you take First",
	"why: taken"
)
-- Call of Fire (1522), an orc shaman's breadcrumb from Searn Firewarder to Kranal Fiss's Call of Fire (1524).
local shaman = { level = 10, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1454, x = 0.38, y = 0.38 }
equal(ns.Data.quests[1522].breadcrumb, 1524, "Call of Fire: a breadcrumb")
equal(Model.Eligible(ns.Data, shaman, {}, {}, 1522), true, "Call of Fire: open")
equal(Model.Eligible(ns.Data, shaman, {}, { [1524] = {} }, 1522), false, "Call of Fire: closed by its target")
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

-- Roadmap #8: a skill line's rank and a faction's standing gate a quest, on the data's scale (0 starts Neutral).
local locks = {
	quests = { quest(), quest(), quest(), quest() },
	zones = {},
	skills = { [197] = { name = "Tailoring" } },
	factions = { [576] = { name = "Timbermaw Hold" }, [529] = { name = "Argent Dawn" }, [21] = { name = "Booty Bay" } },
}
locks.quests[1].skill = { id = 197, value = 150 }
locks.quests[2].rep = { faction = 576, min = 3000 }
locks.quests[3].rep = { faction = 529, min = 9000, max = 20999 }
locks.quests[4].rep = { faction = 21, max = 1 }
local standings = { [576] = 2999, [529] = 9000 }
local skilled = setmetatable({
	skills = { [197] = 149 },
	reputation = function(faction)
		return standings[faction]
	end,
}, { __index = player })
local function Open(id)
	return Model.Eligible(locks, skilled, {}, {}, id)
end
equal(Open(1), false, "skill: rank 149 of 150")
skilled.skills[197] = 150
equal(Open(1), true, "skill: rank 150")
equal(Model.Eligible(locks, player, {}, {}, 1), false, "skill: an unlearned line is rank 0")
equal(Open(2), false, "rep: 2999 is one short of Friendly")
standings[576] = 3000
equal(Open(2), true, "rep: Friendly")
equal(Open(3), true, "rep: Honored, below the maximum")
standings[529] = 20999
equal(Open(3), false, "rep: the maximum itself closes it")
equal(Open(4), false, "rep: no standing from the client meets nothing")
standings[21] = 0
equal(Open(4), true, "rep: below the maximum")
equal(
	Texts(Model.Why(locks, player, {}, {}, 1)),
	"+ Horde only | + Requires level 10 | - Requires Tailoring 150",
	"why: a skill line and its rank"
)
equal(
	Texts(Model.Why(locks, skilled, {}, {}, 2)),
	"+ Horde only | + Requires level 10 | + Requires Friendly with Timbermaw Hold",
	"why: a standing and its faction"
)
equal(
	Texts(Model.Why(locks, skilled, {}, {}, 3)),
	"+ Horde only | + Requires level 10 | + Requires Honored with Argent Dawn "
		.. "| - Only while below Revered with Argent Dawn",
	"why: a minimum and a maximum one short of a rank"
)
equal(
	Model.Why(locks, skilled, {}, {}, 4)[3].text,
	"Depends on your standing with Booty Bay",
	"why: a value between ranks names only the faction"
)
local french = {
	skill = function()
		return "Couture"
	end,
	faction = function()
		return "Grumegueules"
	end,
	standing = function(reaction)
		return reaction == 5 and "Amical" or nil
	end,
}
equal(Model.Why(locks, player, {}, {}, 1, french)[3].text, "Requires Couture 150", "why: the client's skill name")
equal(
	Model.Why(locks, player, {}, {}, 2, french)[3].text,
	"Requires Amical with Grumegueules",
	"why: the client's standing and faction names"
)
-- The data: locks quests keep their start and carry the gate (tools/gen_quests.py `requirements`).
equal(ns.Data.quests[6031].rep.faction, 576, "data: Runecloth needs Timbermaw Hold")
equal(ns.Data.quests[6031].rep.min, 3000, "data: at Friendly")
equal(ns.Data.quests[6031].start ~= nil, true, "data: and has a start")
equal(ns.Data.quests[3385].skill.id, 197, "data: The Undermarket needs Tailoring")
equal(ns.Data.factions[576].name, "Timbermaw Hold", "data: faction names")
equal(ns.Data.skills[197].name, "Tailoring", "data: skill names")

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
-- Roadmap #5: the nearest trainer who teaches the spells, from Data.npcs, by the route's cost.
local function Nearest(side, classBit, map, x, y, level)
	local npc = Model.Trainer(ns.Data, { side = side, classBit = classBit, map = map, x = x, y = y }, level)
	return npc and npc.place.name or "none"
end
equal(Nearest(2, 64, 1413, 0.52, 0.3, 18), "Swart", "trainer: a Crossroads shaman's is in Razor Hill")
equal(Nearest(1, 128, 1453, 0.5038, 0.8599, 20), "Jennea Cannon", "trainer: never the portal trainer beside you")
equal(Nearest(1, 128, 1429, 0.49, 0.4, 4), "Khelden Bremen", "trainer: Northshire's teaches novices")
equal(Nearest(1, 128, 1429, 0.49, 0.4, 8), "Zaldimar Wefhellt", "trainer: and no one past level 6")
equal(Nearest(2, 2, 1413, 0.52, 0.3, 20), "none", "trainer: the data has no Horde paladin trainer")
equal(Nearest(2, 0, 1413, 0.52, 0.3, 20), "none", "trainer: no class, none")
equal(Model.Trainer(ns.Data, { side = 2, classBit = 64 }, 18), nil, "trainer: no place to measure from, none")

-- Not this quest, pins and the log-full note (docs/design.md §2.18), on the real data at 18 in The Barrens.
do
	player.map, player.x, player.y = 1413, 0.52, 0.3
	local function Holds(steps, id)
		for _, step in ipairs(steps) do
			for _, held in ipairs(step.quests) do
				if held == id then
					return true
				end
			end
		end
		return false
	end
	local function Choice(extra)
		local p = prefs()
		p.notInterested, p.pinned = {}, {}
		for key, value in pairs(extra or {}) do
			p[key] = value
		end
		return p
	end
	local plan = Model.Plan(ns.Data, player, {}, {}, Choice())
	local first = plan.steps[1].quests[1]
	equal(first ~= nil, true, "not this quest: the route leads with a quest")
	-- Dropped: off every card's steps.
	local dropped = Choice({ notInterested = { ["quest:" .. first] = { title = "Dropped" } } })
	for _, journey in ipairs(Model.Plan(ns.Data, player, {}, {}, dropped).journeys) do
		dropped.journey = journey.key
		equal(
			Holds(Model.Plan(ns.Data, player, {}, {}, dropped).steps, first),
			false,
			"not this quest: " .. journey.key
		)
	end
	-- In the log it is left there, and no step leads to it.
	local logged =
		{ [first] = { id = first, title = "Dropped", level = ns.Data.quests[first].level, complete = false } }
	dropped.journey = nil
	for _, journey in ipairs(Model.Plan(ns.Data, player, {}, logged, dropped).journeys) do
		dropped.journey = journey.key
		equal(Holds(Model.Plan(ns.Data, player, {}, logged, dropped).steps, first), false, "not this quest, in the log")
	end
	-- A pinned quest in another zone, which no card offers, is on Loose ends.
	local away
	for id, candidate in pairs(ns.Data.quests) do
		if
			not away
			and candidate.start
			and candidate.start.map ~= 1413
			and not (candidate.dungeon or candidate.raid)
			and candidate.min <= player.level
			and Model.Eligible(ns.Data, player, {}, {}, id)
			and not Holds(plan.steps, id)
		then
			local carried = false
			for _, journey in ipairs(plan.journeys) do
				local p = Choice({ journey = journey.key })
				carried = carried or Holds(Model.Plan(ns.Data, player, {}, {}, p).steps, id)
			end
			away = not carried and id or nil
		end
	end
	equal(away ~= nil, true, "pin: a quest no card holds")
	local pinned = Choice({ pinned = { [away] = true }, journey = "carry" })
	local carry = Model.Plan(ns.Data, player, {}, {}, pinned)
	equal(carry.journey, "carry", "pin: on Loose ends")
	equal(Holds(carry.steps, away), true, "pin: which leads to it")
	pinned.notInterested["quest:" .. away] = { title = "Dropped" }
	equal(Holds(Model.Plan(ns.Data, player, {}, {}, pinned).steps, away), false, "pin: never a dropped one")
	-- A pinned quest the story's cut left out is in its route, past the cut.
	local cut
	for id, candidate in pairs(ns.Data.quests) do
		if
			not cut
			and candidate.start
			and candidate.start.map == 1413
			and not (candidate.dungeon or candidate.raid)
			and candidate.min <= player.level
			and Model.Eligible(ns.Data, player, {}, {}, id)
			and not Holds(plan.steps, id)
		then
			cut = id
		end
	end
	equal(cut ~= nil, true, "pin: a story quest the cut left out")
	local led = Model.Plan(ns.Data, player, {}, {}, Choice({ pinned = { [cut] = true } }))
	equal(led.journey, plan.journey, "pin: the same card leads")
	equal(Holds(led.steps, cut), true, "pin: and its route has the pinned quest")
	-- The log-full note: nil with room, else the log's quests the guide would let go, sorted.
	local grey, crowded = {}, {}
	for id, candidate in pairs(ns.Data.quests) do
		if
			#grey < 3
			and candidate.side ~= 1
			and candidate.level > 0
			and candidate.level <= 5
			and candidate.start
			and candidate.finish
		then
			grey[#grey + 1] = id
		end
	end
	table.sort(grey)
	for _, id in ipairs(grey) do
		crowded[id] = { id = id, title = ns.Data.quests[id].title, level = ns.Data.quests[id].level, complete = false }
	end
	player.logMax = 20
	equal(Model.Plan(ns.Data, player, {}, crowded, Choice()).journeys[1].drop, nil, "log full: room, no note")
	player.logMax = #grey + 2
	local drop = Model.Plan(ns.Data, player, {}, crowded, Choice()).journeys[1].drop
	equal(drop and table.concat(drop, " "), table.concat(grey, " "), "log full: the grey quests, sorted")
	crowded[grey[1]].complete = true
	drop = Model.Plan(ns.Data, player, {}, crowded, Choice()).journeys[1].drop
	equal(drop and drop[1], grey[2], "log full: never a finished quest")
	player.logMax = nil
end

player.map, player.x, player.y = 1413, 0.52, 0.3
local baseline = Model.Plan(ns.Data, player, {}, {}, prefs())
equal(#baseline.steps >= 3, true, "level 18 Horde route offers at least three steps")
local signature = {}
for _, step in ipairs(baseline.steps) do
	signature[#signature + 1] = step.key
end
-- The game runs plain Lua 5.1, so this times the planner, not LuaJIT's code cache: Ubuntu's LuaJIT
-- keeps 512 KB of machine code, too little for the whole spec, and flushes every few Plans once full.
-- plan_bench's -joff run is the frame budget.
jit.opt.start("maxmcode=4096")
jit.flush()
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
