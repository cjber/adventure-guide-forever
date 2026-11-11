-- Run from the repository root: luajit tests/journey_menu_spec.lua
-- #641: a step's menu ends the chosen journey, paused or not, with one clear exit; Choose another journey says how to
-- open the guide when the map's quest sidebar is collapsed rather than doing nothing; and a right-click on a step's
-- title in the tracker opens that same menu.
local harness = dofile("tests/harness.lua")
local checks = 0

local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
}

-- ui_spec's Barrens character with the story chosen and nothing started, so a spec decides what guides it.
local function Load()
	return harness.load({
		planned = true,
		panelHeight = 1200,
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = LOG,
	})
end

-- The menu line for a button whose text is `label`, so a missing locale line counts as none rather than erroring.
local function Button(label)
	return "button: " .. tostring(label)
end

local function Entry(menu, text)
	for _, entry in ipairs(menu.entries or {}) do
		if entry.text == text then
			return entry
		end
		local found = Entry(entry, text)
		if found then
			return found
		end
	end
end

-- How many of the menu's lines read exactly `text`.
local function Count(lines, text)
	local count = 0
	for _, line in ipairs(lines) do
		if line == text then
			count = count + 1
		end
	end
	return count
end

-- A paused journey: its route stopped without the player's Stop, so nothing of ours guides it but the choice stands.
do
	local h = Load()
	local ns = h.ns
	h.flush()
	ns.Guidance.Pause()
	equal(ns.Guidance.Status(), "paused", "paused: the chosen journey's route stopped")
	equal(ns.Guidance.Owns(), false, "paused: nothing of AGF's guides it")
	equal(ns.Prefs().journey, "zone:1413", "paused: the journey stays chosen")

	h.OpenTrackerMenu(h.tracker)
	local lines = h.MenuLines()
	equal(Count(lines, Button(ns.L.END_JOURNEY)), 1, "paused: the menu offers End journey")
	equal(Count(lines, "button: " .. ns.L.STOP), 0, "paused: and not a second Stop")
	local ending = Entry(h.menu, ns.L.END_JOURNEY)
	check(ending ~= nil, "paused: the entry is there to click")
	ending.onClick()
	h.flush()
	equal(ns.Prefs().journey, nil, "paused: End journey clears the choice")
	equal(ns.Route().chosen, false, "paused: so the guide shows every card again")
	equal(ns.Guidance.Status() == "paused", false, "paused: and nothing is left paused")
	h.OpenTrackerMenu(h.tracker)
	equal(Count(h.MenuLines(), Button(ns.L.END_JOURNEY)), 0, "paused: nothing is left to end")
	equal(#h.errors, 0, "paused: errors\n" .. table.concat(h.errors, "\n"))
end

-- A running journey: the same single exit, and it still stops the route Go started.
do
	local h = Load()
	local ns = h.ns
	h.flush()
	check(ns.Guidance.Navigate(ns.Route().steps[1]), "running: the route guides the player")
	equal(ns.Guidance.Owns(), true, "running: AGF's guidance runs")
	h.OpenTrackerMenu(h.tracker)
	local lines = h.MenuLines()
	equal(Count(lines, Button(ns.L.END_JOURNEY)), 1, "running: the menu offers End journey")
	equal(Count(lines, "button: " .. ns.L.STOP), 0, "running: one exit, not the old Stop as well")
	local cancels = h.spf.Cancel
	Entry(h.menu, ns.L.END_JOURNEY).onClick()
	h.flush()
	equal(h.spf.Cancel, cancels + 1, "running: End journey stops the route Go started")
	equal(ns.Prefs().journey, nil, "running: and clears the choice")
	equal(ns.Guidance.Owns(), false, "running: nothing guides afterwards")
	equal(#h.errors, 0, "running: errors\n" .. table.concat(h.errors, "\n"))
end

-- Choose another journey with the quest sidebar collapsed: the guide cannot be shown, so it says how instead of
-- doing nothing, and it never opens the sidebar itself (taint).
do
	local h = Load()
	local ns = h.ns
	h.flush()
	ns.OpenPanel()
	h.flush()
	equal(ns.PanelShown(), true, "sidebar: the guide shows while the sidebar is up")

	h.G.WorldMapFrame:SetQuestLogPanelShown(false)
	equal(h.G.QuestMapFrame:IsShown(), false, "sidebar: collapsed")
	local prints = #h.prints
	ns.OpenPanel()
	h.flush()
	equal(#h.prints, prints + 1, "sidebar: opening the guide says one line")
	check(h.prints[#h.prints]:find(ns.L.SIDEBAR_COLLAPSED, 1, true) ~= nil, "sidebar: it says to expand the sidebar")
	equal(ns.PanelShown(), false, "sidebar: the guide stays hidden with the sidebar")
	equal(h.counts.OpenQuestLog, 0, "sidebar: the addon never opens it")

	h.G.WorldMapFrame:SetQuestLogPanelShown(true)
	prints = #h.prints
	ns.OpenPanel()
	h.flush()
	equal(#h.prints, prints, "sidebar: expanded, the guide opens without a complaint")
	equal(ns.PanelShown(), true, "sidebar: and shows")
	equal(#h.errors, 0, "sidebar: errors\n" .. table.concat(h.errors, "\n"))
end

-- Right-clicking a step's title in the tracker opens the menu its section header has, for that step.
do
	local h = Load()
	local ns = h.ns
	h.flush()
	local route = ns.Route()
	local step = ns.Guidance.CurrentStep()
	check(step ~= nil, "title: the tracker shows a step")
	local block = h.tracker.liveBlocks[step.key]
	check(block ~= nil, "title: its block is laid out")

	h.OpenTrackerMenu(h.tracker)
	local expected = h.MenuLines()
	h.menu = nil
	h.tracker:OnBlockHeaderClick(block, "RightButton")
	check(h.menu ~= nil, "title: a right-click opens a menu")
	equal(table.concat(h.MenuLines(), "\n"), table.concat(expected, "\n"), "title: the step's own menu")
	equal(#h.errors, 0, "title: errors\n" .. table.concat(h.errors, "\n"))

	-- The menu belongs to the block's step: a later step's title titles its own menu, not the one under way.
	local later = route.steps[2]
	if later then
		h.menu = nil
		h.tracker:OnBlockHeaderClick({ id = later.key }, "RightButton")
		check(h.menu ~= nil, "title: a later step's title opens a menu")
		equal(h.menu.entries[1].text, later.title, "title: the menu belongs to that step")
		equal(#h.errors, 0, "title, later step: errors\n" .. table.concat(h.errors, "\n"))
	end
end

print(("journey_menu_spec: %d checks passed"):format(checks))
