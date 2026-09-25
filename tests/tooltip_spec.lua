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
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
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

local SERGRA, THORK, GAZLOWE = 3338, 3429, 3391 -- The Zhevra's ender; Crossroads and Ratchet givers

-- The log's quests ride on the zone's story (they are done on its map): Sergra Darkthorn takes The Zhevra at the
-- Crossroads; Innkeeper Gryshka in Orgrimmar is on none of its steps.
local GRYSHKA = 6929
do
	local h = Load({ journey = "zone:1413" })
	local line = { "normal: Adventure guide: The Barrens story" }
	same(Lines(h, Creature(SERGRA)), line, "log: the ender")
	same(Lines(h, Creature(GRYSHKA)), {}, "log: an NPC the card doesn't visit")
	same(Lines(h, "Player-5250-0A1B2C3D"), {}, "log: a player")
	same(Lines(h, nil), {}, "log: no unit")
	h.SetCombat(true)
	h.flush()
	same(Lines(h, Creature(SERGRA)), line, "log: in combat too")
	h.SetCombat(false)
	-- Once The Zhevra is handed in the card goes on without it.
	table.remove(h.log, 1)
	h.fire("QUEST_TURNED_IN", 845)
	h.flush()
	local handins = 0
	for _, step in ipairs(h.ns.Route().steps) do
		for _, id in ipairs(step.handins or {}) do
			handins = handins + (id == 845 and 1 or 0)
		end
	end
	equal(handins, 0, "log: The Zhevra is no longer handed in")
	equal(#h.errors, 0, "log: errors\n" .. table.concat(h.errors, "\n"))
end

-- The zone's story: its pickups' givers, in towns beyond the first; choosing none keeps the line, as the guide draws
-- the first card on its own.
do
	local h = Load({ journey = "zone:1413" })
	local line = { "normal: Adventure guide: The Barrens story" }
	same(Lines(h, Creature(THORK)), line, "story: a pickup's giver")
	same(Lines(h, Creature(GAZLOWE)), line, "story: in a later town")
	same(Lines(h, Creature(SERGRA)), line, "story: its hand-in's ender")
	h.ns.Choose(nil)
	h.flush()
	equal(h.ns.Route().chosen, false, "none chosen")
	same(Lines(h, Creature(THORK)), line, "none chosen: the first card's line")
	equal(#h.errors, 0, "story: errors\n" .. table.concat(h.errors, "\n"))
end

-- A turn-in at the client's waypoint, away from the town: the quest's finish NPC still takes it.
do
	local h = Load({ journey = "zone:1413" }, { x = 0.62, y = 0.38 })
	local turnin
	for _, step in ipairs(h.ns.Route().steps) do
		turnin = turnin or (step.key == "turnin:845" and step or nil)
	end
	equal(turnin and turnin.kind, "turnin", "a turn-in step")
	same(Lines(h, Creature(SERGRA)), { "normal: Adventure guide: The Barrens story" }, "turn-in: the ender")
	equal(#h.errors, 0, "turn-in: errors\n" .. table.concat(h.errors, "\n"))
end

-- No journey chosen on login: the first card's NPCs say so all the same.
do
	local h = Load(nil)
	equal(h.ns.Route().chosen, false, "login: none chosen")
	same(Lines(h, Creature(SERGRA)), { "normal: Adventure guide: The Barrens story" }, "login: the first card's")
	equal(#h.errors, 0, "login: errors\n" .. table.concat(h.errors, "\n"))
end

print(("tooltip_spec: %d checks passed"):format(checks))
