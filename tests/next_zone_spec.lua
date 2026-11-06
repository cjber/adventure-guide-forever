-- Run from the repository root: luajit tests/next_zone_spec.lua
-- Finishing a zone journey moves to the next zone card (#400): the planner's order, never the finished zone, never one
-- the player hid. A guided route starts again; with the setting off, or for another journey kind, today's clear stands.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function Barrens(extra)
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	local options = {
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = log,
	}
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	return harness.load(options)
end

-- The full build just committed, without the finished zone.
local function Route()
	return {
		chosen = false,
		journey = nil,
		steps = {},
		journeys = {
			{ kind = "story", key = "zone:1413", title = "The Barrens story" },
			{ kind = "carry", key = "carry", title = "Clean up my log" },
			{ kind = "nextzone", key = "zone:1442", title = "Head to Stonetalon Mountains" },
			{ kind = "nextzone", key = "zone:1440", title = "Head to Ashenvale" },
		},
	}
end

-- A guided zone ends on a turn-in: the next zone is chosen and its route starts on the next build.
do
	local h = Barrens()
	local ns = h.ns
	ns.Prefs().guided = "zone:1413"
	ns.TurnedIn(894)
	ns.Guidance.Ended(Route())
	check(ns.Prefs().journey == "zone:1442", "the next zone card is chosen")
	local block = h.tracker.liveBlocks["journey-complete"]
	check(block and block.header == ns.L.JOURNEY_COMPLETE, "the journey complete block shows")
	check(
		block and block.lines[1] == ns.L.JOURNEY_NEXT:format("Head to Stonetalon Mountains"),
		"and names the next zone"
	)
	h.flush()
	check(ns.Route().journey == "zone:1442", "the new zone leads")
	check(ns.Prefs().guided == "zone:1442", "and its guided route starts")
	check(h.spf.NavigateRoute == 1, "Shortest Path is handed the new route")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The setting off: the same ending clears the choice, as before.
do
	local h = Barrens({ db = { autoStart = false, autoNextZone = false } })
	local ns = h.ns
	ns.Prefs().guided = "zone:1413"
	ns.TurnedIn(894)
	ns.Guidance.Ended(Route())
	check(ns.Prefs().journey == nil, "the choice is cleared")
	check(ns.Prefs().guided == nil, "and its guidance")
	local block = h.tracker.liveBlocks["journey-complete"]
	check(block and block.lines[1] == ns.L.CHOOSE_NEXT, "the tracker asks for the next journey")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A dungeon journey keeps today's behaviour: it ends and clears.
do
	local h = Barrens({ db = { autoStart = false, dungeons = true } })
	local ns = h.ns
	ns.Prefs().journey, ns.Prefs().guided = "dungeon:1", "dungeon:1"
	ns.TurnedIn(894)
	local route = Route()
	route.stranded = true
	ns.Guidance.Ended(route)
	check(ns.Prefs().journey == nil, "a finished dungeon clears the choice")
	check(ns.Prefs().guided == nil, "and stops its route")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A hidden next zone is skipped for the one after it.
do
	local h = Barrens({
		charDB = {
			journey = "zone:1413",
			notInterested = { ["zone:1442"] = { title = "Head to Stonetalon Mountains" } },
		},
	})
	local ns = h.ns
	ns.TurnedIn(894)
	ns.Guidance.Ended(Route())
	check(ns.Prefs().journey == "zone:1440", "the hidden zone is passed over")
	h.flush()
	check(ns.Route().journey ~= "zone:1442", "and never becomes the route")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("next_zone_spec: " .. checks .. " checks passed")
