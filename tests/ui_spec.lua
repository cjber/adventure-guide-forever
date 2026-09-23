-- Run from the repository root: luajit tests/ui_spec.lua
-- Headless UI checks (docs/plan.md §1.1) through tests/harness.lua. What they cannot reach is a /reload check.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function clean(h, label)
	equal(#h.errors, 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
end

-- A level-18 orc shaman in The Barrens with one quest ready to hand in and one under way.
local function Load(spf)
	return harness.load({
		spf = spf or nil,
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
		},
	})
end

local function Shown(h, test)
	return h.Find(function(frame)
		return frame:IsVisible() and test(frame)
	end)
end

for _, spf in ipairs({ false, "v1", "v1+" }) do
	local label = spf or "no Shortest Path"
	local h = Load(spf)
	clean(h, label .. ": load")
	equal(h.G.ShortestPathForever ~= nil, spf ~= false, label .. ": Shortest Path global")
	equal(h.G.TweaksForever, nil, label .. ": no Tweaks Forever")
	equal(h.G.LegacyForever, nil, label .. ": no Legacy Forever")
	equal(h.ns.Route().steps[1].key, "turnin:845", label .. ": the hand-in leads the route")

	-- Blizzard's displayMode is never written, whatever the player clicks (Panel.lua ShowGuide).
	local panel, questsFrame = h.G.AdventureGuideForeverPanel, h.questMap.QuestsFrame
	h.ns.OpenPanel()
	h.flush()
	equal(panel:IsVisible(), true, label .. ": the guide opens")
	equal(questsFrame:IsShown(), false, label .. ": the quest list steps aside")
	h.Click(Shown(h, function(frame)
		return frame.BestFit ~= nil
	end)[1])
	h.flush()
	h.Click(Shown(h, function(frame)
		return frame.SkipButton ~= nil
	end)[1])
	h.flush()
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	equal(panel:IsShown(), false, label .. ": the Quests tab closes the guide")
	equal(questsFrame:IsShown(), true, label .. ": the quest list is back")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks["turnin:845"], "LeftButton")
	h.flush()
	equal(panel:IsShown(), true, label .. ": a tracker click opens the guide")
	h.TriggerEvent("QuestLog.SetDisplayMode")
	equal(panel:IsShown(), false, label .. ": a display mode change closes the guide")
	h.ns.OpenPanel()
	h.G.QuestMapFrame_ShowQuestDetails(845)
	equal(panel:IsShown(), false, label .. ": quest details close the guide")
	equal(h.counts.displayModeWrites, 0, label .. ": displayMode writes")
	clean(h, label .. ": clicks")
	-- The trap itself: a write raises and is counted.
	equal(
		pcall(function()
			h.G.QuestMapFrame.displayMode = "MapLegend"
		end),
		false,
		label .. ": a displayMode write raises"
	)
	equal(h.counts.displayModeWrites, 1, label .. ": the trap counts writes")
end

-- WFA-13: nothing runs per frame while idle, and a refresh reuses the frames it has.
local function IdleUpdates(h)
	local busy = 0
	for _, frame in ipairs(h.frames) do
		busy = busy + (frame.scripts.OnUpdate and 1 or 0)
		for _, group in ipairs(frame.animationGroups or {}) do
			busy = busy + (group:IsPlaying() and 1 or 0)
		end
	end
	return busy + h.counts.tickers
end

