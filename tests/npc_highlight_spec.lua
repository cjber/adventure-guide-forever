-- Run from the repository root: luajit tests/npc_highlight_spec.lua
-- The current talk step's NPC (#401): match a nameplate by creature entry then exact name, bounce our own two arrows
-- either side of it, hint once when friendly nameplates are off, and clean up when the step changes. Every target
-- change rebuilds the target button and raises nothing: the client refuses a raid mark to addons. The guide never
-- writes a CVar or touches the nameplate.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function Load(extra)
	local options = {
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
	}
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	local h = harness.load(options)
	-- A laid-out tracker: the secure target rows anchor at its bottom-left.
	h.tracker.rect = { 0, 300, 200, 100 }
	return h
end

local STEP = {
	kind = "town",
	key = "town:test",
	title = "Pick up: Test",
	quests = { 858 },
	pickups = { 858 },
	handins = {},
	spots = { [858] = { name = "Wizzlecrank's Shredder", npc = 3439, map = 1413, x = 0.5652, y = 0.0745 } },
	map = 1413,
	x = 0.5652,
	y = 0.0745,
}

local GUID = "Creature-0-1-2-3-3439-0000ABCDEF"

local function Step(h, step)
	h.ns.Guidance.CurrentStep = function()
		return step
	end
	h.ns.NpcHighlight.Refresh()
end

-- The creature entry wins when both sides have one; the exact name is the fallback.
do
	local h = Load()
	local ns = h.ns
	h.guids, h.unitNames = {}, {}
	h.G.UnitGUID = function(unit)
		return h.guids[unit]
	end
	h.G.UnitName = function(unit)
		return h.unitNames[unit]
	end
	local npc = { name = "Thork", npc = 3439 }
	h.guids.nameplate1 = GUID
	check(ns.NpcHighlight.Matches(npc, "nameplate1"), "the same creature entry matches")
	h.guids.nameplate1 = "Creature-0-1-2-3-9999-0000ABCDEF"
	check(ns.NpcHighlight.Matches(npc, "nameplate1") == false, "another entry does not")
	h.unitNames.nameplate1 = "Thork"
	check(ns.NpcHighlight.Matches(npc, "nameplate1") == false, "and its name does not override a known entry")
	h.guids.nameplate1 = GUID
	h.unitNames.nameplate1 = "Someone Else"
	check(ns.NpcHighlight.Matches(npc, "nameplate1"), "the same entry matches whatever the name says")
	h.unitNames.nameplate1 = "Thork"
	h.guids.nameplate1 = nil
	check(ns.NpcHighlight.Matches(npc, "nameplate1"), "without an entry, the exact name matches")
	h.unitNames.nameplate1 = "thork"
	check(ns.NpcHighlight.Matches(npc, "nameplate1") == false, "the name match is exact")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A shown nameplate gets our own bouncing arrows; removal and a step change take them away.
