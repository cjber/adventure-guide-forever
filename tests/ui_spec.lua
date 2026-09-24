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

-- A level-18 orc shaman in The Barrens with one quest ready to hand in and one under way. `db` is the account's
-- saved settings; the map marks are off unless it turns them on.
local PINS_ON = { showMapPins = true, showQuestGivers = true }
local function Load(spf, db)
	return harness.load({
		spf = spf or nil,
		db = db,
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
	-- F6: the first step, a quest in the log, opens in Blizzard's details from its row and from the tracker; in
	-- combat the row turns the map and the tracker opens the guide instead.
	local first = h.ns.Route().steps[1]
	local function Row()
		return Shown(h, function(frame)
			return frame.SkipButton ~= nil
		end)[1]
	end
	h.Click(Row())
	h.flush()
	equal(table.concat(h.questDetails, " "), tostring(first.quests[1]), label .. ": a row in the log opens the quest")
	equal(panel:IsShown(), false, label .. ": in place of the guide")
	h.ns.OpenPanel()
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	equal(panel:IsShown(), false, label .. ": the Quests tab closes the guide")
	equal(questsFrame:IsShown(), true, label .. ": the quest list is back")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[first.key], "LeftButton")
	h.flush()
	equal(#h.questDetails, 2, label .. ": so does a tracker click")
	h.SetCombat(true)
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[first.key], "LeftButton")
	h.flush()
	equal(panel:IsShown(), true, label .. ": a tracker click in combat opens the guide")
	h.Click(Row())
	equal(#h.questDetails, 2, label .. ": no quest details in combat")
	h.SetCombat(false)
	h.flush()
	h.ns.OpenPanel()
	h.flush()
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
	local h = Load(spf, PINS_ON)
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
	local h = Load(spf, PINS_ON)
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

	-- The story card's step tells its chapter under the title (design §2.9).
	h.map:SetMapID(1413)
	ns.Prefs().journey = ns.Route().journeys[2].key
	ns.Invalidate()
	h.flush()
	local chapter
	for _, pin in ipairs(h.pins.AdventureGuideForeverPinTemplate) do
		chapter = pin.step.chapter and pin or chapter
	end
	h.Hover(chapter)
	equal(h.tooltip[2], "normal: Chapter 1 of 5", label .. ": the story's ring tells its chapter")
	ns.Prefs().journey = nil
	ns.Invalidate()
	h.flush()

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

-- F1, the map budget: a fresh install draws no mark with the tab closed; opted in, at most 9 rings and exactly the
-- zone's eligible givers, which stay while Shortest Path guides; either switch off hides every giver. The rings,
-- the open guide's preview included, step aside while it guides.
do
	local h = Load(false)
	h.G.OpenQuestLog()
	h.flush()
	for _ = 1, 10 do
		h.providers[1]:RefreshAllData()
	end
	equal(h.counts.AcquirePin, 0, "map budget: a fresh install draws nothing")
	equal(h.G.AdventureGuideForeverDB.showMapPins, false, "map budget: pins are opt-in")
	equal(h.G.AdventureGuideForeverDB.showQuestGivers, false, "map budget: givers are opt-in")
	clean(h, "map budget: fresh")
end
for _, case in ipairs({
	{ label = "both on", db = PINS_ON, givers = true },
	{ label = "pins only", db = { showMapPins = true }, givers = false },
	{ label = "givers only", db = { showQuestGivers = true }, givers = false },
}) do
	local label = "map budget, " .. case.label
	local h = Load("v1", case.db)
	local ns = h.ns
	h.G.OpenQuestLog()
	h.flush()
	local rings = #h.pins.AdventureGuideForeverPinTemplate
	equal(rings <= ns.Model.MAX_STEPS, true, label .. ": at most 9 rings")
	equal(rings, case.db.showMapPins and #ns.Route().steps or 0, label .. ": a ring per step, only with pins on")
	h.map:SetMapID(1442)
	local givers = #ns.Model.Givers(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), 1442)
	equal(givers > 0, true, label .. ": Stonetalon has givers")
	local expected = case.givers and givers or 0
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, expected, label .. ": givers")
	ns.Integrations.Navigate(ns.Route().steps[1])
	equal(ns.Integrations.Guiding(), true, label .. ": Shortest Path guides")
	h.map:SetMapID(1413)
	equal(#h.pins.AdventureGuideForeverPinTemplate, 0, label .. ": rings step aside while Shortest Path guides")
	ns.OpenPanel()
	h.flush()
	h.map:SetMapID(1413)
	equal(#h.pins.AdventureGuideForeverPinTemplate, 0, label .. ": the guide's preview steps aside as well")
	h.map:SetMapID(1442)
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, expected, label .. ": givers stay while it guides")
	clean(h, label)
end
-- Choosing another card while Shortest Path guides: it still walks the old route, so the new journey's givers
-- are drawn, not left to stops nobody draws.
do
	local h = Load("v1", PINS_ON)
	local ns = h.ns
	h.G.OpenQuestLog()
	h.flush()
	ns.Integrations.Navigate(ns.Route().steps[1])
	local nextZone = ns.Route().journeys[3]
	equal(nextZone.kind, "nextzone", "guided givers: a next-zone card")
	ns.Prefs().journey = nextZone.key
	ns.Invalidate()
	h.flush()
	h.map:SetMapID(nextZone.map)
	local givers = ns.Model.Givers(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), nextZone.map)
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, #givers, "guided givers: every giver on the new card's map")
	clean(h, "guided givers")
end
do
	local h = Load(false, { showMapPins = true })
	equal(h.ns.Setting("showMapPins"), true, "map budget: a saved true survives the new default")
	equal(h.G.AdventureGuideForeverDB.showMapPins, true, "map budget: and stays saved")
	clean(h, "map budget: saved")
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

-- The combat rule (docs/plan.md §1.1 assert 6): in combat a rebuild runs only the cheap path, which still shows the
-- log's news, and the full build runs once, when combat ends. No timer: PLAYER_REGEN_ENABLED brings it.
do
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
	}
	local h = harness.load({ completed = { 844 }, log = log })
	local ns, before = h.ns, h.modelCalls.Journeys
	local story = ns.Route().journeys[2]
	h.SetCombat(true)
	for _ = 1, 10 do
		ns.Invalidate()
		h.flush()
	end
	log[2].complete = true
	ns.Invalidate()
	equal(ns.Route().steps ~= nil, true, "combat: the lazy path answers")
	h.flush()
	equal(h.modelCalls.Journeys - before, 0, "combat: no full build in combat")
	equal(ns.Route().journey, "carry", "combat: the chosen card holds")
	local keys = {}
	for _, step in ipairs(ns.Route().steps) do
		keys[step.key] = true
	end
	equal(keys["turnin:843"], true, "combat: a quest finished mid-fight is ready to hand in")
	equal(keys["objective:843"], nil, "combat: its objective step is gone")
	equal(
		story ~= nil and ns.Route().journeys[2] == story,
		true,
		"combat: the story stays as the last full build left it"
	)
	equal(h.counts.tickers, 0, "combat: no timer waits for the fight to end")
	-- A skip mid-fight takes effect at once, on the story's card as on the log's.
	ns.Prefs().journey = story.key
	ns.Invalidate()
	h.flush()
	local skipped = ns.Route().steps[1].key
	ns.Skip(skipped)
	h.flush()
	equal(ns.Route().steps[1].key ~= skipped, true, "combat: a skipped story step goes at once")
	equal(#ns.Route().steps, #story.steps - 1, "combat: and only that step")
	equal(h.modelCalls.Journeys - before, 0, "combat: still no full build")
	h.SetCombat(false)
	h.flush()
	equal(h.modelCalls.Journeys - before, 1, "combat: one full build once it ends")
	h.SetCombat(false)
	h.flush()
	equal(h.modelCalls.Journeys - before, 1, "combat: the owed build runs once")
	clean(h, "combat")
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
-- the client allows one on; where it allows none, nothing is set, the red error line says so and Navigate returns
-- false.
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
	local told = case.blocked and "You can't place a pin on this map." or ""
	equal(table.concat(h.uiErrors, "|"), told, case.label .. ": the player is told only when nothing guides")
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

-- A refusal after an earlier Go cancels that journey, so Shortest Path's old line never stays beside the waypoint.
do
	local h = Load("v1")
	local step = h.ns.Route().steps[1]
	h.ns.Integrations.Navigate(step)
	equal(h.ns.Integrations.Guiding(), true, "declined later: the first Go guides")
	h.spfDeclines, h.noWaypoint[step.map] = true, true
	equal(h.ns.Integrations.Navigate(step), false, "declined later, no waypoint map: nothing new guides")
	equal(h.spf.Cancel, 0, "declined later, no waypoint map: the earlier journey is kept")
	h.noWaypoint[step.map], h.uiErrors = nil, {}
	equal(h.ns.Integrations.Navigate(step), true, "declined later: the waypoint guides")
	equal(h.spf.Cancel, 1, "declined later: the earlier journey is cancelled")
	equal(h.ns.Integrations.Guiding(), false, "declined later: Shortest Path no longer guides")
	equal(h.counts.SetUserWaypoint, 1, "declined later: the native waypoint is set")
	clean(h, "declined later")
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

-- The journey card template (docs/design.md §2.2): the renown card at 0.77 scale, its highlight the card's own art.
do
	local h = Load(false)
	local card = h.G.CreateFrame("Button", nil, h.G.UIParent, "AdventureGuideForeverJourneyCardTemplate")
	equal(("%dx%d"):format(card:GetSize()), "288x86", "card: 288x86") -- multi-value: width and height
	equal(("%dx%d"):format(card.IconFrame:GetSize()), "46x46", "card: 46x46 ring") -- multi-value: width and height
	equal(card.NormalTexture:GetAtlas(), "ui-journeys-renown-button", "card: the renown art")
	equal(card.highlightAtlas, "ui-journeys-renown-button", "card: highlighted with its own art")
	equal(card.PushedTexture:IsShown(), false, "card: the pressed art waits for a press")
	clean(h, "card")
end

-- The guide (F2): at most three cards, the chosen one pressed and followed by its steps, every card 288x86 with a
-- 46x46 ring, in the dumped layout the client's own dump is compared with.
do
	local h = Load(false)
	h.ns.OpenPanel()
	h.flush()
	local route, shown, pressed, lit = h.ns.Route(), 0, 0, 0
	for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
		if entry.path:match("%.Button%[%d%]$") and entry.size and entry.size[2] == 86 then
			shown = shown + 1
			lit = lit + (entry.highlightLocked and 1 or 0)
			equal(("%dx%d"):format(entry.size[1], entry.size[2]), "288x86", "guide: " .. entry.path .. " is 288x86")
		elseif entry.path:match("%.IconFrame$") then
			equal(("%dx%d"):format(entry.size[1], entry.size[2]), "46x46", "guide: " .. entry.path .. " is 46x46")
		elseif entry.path:match("NormalTexture$") and entry.atlas == "ui-journeys-renown-button-pressed" then
			pressed = pressed + 1
		end
	end
	equal(shown, #route.journeys, "guide: a card per journey")
	equal(shown >= 1 and shown <= 3, true, "guide: one to three cards")
	equal(pressed, 1, "guide: only the chosen card is pressed")
	equal(lit, 1, "guide: and only it stays lit, so it reads as chosen in game")
	local rows = Shown(h, function(frame)
		return frame.SkipButton ~= nil
	end)
	equal(#rows, #route.steps, "guide: only the chosen card's steps are listed")
	-- The dump holds only what is shown.
	local function Says(each, text)
		local count = 0
		for _, entry in ipairs(each.ns.DumpLayout(each.G.AdventureGuideForeverPanel, each.Describe)) do
			count = count + (entry.text == text and 1 or 0)
		end
		return count
	end
	equal(Says(h, h.ns.L.NOTHING_NEARBY), 0, "guide: no empty line beside the cards")

	-- F4: the chosen story shows its chapter track, one square per proven chapter, and never a later chapter's title.
	local story = route.journeys[2]
	h.ns.Prefs().journey = story.key
	h.ns.Invalidate()
	h.flush()
	local chain, squares, texts = story.story, {}, {}
	equal(chain and chain.total, 5, "story: the fixture's chain is proven at 5")
	for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
		if entry.atlas and entry.atlas:match("^ui%-journeys%-delve%-level%-square") then
			squares[#squares + 1] = entry.atlas
		end
		texts[#texts + 1] = entry.text
	end
	equal(#squares, chain.total, "story: a square per chapter")
	equal(squares[1], "ui-journeys-delve-level-square-grey", "story: chapter 1 is still to do")
	local rendered, later = table.concat(texts, "\n"), 0
	for index = chain.chapter + 1, #chain.members do
		later = later + (rendered:find(h.ns.Data.quests[chain.members[index]].title, 1, true) and 1 or 0)
	end
	equal(later, 0, "story: no later chapter's title is drawn")
	h.ns.Prefs().journey = "carry"
	h.ns.Invalidate()
	h.flush()
	local after = 0
	for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
		after = after + ((entry.atlas or ""):match("^ui%-journeys%-delve") and 1 or 0)
	end
	equal(after, 0, "story: no track under another card")

	-- F5: a search of 3 characters or more puts quests in place of the cards; a locked one says why, and Go waits.
	local search = h.Find(function(frame)
		return frame.stockTemplate == "SearchBoxTemplate"
	end)[1]
	local function Results()
		return Shown(h, function(frame)
			return frame.Lines ~= nil
		end)
	end
	local function Lines(row)
		local out = {}
		for _, line in ipairs(row.Lines) do
			if line:IsVisible() then
				out[#out + 1] = line:GetText()
			end
		end
		return out
	end
	local goButton = h.Find(function(frame)
		return frame.stockTemplate == "UIPanelButtonTemplate"
	end)[1]
	h.Type(search, "ca")
	equal(#Results(), 0, "search: two characters keep the cards")
	h.Type(search, "Call of")
	local found, suppressed, open = Results(), nil, nil
	for _, row in ipairs(found) do
		suppressed = suppressed or (row.Title:GetText() == "Call of Fire" and row) or nil
		open = open or (not row.Lock:IsShown() and row) or nil
	end
	equal(#found, 10, "search: ten results at most")
	equal(Says(h, story.title), 0, "search: the cards step aside")
	equal(#Shown(h, function(frame)
		return frame.SkipButton ~= nil
	end), 0, "search: and their steps")
	equal(goButton:IsEnabled(), false, "search: no Go")
	local lines = Lines(assert(suppressed, "search: Call of Fire, whose start the data suppresses"))
	equal(#lines, 1, "search: a suppressed start shows exactly 1 line")
	equal(lines[1], h.ns.L.WHY_NO_START, "search: saying the guide can't tell where it starts")
	equal(suppressed.Lock:IsShown(), true, "search: behind a lock")
	h.Hover(suppressed)
	equal(table.concat(h.tooltip, "\n"), "title: Call of Fire\nerror: " .. h.ns.L.WHY_NO_START, "search: tooltip")
	equal(#Lines(assert(open, "search: a quest open now")), 0, "search: an open quest has nothing to explain")
	h.Type(search, "no such quest")
	equal(#Results(), 0, "search: nothing found")
	equal(Says(h, h.ns.L.SEARCH_NONE), 1, "search: says so")
	h.Type(search, "")
	equal(#Results(), 0, "search: cleared")
	equal(goButton:IsEnabled(), true, "search: Go is back")
	clean(h, "guide")

	local none = harness.load({ player = { level = 70 } })
	none.ns.Prefs().quests = false
	none.ns.Invalidate()
	none.ns.OpenPanel()
	none.flush()
	equal(#none.ns.Route().journeys, 0, "guide: nothing fits")
	equal(Says(none, none.ns.L.NOTHING_NEARBY), 1, "guide: says so, and where to look")
	clean(none, "guide: empty")
end

-- F3, select then Go: choosing a journey moves nothing until Go; it turns the map to the journey and its rings
-- preview it while the guide is open, even with map pins off. Closing the guide takes them away.
for _, spf in ipairs({ false, "v1" }) do
	local label = "select: " .. (spf or "no Shortest Path")
	local h = Load(spf)
	h.ns.OpenPanel()
	h.flush()
	local function Cards()
		return Shown(h, function(frame)
			return frame.IconFrame ~= nil and frame.journey ~= nil
		end)
	end
	equal(#Cards(), 3, label .. ": three cards")
	local waypoints, maps = h.counts.SetUserWaypoint, h.counts.SetMapID
	local function Spf(name)
		return h.spf and h.spf[name] or 0
	end
	local navigate, drawn = Spf("Navigate") + Spf("NavigateRoute"), 0
	for click, index in ipairs({ 2, 3, 1, 2, 3 }) do
		local estimates, builds = Spf("Estimate") + Spf("EstimateDetail"), h.modelCalls.Journeys
		local card = Cards()[index]
		local journey = card.journey
		h.Click(card)
		equal(h.modelCalls.Journeys - builds, 0, label .. ": click " .. click .. " builds nothing in its own frame")
		h.flush()
		equal(h.modelCalls.Journeys - builds, 1, label .. ": click " .. click .. " builds once, a frame later")
		local route = h.ns.Route()
		equal(route.journey, journey.key, label .. ": click " .. click .. " chooses " .. journey.key)
		equal(h.map:GetMapID(), journey.map, label .. ": click " .. click .. " turns the map to it")
		equal(Spf("Estimate") + Spf("EstimateDetail") - estimates <= 1, true, label .. ": at most one estimate")
		local rings, expected = {}, {}
		for _, pin in ipairs(h.pins.AdventureGuideForeverPinTemplate or {}) do
			rings[#rings + 1] = pin.step.key
		end
		for _, step in ipairs(route.steps) do
			if step.map == journey.map then
				expected[#expected + 1] = step.key
			end
		end
		equal(table.concat(rings, " "), table.concat(expected, " "), label .. ": click " .. click .. " rings")
		drawn = drawn + #rings
	end
	equal(h.counts.SetUserWaypoint - waypoints, 0, label .. ": no waypoint")
	equal(Spf("Navigate") + Spf("NavigateRoute") - navigate, 0, label .. ": no guidance")
	equal(h.counts.SetMapID - maps, 5, label .. ": the map turns once per click")
	equal(drawn > 0, true, label .. ": the rings preview with map pins off")
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	h.flush()
	equal(#(h.pins.AdventureGuideForeverPinTemplate or {}), 0, label .. ": closing the guide takes the rings away")
	clean(h, label)
end

-- The preview follows the guide's visibility, not only its tab: collapsing the quest sidebar hides the guide and
-- its rings, and bringing the sidebar back brings both.
do
	local h = Load(false)
	h.ns.OpenPanel()
	h.flush()
	local rings = #h.pins.AdventureGuideForeverPinTemplate
	equal(rings > 0, true, "preview: the open guide previews its journey")
	h.G.QuestMapFrame:Hide()
	equal(#h.pins.AdventureGuideForeverPinTemplate, 0, "preview: a collapsed sidebar takes the rings away")
	h.G.QuestMapFrame:Show()
	equal(#h.pins.AdventureGuideForeverPinTemplate, rings, "preview: and its return brings them back")
	clean(h, "preview")
end

-- The activity filters live in the cog's menu, not on the guide (design §2.1).
do
	local h = Load(false)
	h.ns.OpenPanel()
	h.flush()
	local cog = h.Find(function(frame)
		return frame.stockTemplate == "UIPanelIconDropdownButtonTemplate"
	end)[1]
	local menu = h.OpenMenu(cog)
	local byText = {}
	for _, entry in ipairs(menu.entries) do
		byText[entry.text or entry.kind] = entry
	end
	equal(byText.Quests.kind, "checkbox", "cog: a Quests checkbox")
	equal(byText.Dungeons.isSelected(), false, "cog: dungeons off")
	local before = h.modelCalls.Journeys
	byText.Dungeons.onClick()
	h.flush()
	equal(h.ns.Prefs().dungeons, true, "cog: Dungeons turns them on")
	equal(h.modelCalls.Journeys - before, 1, "cog: and rebuilds once")
	local givers = byText["Show quest givers"]
	equal(givers:IsEnabled(), false, "cog: givers are grayed while map pins are off")
	byText["Show map pins"].onClick()
	equal(givers:IsEnabled(), true, "cog: and can be ticked once they are on")
	clean(h, "cog")
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