for _, spf in ipairs({ false, "v1" }) do
	local label = spf or "no Shortest Path"
	local h = Load(spf)
	equal(IdleUpdates(h), 0, label .. ": per-frame work after loading")
	h.ns.OpenPanel()
	h.flush()
	local created = h.counts.CreateFrame
	for _ = 1, 10 do
		h.ns.Invalidate()
		h.flush()
	end
	equal(h.counts.CreateFrame - created, 0, label .. ": frames created by 10 refreshes")
	equal(#h.pins.AdventureGuideForeverPinTemplate, #h.ns.Route().steps, label .. ": the refreshes drew the route")
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	h.flush()
	equal(IdleUpdates(h), 0, label .. ": per-frame work once the guide is closed")
	clean(h, label .. ": idle")
end

local function same(actual, expected, label)
	equal(table.concat(actual, "\n"), table.concat(expected, "\n"), label)
end

-- Map pins: a refresh replaces, never adds; removal leaves none; tooltips and the tracker menu read as today.
-- The expected text is today's. The features that change it (F6, F7, F10) change these lists in the same
-- commit, until they read as design §2.8 and §2.9.
for _, spf in ipairs({ false, "v1" }) do
	local label = spf or "no Shortest Path"
	local click = spf and "instruction: Click to travel with Shortest Path" or "instruction: Click to set a waypoint"
	local h = Load(spf)
	local provider, ns = h.providers[1], h.ns
	h.G.OpenQuestLog()
	h.flush()
	local function Live()
		return #h.pins.AdventureGuideForeverPinTemplate + #h.pins.AdventureGuideForeverGiverPinTemplate
	end
	provider:RefreshAllData()
	local first = Live()
	provider:RefreshAllData()
	equal(Live(), first, label .. ": a second refresh keeps the pin count")
	equal(#h.pins.AdventureGuideForeverPinTemplate, #ns.Route().steps, label .. ": one ring per step on this map")

	local ring = h.pins.AdventureGuideForeverPinTemplate[1]
	equal(ring.Number:GetAtlas(), "services-number-1", label .. ": the ring's numeral")
	h.Hover(ring)
	-- With Shortest Path, step 1 adds its travel line; the stub answers 360 s.
	local expected = { "title: 1. Turn in: The Zhevra", "highlight: ready to hand in" }
	expected[#expected + 1] = spf and "highlight: About 6 min away" or nil
	expected[#expected + 1] = "normal: ready to hand in"
	expected[#expected + 1] = click
	same(h.tooltip, expected, label .. ": ring tooltip")
	equal(ring.Glow:IsShown(), true, label .. ": hover glow")
	ring:OnMouseLeave()
	equal(ring.Glow:IsShown(), false, label .. ": glow off after hover")

	-- Stonetalon has quest givers and no route step, so every eligible giver gets a "!".
	h.map:SetMapID(1442)
	local givers = ns.Model.Givers(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), 1442)
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, #givers, label .. ": a giver pin per eligible giver")
	equal(#h.pins.AdventureGuideForeverPinTemplate, 0, label .. ": no rings off the route's map")
	local giverPin = h.pins.AdventureGuideForeverGiverPinTemplate[1]
	h.Hover(giverPin)
	equal(h.tooltip[1], "title: " .. giverPin.giver.title, label .. ": giver tooltip title")
	equal(#h.tooltip, #giverPin.giver.quests + 2, label .. ": a giver tooltip line per quest")
	equal(h.tooltip[#h.tooltip], click, label .. ": giver tooltip instruction")

	provider:RemoveAllData()
	equal(Live(), 0, label .. ": RemoveAllData leaves no pins")

	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks["turnin:845"], "RightButton")
	same(h.MenuLines(), {
		"title: Turn in: The Zhevra",
		"button: Skip",
		"button: Change route",
		"button: Go",
	}, label .. ": tracker menu")
	clean(h, label .. ": pins")
end

-- F0: a rebuild asks Shortest Path nothing; step 1's travel line is one estimate, in the frame after.
for _, spf in ipairs({ "v1", "v1+" }) do
	local h = Load(spf)
	local function Estimates()
		return h.spf.Estimate + (h.spf.EstimateDetail or 0)
	end
	local before = Estimates()
	h.MovePlayer(1413, 0.6, 0.4)
	h.ns.Invalidate()
	h.flush()
	equal(Estimates() - before, 1, spf .. ": a move and a rebuild cost exactly one estimate")
	equal(h.ns.Integrations.Travel(h.ns.Route().steps[1]), "About 6 min away", spf .. ": step 1's travel line")
	equal(h.ns.Integrations.Travel(h.ns.Route().steps[2]), nil, spf .. ": no line for other steps")
	equal(Estimates() - before, 1, spf .. ": reading the line asks nothing")
	-- An invalidation between the rebuild frame and the travel frame: the travel frame must not rebuild as well.
	local plan, builds = h.ns.Model.Plan, 0
	h.ns.Model.Plan = function(...)
		builds = builds + 1
		return plan(...) -- multi-value: the wrapper is transparent
	end
	h.ns.Invalidate()
	h.tick()
	h.ns.Invalidate()
	h.tick()
	equal(builds, 2, spf .. ": one build per rebuild frame, none in the skipped travel frame")
	h.flush()
	equal(Estimates() - before, 2, spf .. ": the second rebuild's travel frame asks once")
	h.ns.Model.Plan = plan
	clean(h, spf .. ": travel")
end

-- The contract (types/Namespace.lua AGFSPFAPI): version 1 with every required function, or no Shortest Path at all.
do
	local h = Load("v1")
	local api = h.G.ShortestPathForever.API
	equal(h.ns.Integrations.Provider(), "Shortest Path", "contract: v1 is used")
	local cancel = api.Cancel
	api.Cancel = nil
	equal(h.ns.Integrations.Provider(), nil, "contract: a missing required function reads as absent")
	api.Cancel, api.version = cancel, 2
	equal(h.ns.Integrations.Provider(), nil, "contract: another version reads as absent")
	h.ns.Integrations.Navigate(h.ns.Route().steps[1])
	equal(h.counts.SetUserWaypoint, 1, "contract: absent falls back to the native waypoint")
	clean(h, "contract")
end

-- Go: Shortest Path's answer decides. When it declines or is absent, the native waypoint takes step 1, on any map
-- the client allows one on; where it allows none, nothing is set and Navigate returns false.
for _, case in ipairs({
	{ label = "Shortest Path accepts", spf = "v1", routes = 1, waypoints = 0 },
	{ label = "Shortest Path declines", spf = "v1", declines = true, routes = 1, waypoints = 1 },
	{ label = "no Shortest Path", routes = 0, waypoints = 1 },
	{ label = "declined, no waypoint map", spf = "v1", declines = true, blocked = true, routes = 1, waypoints = 0 },
	{ label = "absent, no waypoint map", blocked = true, routes = 0, waypoints = 0 },
}) do
	local h = Load(case.spf)
	local step = h.ns.Route().steps[1]
	h.spfDeclines = case.declines
	h.noWaypoint[step.map] = case.blocked
	local guided = h.ns.Integrations.Navigate(step)
	equal(guided, not case.blocked, case.label .. ": Navigate's answer")
	equal(h.spf and h.spf.NavigateRoute or 0, case.routes, case.label .. ": NavigateRoute calls")
	equal(h.counts.SetUserWaypoint, case.waypoints, case.label .. ": native waypoints")
	if case.waypoints == 1 then
		local point = h.waypoint
		equal(
			("%d %.4f %.4f"):format(point.uiMapID, point.position.x, point.position.y),
			("%d %.4f %.4f"):format(step.map, step.x, step.y),
			case.label .. ": the waypoint is step 1"
		)
		equal(h.superTracked, true, case.label .. ": the waypoint is tracked")
	end
	equal(h.ns.Integrations.Guiding(), case.spf ~= nil and not case.declines, case.label .. ": Shortest Path guides")
	clean(h, case.label)
end

-- Chat copy comes from ns.L: an unknown command prints the three help lines, in order.
do
	local h = Load(false)
	local before = #h.prints
	h.Slash("help")
	local L = h.ns.L
	for index, line in ipairs({ L.HELP_OPEN, L.HELP_AUDIT, L.HELP_DUMP }) do
		equal(h.prints[before + index]:sub(-#line), line, "L: help line " .. index)
	end
	equal(#h.prints, before + 3, "L: three help lines")
	-- Map names come from the client (C_Map.GetMapInfo), which the planner prefers over the data's English.
	equal(h.ns.State.MapName(1453), "Map 1453", "L: the client's map name")
	h.G.C_Map.GetMapInfo = function() end
	equal(h.ns.State.MapName(1453), nil, "L: no client name, so the data's")
	clean(h, "L")
end

-- /agf dump: a plain-table snapshot in the saved variables, kept across /reload and dropped at the next login.
do
	local h = Load(false)
	h.ns.OpenPanel()
	h.flush()
	h.Slash("dump")
	local dump = h.G.AdventureGuideForeverDB.dump
	equal(dump.build, "1.60.1.69913", "dump: build")
	equal(dump.layout[1].path, "AdventureGuideForeverPanel", "dump: the layout starts at the panel")
	local keys = {}
	for index, step in ipairs(h.ns.Route().steps) do
		keys[index] = step.key
	end
	same(dump.route, keys, "dump: route keys")
	equal(dump.tracker ~= nil and #dump.tracker > 0, true, "dump: tracker entries")
	equal(#dump.frames > 0, true, "dump: frames listed")
	local busy = 0
	for _, frame in ipairs(dump.frames) do
		busy = busy + (frame.onUpdate and 1 or 0)
	end
	equal(busy, 0, "dump: no frame runs an OnUpdate")
	equal(h.counts.displayModeWrites, 0, "dump: displayMode writes")
	clean(h, "dump")
	equal(
		harness.load({ db = h.G.AdventureGuideForeverDB, initialLogin = false }).G.AdventureGuideForeverDB.dump,
		dump,
		"dump: kept by /reload"
	)
	equal(
		harness.load({ db = h.G.AdventureGuideForeverDB, initialLogin = true }).G.AdventureGuideForeverDB.dump,
		nil,
		"dump: dropped at login"
	)
end

-- The golden layout: any change to what the guide draws shows as a reviewable diff of tests/golden/layout.json.
do
	local json, diff = dofile("tests/json.lua"), dofile("tests/dump_diff.lua")
	local h = Load(false)
	h.ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	local current = json.encode({ layout = h.ns.DumpLayout(panel, h.Describe) })
	local goldenPath = "tests/golden/layout.json"
	if os.getenv("AGF_UPDATE_GOLDEN") == "1" then
		local handle = assert(io.open(goldenPath, "w"))
		handle:write(current)
		handle:close()
	end
	local handle = assert(io.open(goldenPath), "no golden layout: run with AGF_UPDATE_GOLDEN=1")
	local stored = handle:read("*a")
	handle:close()
	equal(current == stored, true, "golden: layout.json matches (AGF_UPDATE_GOLDEN=1 rewrites it)")
	equal(json.encode(json.decode(stored)), stored, "golden: json round trip")

	-- The in-game diff, fed a dump taken the way /agf dump takes it.
	local golden, game = json.decode(stored).layout, h.ns.DumpLayout(panel)
	local differences, onlyInGame = diff.Compare(golden, game)
	equal(#differences, 0, "dump_diff: the headless dump matches\n" .. table.concat(differences, "\n"))
	equal(onlyInGame, 0, "dump_diff: no regions only in game")
	for _, entry in ipairs(game) do
		if entry.atlas then
			entry.atlas = "changed"
			break
		end
	end
	for _, entry in ipairs(game) do
		if entry.path == "AdventureGuideForeverPanel.DropdownButton[1]" then
			entry.size = { 15, 16 } -- UIPanelIconDropdownButtonTemplate's own <Size>, applied only in game
		end
	end
	game[#game + 1] = { path = "AdventureGuideForeverPanel.NineSlice", type = "Frame", anchors = {} }
	differences, onlyInGame = diff.Compare(golden, game)
	equal(#differences, 1, "dump_diff: a changed atlas is one difference")
	equal(onlyInGame, 1, "dump_diff: stock chrome is counted, not failed")
	clean(h, "golden")
end

print(("ui_spec: %d checks passed"):format(checks))
