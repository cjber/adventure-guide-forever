-- Run from the repository root: luajit tests/tooltip_spec.lua
-- The NPC tooltip line (Tooltip.lua, docs/design.md §2.9) through tests/harness.lua: an NPC the chosen journey's steps
-- visit says so on its unit tooltip; no other unit, and nothing while no journey is chosen.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function same(actual, expected, label)
	equal(table.concat(actual, "\n"), table.concat(expected, "\n"), label)
end

-- ui_spec's level-18 orc shaman in The Barrens; The Zhevra is ready to hand in at `zhevra`, its log waypoint.
local function Load(charDB, zhevra)
	zhevra = zhevra or { x = 0.5223, y = 0.3101 }
	local h = harness.load({
		charDB = charDB,
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = zhevra.x, y = zhevra.y },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
		},
	})
	h.flush()
	return h
end

local function Creature(entry)
	return ("Creature-0-5250-0-17-%d-00004A2B3C"):format(entry)
end

-- The lines a unit's tooltip gains.
local function Lines(h, guid)
	h.HoverUnit(guid)
	return h.tooltip
end

local SERGRA, THORK, KADRAK = 3338, 3429, 8582 -- The Zhevra's ender; Crossroads and Mor'shan Rampart givers

-- The carry card: Sergra Darkthorn takes The Zhevra at the Crossroads, and nobody else there is on its route.
do
	local h = Load({ journey = "carry" })
	same(Lines(h, Creature(SERGRA)), { "normal: Adventure guide: Finish what you carry" }, "carry: the ender")
	same(Lines(h, Creature(THORK)), {}, "carry: a giver the card doesn't visit")
	same(Lines(h, "Player-5250-0A1B2C3D"), {}, "carry: a player")
	same(Lines(h, nil), {}, "carry: no unit")
	h.SetCombat(true)
	h.flush()
	same(Lines(h, Creature(SERGRA)), { "normal: Adventure guide: Finish what you carry" }, "carry: in combat too")
	equal(#h.errors, 0, "carry: errors\n" .. table.concat(h.errors, "\n"))
end

-- The zone's story: its pickups' givers, in towns beyond the first; choosing none takes the line away.
do
	local h = Load({ journey = "zone:1413" })
	local line = { "normal: Adventure guide: The Barrens story" }
	same(Lines(h, Creature(THORK)), line, "story: a pickup's giver")
	same(Lines(h, Creature(KADRAK)), line, "story: in a later town")
	same(Lines(h, Creature(SERGRA)), line, "story: its hand-in's ender")
	same(Lines(h, Creature(3439)), line, "story: Wizzlecrank's Shredder is a creature")
	h.ns.Choose(nil)
	h.flush()
	equal(h.ns.Route().chosen, false, "none chosen")
	same(Lines(h, Creature(THORK)), {}, "none chosen: no line")
	equal(#h.errors, 0, "story: errors\n" .. table.concat(h.errors, "\n"))
end

-- A turn-in at the client's waypoint, away from the town: the quest's finish NPC still takes it.
do
	local h = Load({ journey = "carry" }, { x = 0.62, y = 0.38 })
	equal(h.ns.Route().steps[1].kind, "turnin", "a turn-in step")
	same(Lines(h, Creature(SERGRA)), { "normal: Adventure guide: Finish what you carry" }, "turn-in: the ender")
	equal(#h.errors, 0, "turn-in: errors\n" .. table.concat(h.errors, "\n"))
end

-- No journey chosen on login: no NPC says anything.
do
	local h = Load(nil)
	equal(h.ns.Route().chosen, false, "login: none chosen")
	same(Lines(h, Creature(SERGRA)), {}, "login: no line")
	equal(#h.errors, 0, "login: errors\n" .. table.concat(h.errors, "\n"))
end

print(("tooltip_spec: %d checks passed"):format(checks))
