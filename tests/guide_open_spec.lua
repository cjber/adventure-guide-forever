-- Run from the repository root: luajit tests/guide_open_spec.lua
-- #664: the minimap button and Alt-G open the guide on the state the client reports once the world map has shown.
-- C_Map.OpenWorldMap posts the client's WORLD_MAP_OPEN, which opens the map a frame later, and the quest sidebar
-- inside it comes with it (UIParentPanelManager hands ShowUIPanel to its secure frame). A reopen keeps the sidebar the
-- player left and calls nothing. Reading QuestMapFrame as the opener returns read a map that had not shown yet, so
-- the guide asked the player to expand a sidebar that was about to appear, or opened on a stale, blank page.
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

---@param cvars? table<string, string>
local function Load(cvars)
	return harness.load({
		planned = true,
		panelHeight = 1200,
		spf = "v1",
		db = { autoStart = false },
		completed = { 844 },
		log = LOG,
		cvars = cvars,
	})
end

-- The minimap button, which Alt-G clicks through Bindings.xml (CLICK AdventureGuideForeverMinimapButton:LeftButton).
---@param h table
local function PressMinimap(h)
	local button = h.ns.minimapButton
	check(button ~= nil, "the minimap button exists")
	h.Click(button, "LeftButton")
end

-- With the map closed, the client shows it a frame later: the guide waits for that and opens on the sidebar the
-- client then reports, so the click never claims a sidebar the player did not collapse.
do
	local h = Load()
	h.flush()
	equal(h.map:IsShown(), false, "closed: the world map starts closed")
	PressMinimap(h)
	equal(h.map:IsShown(), false, "closed: the click has not shown the map yet")
	equal(#h.prints, 0, "closed: and says nothing about the sidebar")
	h.flush()
	equal(h.map:IsShown(), true, "closed: the client shows the map")
	equal(h.G.QuestMapFrame:IsShown(), true, "closed: with its quest sidebar")
	equal(h.ns.PanelShown(), true, "closed: the guide opens")
	equal(h.G.ForeverCore.QuestLogTabs.Selected(), "guide", "closed: on its own tab")
	equal(#h.prints, 0, "closed: without a complaint")
	equal(h.counts.OpenQuestLog, 0, "closed: the addon never opens the sidebar itself")
	equal(#h.errors, 0, "closed: errors\n" .. table.concat(h.errors, "\n"))
end

-- The map is already on screen with its sidebar: the state is final, so the click opens the guide at once.
do
	local h = Load()
	h.flush()
	h.G.C_Map.OpenWorldMap(1413)
	h.flush()
	equal(h.map:IsShown(), true, "open: the world map is up")
	equal(h.G.QuestMapFrame:IsShown(), true, "open: with its quest sidebar")
	PressMinimap(h)
	equal(h.ns.PanelShown(), true, "open: the guide shows")
	equal(h.G.ForeverCore.QuestLogTabs.Selected(), "guide", "open: on its own tab")
	equal(#h.prints, 0, "open: without a complaint")
	equal(#h.errors, 0, "open: errors\n" .. table.concat(h.errors, "\n"))
end

-- The map closes with the guide chosen and opens again: the client shows the sidebar it kept and tells nobody, so
-- the guide reads its own visibility once more rather than showing a stale page.
do
	local h = Load()
	h.flush()
	PressMinimap(h)
	h.flush()
	equal(h.ns.PanelShown(), true, "reopen: the guide opens")

	local opened, opens = h.ns.Moments.Opened, 0
	h.ns.Moments.Opened = function()
		opens = opens + 1
		return opened()
	end
	h.G.HideUIPanel(h.map)
	h.flush()
	equal(h.ns.PanelShown(), false, "reopen: closing the map hides the guide")

	PressMinimap(h)
	h.flush()
	equal(h.ns.PanelShown(), true, "reopen: the minimap button opens it again")
	equal(opens, 1, "reopen: and the guide runs its show path")
	h.ns.Moments.Opened = opened
	equal(#h.prints, 0, "reopen: without a complaint")
	equal(#h.errors, 0, "reopen: errors\n" .. table.concat(h.errors, "\n"))
end

-- The player collapsed the quest log: the map opens without one, and the guide names the control that shows it.
do
	local h = Load({ questLogOpen = "0" })
	h.flush()
	PressMinimap(h)
	h.flush()
	equal(h.map:IsShown(), true, "collapsed: the client shows the map")
	equal(h.G.QuestMapFrame:IsShown(), false, "collapsed: without the quest sidebar")
	equal(h.ns.PanelShown(), false, "collapsed: the guide stays hidden")
	equal(#h.prints, 1, "collapsed: one line says how to show it")
	check(h.prints[1]:find(h.ns.L.SIDEBAR_COLLAPSED, 1, true) ~= nil, "collapsed: naming the sidebar toggle")
	equal(h.counts.OpenQuestLog, 0, "collapsed: the addon never opens the sidebar itself")
	equal(#h.errors, 0, "collapsed: errors\n" .. table.concat(h.errors, "\n"))
end

-- The player's map is maximized, which has no quest sidebar and no toggle for it: the guide names the window button.
do
	local h = Load({ miniWorldMap = "0" })
	h.flush()
	PressMinimap(h)
	h.flush()
	equal(h.map:IsMaximized(), true, "maximized: the map opens maximized")
	equal(h.G.QuestMapFrame:IsShown(), false, "maximized: with no quest sidebar")
	equal(h.ns.PanelShown(), false, "maximized: the guide stays hidden")
	equal(#h.prints, 1, "maximized: one line says how to show the sidebar")
	check(h.prints[1]:find(h.ns.L.SIDEBAR_MAXIMIZED, 1, true) ~= nil, "maximized: naming the window button")
	equal(h.prints[1]:find(h.ns.L.SIDEBAR_COLLAPSED, 1, true), nil, "maximized: not a toggle the map does not have")
	equal(h.counts.OpenQuestLog, 0, "maximized: the addon never opens the sidebar itself")
	equal(#h.errors, 0, "maximized: errors\n" .. table.concat(h.errors, "\n"))
end

-- The map is on screen and the player collapses the sidebar in front of them: the click says what to click now.
do
	local h = Load()
	h.flush()
	h.G.C_Map.OpenWorldMap()
	h.flush()
	h.G.WorldMapFrame:SetQuestLogPanelShown(false)
	equal(h.G.QuestMapFrame:IsShown(), false, "shown: the player collapsed the sidebar")
	PressMinimap(h)
	equal(#h.prints, 1, "shown: the click says what to click")
	check(h.prints[1]:find(h.ns.L.SIDEBAR_COLLAPSED, 1, true) ~= nil, "shown: naming the sidebar toggle")
	equal(h.ns.PanelShown(), false, "shown: the guide stays hidden")
	equal(#h.errors, 0, "shown: errors\n" .. table.concat(h.errors, "\n"))
end

print(("guide_open_spec: %d checks passed"):format(checks))
