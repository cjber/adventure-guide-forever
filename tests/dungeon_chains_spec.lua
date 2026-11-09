-- Run from the repository root: luajit tests/dungeon_chains_spec.lua
-- The dungeon card gathers every quest of the instance it can still reach (docs/design.md §2.21): whole prerequisite
-- chains, through branches, before it sends the player to the entrance, and it says how its quests split into chains
-- and single quests (#557).
local harness = dofile("tests/harness.lua")
local characters = dofile("tests/fixtures/characters.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local ns = {}
ns.Data = harness.data()
harness.model(ns)
local Model, data = ns.Model, ns.Data

local fixture
for _, value in ipairs(characters.list) do
	fixture = value.name == "ne17_westfall_deadmines" and value or fixture
end
assert(fixture, "the Deadmines fixture is in tests/fixtures/characters.lua")
local player, completed, log, prefs, inputs = characters.Resolve(data, fixture)
local route = Model.Plan(data, player, completed, log, prefs, nil, nil, nil, inputs)
local card
for _, journey in ipairs(route.journeys) do
	card = journey.key == "dungeon:36" and journey or card
end
assert(card, "the Deadmines card is offered")

local function Has(step, list, id)
	for _, value in ipairs(step[list] or {}) do
		if value == id then
			return true
		end
	end
	return false
end

local function StepWith(list, id)
	for index, step in ipairs(card.steps) do
		if Has(step, list, id) then
			return step, index
		end
	end
end

-- The Destruction in Deadmines chain forks before it reaches the instance: both of its starts are offered now.
local start, startAt = StepWith("pickups", 92742)
local other = StepWith("pickups", 92744)
equal(start ~= nil, true, "Testing the Wells is a pickup on the card")
equal(other ~= nil, true, "Murloc Gills is a pickup on the card")
equal(start ~= nil and other ~= nil, true, "the branching chain's starts are both offered")
equal(startAt ~= nil and startAt <= #card.steps, true, "its pickup is a step")

-- The Defias Brotherhood step 1 is handed in on the card; the rest of its chain follows on later builds.
local handin
for _, step in ipairs(card.steps) do
	handin = (Has(step, "handins", 65) or (step.kind == "turnin" and Has(step, "quests", 65))) and step or handin
end
equal(handin ~= nil, true, "The Defias Brotherhood is handed in on the card")

-- The entrance is after every chain and pickup step that leads to more of the dungeon's quests.
local entranceAt
for index, step in ipairs(card.steps) do
	entranceAt = step.key == "entrance:36" and index or entranceAt
end
equal(entranceAt, #card.steps, "Go to entrance is the last step")
equal(
	entranceAt ~= nil and card.steps[entranceAt].reason:find("%d dungeon quests are still to pick up") ~= nil,
	true,
	"the entrance says what the chains leave behind"
)

-- Each chain is a labelled group with its progress; single quests carry no chain label.
local labels = {}
for _, step in ipairs(card.steps) do
	if step.chapter then
		labels[step.chapter] = true
	end
end
local defias, destruction
for label in pairs(labels) do
	defias = label:find("^The Defias Brotherhood, %d+ of %d+$") and label or defias
	destruction = label:find("^Destruction in Deadmines, %d+ of %d+$") and label or destruction
end
equal(defias ~= nil, true, "The Defias Brotherhood chain is labelled with its progress")
equal(destruction ~= nil, true, "Destruction in Deadmines is labelled with its progress")
equal(defias, "The Defias Brotherhood, 1 of 8", "the Defias chain counts its one handed-in step")
equal(destruction, "Destruction in Deadmines, 0 of 10", "the Destruction chain counts its ten quests")
local single = StepWith("quests", 167)
equal(single ~= nil and single.chapter == nil, true, "a single dungeon quest has no chain label")

-- The card tells the same split in its own lines: two chains, and nothing for the single quests.
equal(card.chains ~= nil and #card.chains, 2, "the card lists its two chains")
equal(card.chains and card.chains[1].label, defias, "the first chain's label")
equal(card.chains and card.chains[2].label, destruction, "the second chain's label")

-- Nothing ineligible is offered and every step has a place, as on every card.
for _, step in ipairs(card.steps) do
	equal(
		step.map > 0 and step.x >= 0 and step.x <= 1 and step.y >= 0 and step.y <= 1,
		true,
		step.key .. " has a place"
	)
	for _, id in ipairs(step.quests) do
		equal(
			log[id] ~= nil or Model.Eligible(data, player, completed, log, id),
			true,
			step.key .. " offers " .. id .. " only when it is eligible or in the log"
		)
	end
end

-- #557: an Alliance night elf's Wailing Caverns card counts only the instance's quests they could ever take. It does
-- not count the Horde-only quests (914, 962, 1489 and 1490) or 6981, which has no start. The ceiling reaches 6981, so
-- its missing start, not the orange rule, is what keeps it out. One neutral quest under way places the entrance step.
local wailing = {
	name = "ne17_wailing_caverns",
	level = 17,
	side = 1,
	raceBit = 8,
	classBit = 4,
	map = 1413,
	x = 0.5200,
	y = 0.3000,
	completed = {},
	log = { { id = 1486, title = "Deviate Hides", level = 17, complete = false } },
	prefs = { dungeons = true, journey = "dungeon:43" },
	inputs = { dungeonEntrances = { [43] = { map = 1413, x = 0.46, y = 0.36 } } },
}
local wplayer, wcompleted, wlog, wprefs, winputs = characters.Resolve(data, wailing)
wplayer.maxQuestLevelOffset = 9
local wroute = Model.Plan(data, wplayer, wcompleted, wlog, wprefs, nil, nil, nil, winputs)
local wcard
for _, journey in ipairs(wroute.journeys) do
	wcard = journey.key == "dungeon:43" and journey or wcard
end
assert(wcard, "the Wailing Caverns card is offered")
local wentrance
for _, step in ipairs(wcard.steps) do
	wentrance = step.key == "entrance:43" and step or wentrance
end
assert(wentrance, "the Wailing Caverns card has an entrance")
equal(
	wentrance.reason,
	"3 dungeon quests are still to pick up",
	"the entrance counts only the instance's quests this player could take"
)

print(("dungeon_chains_spec: %d checks passed"):format(checks))