do
	local h = Load()
	local ns = h.ns
	h.guids, h.unitNames = { nameplate1 = GUID }, { nameplate1 = "Wizzlecrank's Shredder" }
	h.G.UnitGUID = function(unit)
		return h.guids[unit]
	end
	h.G.UnitName = function(unit)
		return h.unitNames[unit]
	end
	local healthBar = {}
	h.namePlates =
		{ nameplate1 = {
			IsShown = function()
				return true
			end,
			UnitFrame = { healthBar = healthBar },
		} }
	Step(h, STEP)
	h.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	check(ns.NpcHighlight.ArrowUnit() == "nameplate1", "the matching nameplate carries the arrow")
	-- Only the two arrows: no glow square behind them (#412).
	local frame = h.G.AdventureGuideForeverNpcArrow
	local arrows = { frame:GetRegions() }
	check(#arrows == 2, "the arrow frame holds just the two arrows")
	check(arrows[1].layer == "ARTWORK" and arrows[2].layer == "ARTWORK", "both arrows draw on ARTWORK")
	check(arrows[1].atlas == "NPE_ArrowRight", "the left arrow points right")
	check(arrows[2].atlas == "NPE_ArrowLeft", "the right arrow points left")
	local function anchor(texture)
		local point, relativeTo, relativePoint, x = texture:GetPoint(1)
		return point, relativeTo, relativePoint, x
	end
	local point, bar, relativePoint, leftX = anchor(arrows[1])
	local rightX
	check(point == "RIGHT" and relativePoint == "LEFT", "the left arrow hangs off the nameplate's left edge")
	check(bar == h.namePlates.nameplate1.UnitFrame.healthBar, "at the health bar, not the plate's top")
	check(leftX == -6, "six units clear of it")
	point, bar, relativePoint, rightX = anchor(arrows[2])
	check(point == "LEFT" and relativePoint == "RIGHT", "the right arrow hangs off the right edge")
	check(bar == h.namePlates.nameplate1.UnitFrame.healthBar, "at the health bar too")
	check(rightX == 22, "and sixteen units further out than the left, clearing Field Guide's tier mark")
	-- Both bob inward together, three units.
	h.call(frame.scripts.OnUpdate, frame, 0.25)
	local _, _, _, bobbedLeft = anchor(arrows[1])
	local _, _, _, bobbedRight = anchor(arrows[2])
	check(bobbedLeft == -3 and bobbedRight == 19, "the pair bobs toward the nameplate and back, in step")
	check(ns.NpcHighlight.TargetShown(), "and the talk step has a target button")
	local button = h.G.AdventureGuideForeverNpcTarget
	check(button ~= nil, "the target button is built")
	check(button:GetAttribute("type1") == "macro", "it is a secure macro")
	local text = button:GetAttribute("macrotext") or ""
	check(text:find("/cleartarget", 1, true) ~= nil, "clearing the target first")
	check(text:find("/targetexact Wizzlecrank's Shredder", 1, true) ~= nil, "then targeting the NPC exactly")
	h.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	check(ns.NpcHighlight.ArrowUnit() == nil, "the arrow goes with the nameplate")
	Step(h, { kind = "area", key = "area:test", title = "Test area", quests = { 858 } })
	check(ns.NpcHighlight.ArrowUnit() == nil, "a step without one NPC has no arrow")
	check(ns.NpcHighlight.TargetShown() == false, "and no target button")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A target change rebuilds the target button and calls nothing forbidden: the client refuses SetRaidTarget to addons.
do
	local h = Load()
	h.guids = { target = GUID }
	h.unitNames = { target = "Wizzlecrank's Shredder" }
	h.G.UnitGUID = function(unit)
		return h.guids[unit]
	end
	h.G.UnitName = function(unit)
		return h.unitNames[unit]
	end
	Step(h, STEP)
	h.SetCombat(true)
	h.fire("PLAYER_TARGET_CHANGED")
	h.SetCombat(false)
	h.fire("PLAYER_TARGET_CHANGED")
	check(h.counts.SetRaidTarget == nil, "the guide never asks for a raid mark")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The hint: one muted line a session, only while friendly nameplates are off, and the setting turns it off.
do
	local h = Load()
	h.nameplateShowFriends = false
	local ns = h.ns
	check(ns.NpcHighlight.Hint(STEP) == ns.L.NPC_HIGHLIGHT_HINT, "the hint explains the friendly-nameplate setting")
	check(ns.NpcHighlight.Hint(STEP) == nil, "once a session")
	local shown = Load()
	shown.nameplateShowFriends = true
	check(shown.ns.NpcHighlight.Hint(STEP) == nil, "nothing to hint when friendly nameplates are on")
	local off = Load()
	off.nameplateShowFriends = false
	off.ns.SetSetting("npcHighlight", false)
	Step(off, STEP)
	check(off.ns.NpcHighlight.Hint(STEP) == nil, "the highlight setting turns the hint off")
	check(off.ns.NpcHighlight.ArrowUnit() == nil, "and the arrow")
	check(off.ns.NpcHighlight.TargetShown() == false, "and the target button")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- No CVar is ever written.
do
	local h = Load()
	local writes = 0
	h.G.SetCVar = function()
		writes = writes + 1
	end
	Step(h, STEP)
	h.ns.NpcHighlight.Hint(STEP)
	check(writes == 0, "the guide never writes a CVar")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("npc_highlight_spec: " .. checks .. " checks passed")
