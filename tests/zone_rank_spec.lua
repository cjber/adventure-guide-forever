-- Run from the repository root: luajit tests/zone_rank_spec.lua
-- Destinations rank by the work a zone holds for this character and side, with travel one factor among them (#492).
-- The report: a level 15 night elf in Darkshore saw "Head to The Barrens", a Horde zone with a few neutral quests,
-- before Loch Modan, a full Alliance zone at the same levels. The boat to the other continent cost more rank than
-- every quest a zone can offer, so no amount of work made up for it. The real corpus, through the client harness.
local harness = dofile("tests/harness.lua")

local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

-- Every card by key, so a spec can compare their places.
local function Places(route)
	local places = {}
	for index, journey in ipairs(route.journeys) do
		places[journey.key] = index
	end
	return places
end

-- A level 15 night elf warrior in Darkshore, nothing done: the reporter's character in the zone they asked about.
local h = harness.load({
	spf = "v1",
	db = { autoStart = false },
	completed = {},
	player = { level = 15, faction = "Alliance", raceID = 4, classID = 1, map = 1439, x = 0.39, y = 0.45 },
	log = {},
})
h.flush()
do
	local places = Places(h.ns.Route())
	check(places["zone:1432"] ~= nil, "Loch Modan is offered")
	check(places["zone:1413"] ~= nil, "The Barrens is offered")
	check(places["zone:1432"] < places["zone:1413"], "Loch Modan ranks above The Barrens")
	-- The zone the player stands in leads, and the full zones of their side follow it, not a Horde zone.
	check(places["zone:1439"] == 1, "Darkshore, where the player stands, leads")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A level 18 orc shaman at the Crossroads still gets The Barrens story, or Stonetalon, before anything else.
local horde = harness.load({
	spf = "v1",
	db = { autoStart = false },
	completed = { 844 },
	player = { level = 18, faction = "Horde", raceID = 2, classID = 64, map = 1413, x = 0.52, y = 0.30 },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	},
})
horde.flush()
do
	local first = horde.ns.Route().journeys[1]
	check(first ~= nil, "the Horde player has a card")
	check(
		first.key == "zone:1413" or first.key == "zone:1442",
		"The Barrens or Stonetalon leads, not another continent's zone"
	)
	check(#horde.errors == 0, table.concat(horde.errors, "\n"))
end

print(("zone_rank_spec: %d checks passed"):format(checks))
