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
		planned = true,
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

local SERGRA, MANKRIK, LATER = 3338, 3432, 3446 -- The Zhevra's ender; Crossroads and Ratchet's giver

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

-- The chosen story names its pickups and hand-ins; clearing the choice returns to accepted quests.
do
	local h = Load({ journey = "zone:1413" })
	local line = { "normal: Adventure guide: The Barrens story" }
	same(Lines(h, Creature(MANKRIK)), line, "story: a pickup's giver")
	same(Lines(h, Creature(LATER)), line, "story: in a later town")
	same(Lines(h, Creature(SERGRA)), line, "story: its hand-in's ender")
	h.ns.Choose(nil)
	h.flush()
	equal(h.ns.Route().chosen, false, "none chosen")
	same(Lines(h, Creature(MANKRIK)), {}, "none chosen: unrelated pickup has no line")
	same(Lines(h, Creature(SERGRA)), { "normal: Adventure guide: Quests in your log" }, "none chosen: accepted hand-in")
	equal(#h.errors, 0, "story: errors\n" .. table.concat(h.errors, "\n"))
end

-- A turn-in at the client's waypoint, away from the town: the quest's finish NPC still takes it.
do
	local h = Load({ journey = "zone:1413" }, { x = 0.62, y = 0.36 })
	local turnin
	for _, step in ipairs(h.ns.Route().steps) do
		turnin = turnin or (step.key == "turnin:845" and step or nil)
	end
	equal(turnin and turnin.kind, "turnin", "a turn-in step")
	same(Lines(h, Creature(SERGRA)), { "normal: Adventure guide: The Barrens story" }, "turn-in: the ender")
	equal(#h.errors, 0, "turn-in: errors\n" .. table.concat(h.errors, "\n"))
end

-- No journey chosen on login: accepted quests provide the default route.
do
	local h = Load(nil)
	equal(h.ns.Route().chosen, false, "login: none chosen")
	same(Lines(h, Creature(SERGRA)), { "normal: Adventure guide: Quests in your log" }, "login: accepted quest route")
	equal(#h.errors, 0, "login: errors\n" .. table.concat(h.errors, "\n"))
end

-- Secret values (docs/design.md §2.23): a GUID or unit token the client keeps secret reads as no unit, and a forbidden
-- tooltip is left alone; neither raises an error, in combat or out. Indexing or matching a secret would.
do
	local h = Load({ journey = "zone:1413" })
	local line = { "normal: Adventure guide: The Barrens story" }
	local guid = Creature(SERGRA)
	h.secrets[guid] = true
	same(Lines(h, guid), {}, "secret: a secret GUID adds nothing")
	h.SetCombat(true)
	h.flush()
	same(Lines(h, guid), {}, "secret: in combat too")
	h.SetCombat(false)
	h.secrets[guid] = nil
	h.secrets.mouseover = true
	same(Lines(h, guid), {}, "secret: a secret unit token adds nothing")
	h.secrets.mouseover = nil
	same(Lines(h, guid), line, "secret: readable again")
	h.forbiddenTooltip = true
	same(Lines(h, guid), {}, "forbidden: the tooltip is left alone")
	h.forbiddenTooltip = false
	same(Lines(h, guid), line, "forbidden: allowed again")
	equal(#h.errors, 0, "secret: errors\n" .. table.concat(h.errors, "\n"))
end

-- ns.Readable passes readable values through unchanged and nil for a secret; ns.Usable refuses nil and a forbidden
-- frame. Without canaccessvalue (a client with no secret values) every value reads.
do
	local h = Load(nil)
	local ns = h.ns
	h.secrets.hidden = true
	equal(ns.Readable("shown"), "shown", "Readable: a readable string")
	equal(ns.Readable(0), 0, "Readable: a readable zero")
	equal(ns.Readable(false), false, "Readable: a readable false")
	equal(ns.Readable(nil), nil, "Readable: nil")
	equal(ns.Readable("hidden"), nil, "Readable: a secret")
	equal(ns.Usable(nil), false, "Usable: nil")
	equal(ns.Usable({}), true, "Usable: a frame without IsForbidden")
	equal(ns.Usable(h.G.GameTooltip), true, "Usable: GameTooltip")
	h.forbiddenTooltip = true
	equal(ns.Usable(h.G.GameTooltip), false, "Usable: a forbidden GameTooltip")
	local saved = h.G.canaccessvalue
	h.G.canaccessvalue = nil
	equal(ns.Readable("hidden"), "hidden", "Readable: no secret values on this client")
	h.G.canaccessvalue = saved
end

print(("tooltip_spec: %d checks passed"):format(checks))
