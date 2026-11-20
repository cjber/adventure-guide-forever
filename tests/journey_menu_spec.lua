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

-- #794: core owns ordering, dispatch and the target passed for a block title.
do
	local h = Load()
	h.flush()
	local ns, tracker = h.ns, h.tracker
	check(tracker.AddHeaderMenuEntries == nil, "contract: no deprecated header builder")
	check(type(tracker.trackerClick) == "function", "contract: left-click is registered")
	h.OpenTrackerMenu(tracker)
	local entries = h.menu.entries
	equal(entries[1].kind, "title", "order: title first")
	equal(entries[2].text, ns.L.GO, "order: primary second")
	-- Core 1.15.3 closes the menu with a divider, its Lock the tracker checkbox and the Tracker submenu.
	equal(entries[#entries - 4].text, ns.L.CHOOSE_JOURNEY, "order: open after actions")
	equal(entries[#entries - 3].text, ns.L.END_JOURNEY, "order: end last addon action")
	equal(entries[#entries - 2].kind, "divider", "order: core divider")
	equal(entries[#entries - 1].text, "Lock the tracker", "order: core lock after the divider")
	equal(entries[#entries].text, "Tracker", "order: core settings last")
	local step = ns.Guidance.CurrentStep()
	local block = tracker.liveBlocks[step.key]
	local menu, click = tracker.trackerMenu, tracker.trackerClick
	local seen
	tracker.trackerMenu = function(target, builder)
		seen = target
		menu(target, builder)
	end
	tracker:OnBlockHeaderClick(block, "RightButton")
	equal(seen.kind, "block", "target: block kind")
	equal(seen.block, block, "target: actual block")
	equal(seen.id, step.key, "target: block id")
	tracker.trackerClick = function(target, button)
		seen = target
		return click(target, button)
	end
	tracker:OnBlockHeaderClick(block, "LeftButton")
	equal(seen.block, block, "click: host dispatches actual block")
	check(tracker.trackerClickHint(seen) ~= nil, "click: core has an action hint")
	equal(#h.errors, 0, "contract: no errors")
end

-- Non-step titles also open useful menus, rather than inheriting a current step's Go action.
do
	local h = Load()
	h.flush()
	local ns, opened = h.ns, 0
	ns.OpenPanel = function()
		opened = opened + 1
	end
	for _, id in ipairs({ "story-complete", "story-beat", "journey-complete", "moment", "loading", "rxp-ongoing" }) do
		h.tracker:OnBlockHeaderClick({ id = id }, "RightButton")
		check(Entry(h.menu, ns.L.GO) == nil, id .. ": no unrelated Go")
		check(Entry(h.menu, ns.L.END_JOURNEY) ~= nil, id .. ": journey can end")
		Entry(h.menu, ns.L.CHOOSE_JOURNEY).onClick()
	end
	equal(opened, 6, "non-step menus: Open opens the guide")
	h.tracker:OnBlockHeaderClick({ id = "polestar" }, "RightButton")
	check(Entry(h.menu, ns.L.TRACKER_TAKE_OVER) ~= nil, "Polestar: explicit take-over action")
	h.combat = true
	h.tracker:OnBlockHeaderClick({ id = "quest-areas" }, "RightButton")
	check(
		not Entry(h.menu, ns.L.TRACKER_QUEST_AREAS_SHOW):IsEnabled(),
		"quest areas: blocked action disabled in combat"
	)
	check(not Entry(h.menu, ns.L.CHOOSE_JOURNEY):IsEnabled(), "Open: disabled in combat")
	check(Entry(h.menu, ns.L.SHOW_QUEST) == nil, "combat: no Show quest")
	h.combat = false
	h.G.SetCVar("questPOI", "0")
	h.tracker:OnBlockHeaderClick({ id = "quest-areas" }, "RightButton")
	Entry(h.menu, ns.L.TRACKER_QUEST_AREAS_SHOW).onClick()
	equal(h.cvars.questPOI, "1", "quest areas: menu action restores areas")
	equal(#h.errors, 0, "non-step menus: no errors")
end

-- Hints describe the actual left-click action, independently of menu labels.
do
	local h = Load()
	h.flush()
	local ns, tracker = h.ns, h.tracker
	local function Hint(block)
		return tracker.trackerClickHint({ kind = "block", block = block, module = tracker })
	end
	equal(Hint(nil), nil, "section: no click hint")
	equal(Hint({ id = "quest-areas" }), "show quest areas", "quest areas hint")
	equal(Hint({ id = "polestar" }), "take over the route", "take-over hint")
	ns.SetSetting("informationOnly", true)
	equal(Hint({ id = "polestar" }), nil, "information only: no take-over hint")
	for _, id in ipairs({ "journey-complete", "moment" }) do
		equal(Hint({ id = id }), "open the guide", id .. " hint")
	end
	for _, id in ipairs({ "story-complete", "story-beat", "loading", "rxp-ongoing" }) do
		equal(Hint({ id = id }), nil, id .. ": no click hint")
	end
	local step = ns.Guidance.CurrentStep()
	local block = tracker.liveBlocks[step.key]
	ns.InLog = function()
		return true
	end
	equal(Hint(block), "show the quest", "logged quest hint")
	ns.InLog = function()
		return false
	end
	equal(Hint(block), "open the guide", "unlogged quest hint")
	local aside = {
		key = "profession:164:2",
		category = "professions",
		text = "Learn the next rank",
		icon = "class",
		place = { map = 1413, x = 0.5, y = 0.5 },
	}
	ns.Asides.Current = function()
		return aside
	end
	equal(Hint({ id = "aside" }), "go there", "aside hint")
	-- Both surfaces consume the same builder; tracker Go occupies Primary.
	local shared = ns.Asides.Menu
	check(type(shared) == "function", "aside: shared entry builder")
	local calls = 0
	ns.Asides.Menu = function(...)
		calls = calls + 1
		return shared(...)
	end
	ns.Asides.Open(tracker, aside)
	local panel = h.MenuLines()
	tracker:OnBlockHeaderClick({ id = "aside" }, "RightButton")
	equal(calls, 2, "aside: panel and tracker share entry builder")
	local lines = h.MenuLines()
	for i, line in ipairs(panel) do
		equal(lines[i], line, "aside shared entry " .. i)
	end
	equal(h.menu.entries[2].text, ns.L.GO, "aside: Go is Primary")
	check(Entry(h.menu, ns.L.SKIP) ~= nil, "aside: Skip")
	check(Entry(h.menu, ns.L.NOT_INTERESTED) ~= nil, "aside: Not interested")
	ns.SetSetting("wanderer", true)
	equal(Hint({ id = "aside" }), nil, "wanderer: no aside hint")
	tracker:OnBlockHeaderClick({ id = "aside" }, "RightButton")
	check(Entry(h.menu, ns.L.GO) == nil, "wanderer: no aside Go")
	ns.SetSetting("wanderer", false)
	aside.place = nil
	equal(Hint({ id = "aside" }), nil, "unplaced aside: no hint")
	tracker:OnBlockHeaderClick({ id = "aside" }, "RightButton")
	check(Entry(h.menu, ns.L.GO) == nil, "unplaced aside: no Go")
end

print(("journey_menu_spec: %d checks passed"):format(checks))
