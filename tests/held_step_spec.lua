-- Run from the repository root: luajit tests/held_step_spec.lua
-- The step the tracker holds (docs/design.md §4.2): step 1 stays until it is done or skipped, so a re-plan from a new
-- place only reorders the stops after it. The Barrens case: The Zhevra's objective area leads at the Crossroads, then
-- a trip to Orgrimmar to train used to re-plan the story and make another quest from the log its step 1. The Westfall
-- case: with nothing held yet, the objective area the player stands in takes step 1, not a distant town pickup.
local harness = dofile("tests/harness.lua")

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- The step of the route with `key`, or nil.
local function step(route, key)
	for _, each in ipairs(route.steps) do
		if each.key == key then
			return each
		end
	end
	return nil
end

-- A level 18 orc shaman at The Zhevra's first objective node, with the quest under way in the Barrens story.
local function Barrens()
	local h = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		player = { level = 18, faction = "Horde", raceID = 2, classID = 64, map = 1413, x = 0.486, y = 0.377 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = false } },
	})
	h.flush()
	return h
end

-- The held step survives a trip to Orgrimmar: the rebuilt route still leads with The Zhevra's area, and no other
-- quest from the log takes its place.
do
	local h = Barrens()
	local route = h.ns.Route()
	local held = route.steps[1]
	equal(held.key, "area:845:4", "barrens: The Zhevra's area leads at the objective")
	equal(held.here, true, "barrens: standing in it")
	h.MovePlayer(1454, 0.5000, 0.5000) -- Orgrimmar, at the trainer
	h.ns.Invalidate()
	h.flush()
	route = h.ns.Route()
	equal(route.steps[1].key, held.key, "barrens: a re-plan in Orgrimmar keeps step 1")
	equal(route.steps[1].here, nil, "barrens: the held step is not where the player stands")
	equal(step(route, "town:1413:382") ~= nil, true, "barrens: the quest that used to take step 1 stays on the route")
	equal(route.steps[1].key ~= "town:1413:382", true, "barrens: and does not take step 1")
	-- A rebuild with nothing changed still holds it.
	h.ns.Invalidate()
	h.flush()
	equal(h.ns.Route().steps[1].key, held.key, "barrens: a second rebuild keeps step 1")
	equal(#h.errors, 0, "barrens: no errors\n" .. table.concat(h.errors, "\n"))
end

-- The held step survives a /reload (#631): the first build after login has no route in hand, so the key saved with the
-- character stands in for it. The player moved to Orgrimmar first, where a fresh plan puts another town pickup at the
-- head.
do
	local saved = { journey = "zone:1413" }
	local h = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = saved,
		completed = { 844 },
		player = { level = 18, faction = "Horde", raceID = 2, classID = 64, map = 1413, x = 0.486, y = 0.377 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = false } },
	})
	h.flush()
	local held = h.ns.Route().steps[1].key
	equal(held, "area:845:4", "reload: The Zhevra's area leads at the objective")
	h.MovePlayer(1454, 0.5000, 0.5000) -- Orgrimmar, at the trainer
	h.ns.Invalidate()
	h.flush()
	equal(h.ns.Route().steps[1].key, held, "reload: the rebuild before leaving keeps step 1")
	equal(saved.heldStep, held, "reload: the held key is saved with the character")

	-- A fresh load with the same saved prefs, as after a /reload, with the player still in Orgrimmar.
	local again = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = saved,
		completed = { 844 },
		player = { level = 18, faction = "Horde", raceID = 2, classID = 64, map = 1454, x = 0.5000, y = 0.5000 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = false } },
	})
	again.flush()
	local route = again.ns.Route()
	equal(route.steps[1].key, held, "reload: the first build after the reload holds the same step")
	equal(route.steps[1].here, nil, "reload: the held step is not where the player stands")
	equal(#again.errors, 0, "reload: no errors\n" .. table.concat(again.errors, "\n"))
	-- A second build keeps it too.
	again.ns.Invalidate()
	again.flush()
	equal(again.ns.Route().steps[1].key, held, "reload: a second build still holds it")

	-- Without the saved key the same state puts another head first, so the reload checks above are the saved one.
	local control = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = saved.journey, lead = saved.lead, left = saved.left },
		completed = { 844 },
		player = { level = 18, faction = "Horde", raceID = 2, classID = 64, map = 1454, x = 0.5000, y = 0.5000 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = false } },
	})
	control.flush()
	equal(control.ns.Route().steps[1].key ~= held, true, "reload: the planner alone picks another head here")
end

-- Skipping the held step lets the route choose again.
do
	local h = Barrens()
	local heldStep = h.ns.Route().steps[1]
	h.ns.Skip(heldStep.key, heldStep.title)
	equal(h.ns.Prefs().heldStep, nil, "skip: the saved held key clears at once")
	h.flush()
	local route = h.ns.Route()
	equal(step(route, heldStep.key), nil, "skip: the held step leaves the route")
	equal(route.steps[1] ~= nil and route.steps[1].key ~= heldStep.key, true, "skip: another step leads")
	equal(h.ns.Prefs().heldStep ~= heldStep.key, true, "skip: the saved key is not the skipped step")
	equal(#h.errors, 0, "skip: no errors\n" .. table.concat(h.errors, "\n"))
end

-- Westfall: standing in the Longshore murloc area with Murloc Gills under way, the area takes step 1 even though the
-- nearest town pickup would otherwise lead. It holds when the route is rebuilt without moving.
do
	local h = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = { optimisedRoute = false },
		completed = { zones = { 1429 } },
		player = { level = 12, faction = "Alliance", raceID = 1, classID = 1, map = 1436, x = 0.344, y = 0.208 },
		log = { { id = 92744, title = "Murloc Gills", level = 12, complete = false } },
	})
	h.flush()
	local route = h.ns.Route()
	local held = route.steps[1]
	equal(held.key, "area:92744:4", "westfall: the area the player stands in leads")
	equal(held.here, true, "westfall: and reads as here")
	local pickup = false
	for index, each in ipairs(route.steps) do
		pickup = pickup or (index > 1 and #(each.pickups or {}) > 0)
	end
	equal(pickup, true, "westfall: a town pickup follows rather than leads")
	h.ns.Invalidate()
	h.flush()
	equal(h.ns.Route().steps[1].key, held.key, "westfall: a rebuild keeps the area at step 1")
	equal(#h.errors, 0, "westfall: no errors\n" .. table.concat(h.errors, "\n"))
end

print(("held_step_spec: %d checks passed"):format(checks))
