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
-- saved settings; the map marks are off unless it turns them on. The character chose the carry card before, as a
-- player past their first session has; `charDB` false is a fresh character, with no card chosen.
local PINS_ON = { showMapPins = true, showQuestGivers = true }
local function Load(spf, db, charDB)
	return harness.load({
		spf = spf or nil,
		db = db,
		charDB = charDB ~= false and (charDB or { journey = "carry" }) or nil,
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
	equal(h.ns.Route().steps[1].key, "hub:346", label .. ": the hand-in leads the route")

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

-- F6: a group quest in the log (a "dungeon" step) opens its details too; a group quest's pickup does not, and a town
-- opens its first hand-in.
do
	local h = Load(false)
	local show = h.ns.ShowQuest
	equal(show({ kind = "dungeon", key = "objective:843", quests = { 843 } }), true, "a group quest in the log opens")
	local town = { kind = "hub", key = "hub:346", quests = { 843 }, pickups = { 843 }, handins = {} }
	equal(show(town), false, "a group pickup does not")
	town.quests, town.pickups, town.handins = { 845, 843 }, { 843 }, { 845 }
	equal(show(town), true, "a town with a hand-in opens it")
	equal(table.concat(h.questDetails, " "), "843 845", "the details opened once each")
end

-- The tracker title sets off along the route and tracks its quests; each part has its own setting, and untracking
-- the player's other quests is opt-in.
do
	local function RouteQuests(h)
		local quests = {}
		for _, step in ipairs(h.ns.Route().steps) do
			if h.ns.InLog(step) then
				for _, questID in ipairs(step.quests) do
					quests[#quests + 1] = questID
				end
			end
		end
		return table.concat(quests, " ")
	end
	local function ClickTitle(h)
		local step = h.ns.Route().steps[1]
		h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[step.key], "LeftButton")
		h.flush()
	end

	local h = Load("v1")
	h.watched[1] = 99
	ClickTitle(h)
	equal(h.spf.NavigateRoute, 1, "the title starts the route")
	equal(h.watched[1], 99, "the player's own tracked quest stays")
	equal(RouteQuests(h), "845 843", "the route holds both log quests")
	equal(table.concat(h.watched, " ", 2), RouteQuests(h), "the route's quests join it")
	ClickTitle(h)
	equal(table.concat(h.watched, " ", 2), RouteQuests(h), "a second click tracks nothing twice")
	clean(h, "title click")

	-- Shortest Path refuses every route in combat; that refusal must not end the journey a click already started.
	local cancels, waypoints = h.spf.Cancel, h.counts.SetUserWaypoint
	h.SetCombat(true)
	ClickTitle(h)
	equal(h.ns.Integrations.Guiding(), true, "a title click in combat keeps the running journey")
	equal(h.spf.Cancel, cancels, "and cancels nothing")
	equal(h.counts.SetUserWaypoint, waypoints, "nor sets a waypoint over it")
	h.SetCombat(false)
	clean(h, "title click in combat")

	h = Load("v1", { untrackOthers = true })
	h.watched[1] = 99
	ClickTitle(h)
	equal(table.concat(h.watched, " "), RouteQuests(h), "untrackOthers leaves only the route's quests")

	h = Load("v1", { titleStartsRoute = false, trackRouteQuests = false, untrackOthers = true })
	h.watched[1] = 99
	ClickTitle(h)
	equal(h.spf.NavigateRoute, 0, "the route setting off: no route")
	equal(table.concat(h.watched, " "), "99", "the tracking setting off: the tracked quests are untouched")

	local byKey = {}
	for _, entry in ipairs(h.settings) do
		byKey[entry.key] = entry
	end
	equal(byKey.untrackOthers.parent, "trackRouteQuests", "untrackOthers hangs under the tracking setting")
	equal(byKey.untrackOthers.enabled(), false, "and is greyed while it is off")
	-- The client re-sorts its watches by distance on every zone change (Blizzard_ObjectiveTracker.lua
	-- SortQuestWatches), so the tooltip promises no order it cannot keep.
	equal(byKey.trackRouteQuests.tooltip:find("order") ~= nil, false, "the tracking tooltip promises no order")
	clean(h, "title click settings")
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

-- Map pins: a refresh replaces, never adds; removal leaves none; the tooltips read as design §2.9 and the tracker
-- menu as §2.8.
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
	-- Rings draw above the stock quest marks; givers stay under them (Blizzard_WorldMap.lua:291-311).
	equal(ring.frameLevelType, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", label .. ": rings at the user waypoint's level")
	h.Hover(ring)
	-- With Shortest Path, step 1 adds its travel line; the stub answers 360 s. The Zhevra opens its next chapter here.
	local expected = { "title: 1. Turn in: The Zhevra" }
	expected[#expected + 1] = spf and "highlight: About 6 min away" or nil
	expected[#expected + 1] = "highlight: Opens the next chapter here"
	expected[#expected + 1] = "normal: Sergra Darkthorn"
	expected[#expected + 1] = "colored: |A:questturnin:14:14|a The Zhevra"
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
	equal(giverPin.frameLevelType, "PIN_FRAME_LEVEL_AREA_POI", label .. ": givers at the area POI level")
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

	-- Design §2.8's menu for a log quest; Stop only once Go runs, Show quest never in combat.
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks["hub:346"], "RightButton")
	local menu = {
		"title: Turn in: The Zhevra",
		"button: Go",
		"button: Show quest",
		"button: Skip for now",
		"button: Choose another journey",
	}
	same(h.MenuLines(), menu, label .. ": tracker menu")
	ns.Integrations.Navigate(ns.Route().steps[1])
	h.SetCombat(true)
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks["hub:346"], "RightButton")
	h.SetCombat(false)
	menu[3] = "button: Stop"
	same(h.MenuLines(), menu, label .. ": tracker menu while Go guides, in combat")
	ns.Integrations.Cancel()
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
	local line = spf == "v1" and "About 6 min away" or "Fly to Sentinel Hill · 6 min"
	equal(h.ns.Integrations.Travel(h.ns.Route().steps[1]), line, spf .. ": step 1's travel line")
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

-- F10, the travel line: the first leg that isn't a walk and the minutes until it arrives, from one EstimateDetail;
-- no answer, no line, and never the reason. In combat nothing is asked and the last line stands.
do
	local h = Load("v1+")
	local ns = h.ns
	local step = ns.Route().steps[1]
	local cases = {
		{
			"a flight",
			{
				{ mode = "walk", to = "Crossroads", seconds = 60 },
				{ mode = "flight", to = "Sentinel Hill", seconds = 300 },
			},
			"Fly to Sentinel Hill · 6 min",
		},
		{
			"a boat's wait",
			{
				{ mode = "walk", to = "Ratchet", seconds = 30 },
				{ mode = "boat", to = "Booty Bay", seconds = 400, wait = 120 },
				{ mode = "walk", to = "Booty Bay", seconds = 20 },
			},
			"Boat to Booty Bay · 8 min · 2 min wait",
		},
		{
			"a new flight path",
			{
				{ mode = "walk", to = "Splintertree Post", seconds = 100, newFlightPath = true },
				{ mode = "flight", to = "Astranaar", seconds = 200 },
			},
			"Fly to Astranaar · 5 min · new flight path",
		},
		{
			"on foot",
			{ { mode = "walk", to = "Crossroads", seconds = 90 }, { mode = "walk", to = "The Barrens", seconds = 45 } },
			"Walk to The Barrens · 3 min",
		},
		{ "no route", false, nil },
	}
	for _, case in ipairs(cases) do
		h.spfLegs = case[2]
		local detail, estimate = h.spf.EstimateDetail, h.spf.Estimate
		equal(ns.Integrations.TravelLine(step), case[3], "travel line, " .. case[1])
		equal(h.spf.EstimateDetail - detail + h.spf.Estimate - estimate, 1, "travel line, " .. case[1] .. ": one call")
	end

	h.spfLegs = cases[1][2]
	ns.Integrations.RefreshTravel()
	h.SetCombat(true)
	h.spfLegs = cases[4][2]
	local calls = h.spf.EstimateDetail
	ns.Invalidate()
	h.flush()
	equal(h.spf.EstimateDetail, calls, "travel line, combat: nothing asked")
	equal(ns.Integrations.Travel(step), cases[1][3], "travel line, combat: the last line stands")
	h.SetCombat(false)
	h.flush()
	equal(ns.Integrations.Travel(step), cases[4][3], "travel line, after combat: asked again")

	-- The guide: step 1's row reads the line fetched already; another row's tooltip asks once per hover.
	ns.Prefs().journey = "carry"
	ns.OpenPanel()
	h.flush()
	local rows = Shown(h, function(frame)
		return frame.SkipButton ~= nil
	end)
	-- 90 + 45 seconds on foot: 3 minutes after the counts; the way itself is the tooltip's.
	equal(rows[1].Detail:GetText(), rows[1].step.detail .. " · 3 min", "travel line: step 1's row adds the minutes")
	calls = h.spf.EstimateDetail
	h.Hover(rows[1])
	equal(h.spf.EstimateDetail, calls, "travel line: step 1's tooltip asks nothing")
	equal(h.tooltip[2], "highlight: " .. cases[4][3], "travel line: step 1's tooltip")
	h.spfLegs = cases[1][2]
	h.Hover(rows[2])
	equal(h.spf.EstimateDetail, calls + 1, "travel line: another row's tooltip asks once")
	same(h.tooltip, {
		"title: 2. " .. rows[2].step.title,
		"highlight: " .. cases[1][3],
		"highlight: " .. rows[2].step.reason,
	}, "travel line: another row's tooltip")
	clean(h, "travel line")

	h = Load(false)
	equal(h.ns.Integrations.TravelLine(h.ns.Route().steps[1]), nil, "travel line: none without Shortest Path")
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

-- F13: while someone else's Shortest Path journey runs, each way to start the route warns once before replacing it:
-- a card another click would choose (while choosing starts the route), the step menu's Go and the tracker title (the
-- same setting). Our own journey, or a Shortest Path without Active, warns of nothing.
local function Warnings(h)
	local warning, counts = "instruction: " .. h.ns.L.REPLACES_JOURNEY, {}
	local function Count()
		local count = 0
		for _, line in ipairs(h.tooltip) do
			count = count + (line == warning and 1 or 0)
		end
		counts[#counts + 1] = count
	end
	h.tooltip = {}
	h.Hover(Shown(h, function(frame)
		return frame.state == "compact"
	end)[1])
	Count()
	h.tooltip = {}
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[h.ns.Route().steps[1].key], "RightButton")
	local go = h.menu.entries[2]
	if go.tooltip then
		h.call(go.tooltip, h.G.GameTooltip, go)
	end
	Count()
	h.tooltip = {}
	h.tracker:OnBlockHeaderEnter(h.tracker.liveBlocks[h.ns.Route().steps[1].key])
	Count()
	return table.concat(counts, " ")
end
for _, spf in ipairs({ "v1", "v1+" }) do
	local h = Load(spf)
	local ns = h.ns
	ns.OpenPanel()
	h.flush()
	equal(Warnings(h), "0 0 0", spf .. ": no journey, no warning")
	h.G.ShortestPathForever.API.Navigate("OtherAddon", 1413, 0.5, 0.5)
	equal(Warnings(h), spf == "v1+" and "1 1 1" or "0 0 0", spf .. ": another addon's journey")
	ns.SetSetting("titleStartsRoute", false)
	h.flush()
	equal(Warnings(h), spf == "v1+" and "0 1 0" or "0 0 0", spf .. ": a choice that doesn't start the route")
	ns.Integrations.Navigate(ns.Route().steps[1])
	equal(Warnings(h), "0 0 0", spf .. ": our own journey")
	clean(h, spf .. ": replace warning")
end

-- F7, Stop: it ends only what we started. The native waypoint is ours while it sits where we put it, across a
-- /reload; one the player moved is theirs. Shortest Path's journey is cancelled by our name, and Stop shows only while
-- one of them runs.
local function StopButton(h)
	return h.Find(function(frame)
		return frame.stockTemplate == "UIPanelButtonTemplate" and frame.text == h.ns.L.STOP
	end)[1]
end
-- Choosing another journey, which starts its route once the rebuild has its steps.
local function ChooseOther(h)
	h.Click(Shown(h, function(frame)
		return frame.state == "compact"
	end)[1])
	h.flush()
end
do
	local h = Load(false)
	local ns = h.ns
	ns.OpenPanel()
	h.flush()
	local stop = StopButton(h)
	equal(stop:IsShown(), false, "stop: hidden before Go")
	ns.Integrations.Navigate(ns.Route().steps[1])
	local moved = h.waypoint
	h.waypoint = { uiMapID = moved.uiMapID, position = { x = moved.position.x + 0.01, y = moved.position.y } }
	equal(ns.Integrations.Owns(), false, "stop: a waypoint the player moved is theirs")
	ns.Integrations.Cancel()
	equal(h.counts.ClearUserWaypoint, 0, "stop: so Stop leaves it")
	equal(h.waypoint ~= nil, true, "stop: it is still there")
	equal(ns.Prefs().waypoint, nil, "stop: and ours is forgotten")
	ChooseOther(h)
	equal(stop:IsShown(), true, "stop: shown after a choice")
	h.Click(stop)
	equal(h.counts.ClearUserWaypoint, 1, "stop: clears the waypoint Go set")
	equal(h.superTracked, false, "stop: and stops tracking it")
	equal(stop:IsShown(), false, "stop: then hides")
	clean(h, "stop")

	-- A /reload: the client keeps the waypoint, the character's saved variables remember it was ours.
	ChooseOther(h)
	local reloaded = harness.load({
		charDB = h.G.AdventureGuideForeverCharDB,
		waypoint = h.waypoint,
		initialLogin = false,
		completed = { 844 },
	})
	-- No log after the reload, so no carry card: the story is chosen for the row menu below.
	reloaded.ns.Prefs().journey = reloaded.ns.Route().journeys[1].key
	reloaded.ns.Invalidate()
	reloaded.ns.OpenPanel()
	reloaded.flush()
	equal(StopButton(reloaded):IsShown(), true, "stop: still offered after a /reload")
	reloaded.Click(StopButton(reloaded))
	equal(reloaded.counts.ClearUserWaypoint, 1, "stop: and still clears the waypoint")
	clean(reloaded, "stop: reload")

	-- Go and Stop from a step row's menu move the footer's Stop too, with no route change to redraw it.
	local function Choose(text)
		for _, entry in ipairs(reloaded.menu.entries) do
			if entry.text == text then
				return entry.onClick()
			end
		end
		error("no menu entry " .. text)
	end
	local row = Shown(reloaded, function(frame)
		return frame.SkipButton ~= nil
	end)[1]
	reloaded.Click(row, "RightButton")
	Choose(ns.L.GO)
	equal(StopButton(reloaded):IsShown(), true, "stop: shown after the menu's Go")
	reloaded.Click(row, "RightButton")
	Choose(ns.L.STOP)
	equal(StopButton(reloaded):IsShown(), false, "stop: hidden after the menu's Stop")
end
do
	local h = Load("v1")
	local ns = h.ns
	ns.OpenPanel()
	h.flush()
	local stop = StopButton(h)
	ChooseOther(h)
	equal(stop:IsShown(), true, "stop, Shortest Path: shown while it walks our journey")
	h.Click(stop)
	equal(h.spf.Cancel, 1, "stop, Shortest Path: cancels our journey once")
	equal(stop:IsShown(), false, "stop, Shortest Path: then hides")
	equal(h.counts.ClearUserWaypoint, 0, "stop, Shortest Path: no native waypoint to clear")
	ns.Integrations.Navigate(ns.Route().steps[1])
	h.G.ShortestPathForever.API.Cancel("AdventureGuideForever")
	ns.Invalidate()
	h.flush()
	equal(stop:IsShown(), false, "stop, Shortest Path: hidden once CurrentStop is nil")
	clean(h, "stop, Shortest Path")
end

-- The step menu (design §2.8) from a step row, and "Skipped (n)": hidden at 0, it counts the session's skips and
-- opens the same Skipped submenu, whose "Show again" puts a step back where the route had it.
do
	local h = Load(false)
	local ns = h.ns
	ns.OpenPanel()
	h.flush()
	local story = ns.Route().journeys[2]
	h.Click(Shown(h, function(frame)
		return frame.journey == story
	end)[1])
	h.flush()
	local function Keys()
		local keys = {}
		for index, step in ipairs(ns.Route().steps) do
			keys[index] = step.key
		end
		return table.concat(keys, " ")
	end
	local before, first, second = Keys(), ns.Route().steps[1], ns.Route().steps[2]
	local function Rows()
		return Shown(h, function(frame)
			return frame.SkipButton ~= nil
		end)
	end
	h.Click(Rows()[1], "RightButton")
	same(h.MenuLines(), {
		"title: " .. first.title,
		"button: Go",
		"button: Stop",
		"button: Show quest",
		"button: Skip for now",
		"button: Choose another journey",
	}, "step menu: a town with a hand-in shows it; choosing started the route, which Stop ends")
	local skipped = h.Find(function(frame)
		return frame.text ~= nil and frame.text:match("^Skipped")
	end)
	equal(#skipped, 0, "skipped: no button at 0")
	h.menu.entries[5].onClick()
	h.flush()
	h.Click(Rows()[1].SkipButton)
	h.flush()
	local button = Shown(h, function(frame)
		return frame.text == "Skipped (2)"
	end)[1]
	equal(button ~= nil, true, "skipped: reads Skipped (2) after 2 skips")
	h.Click(Rows()[1], "RightButton")
	local submenu = { "  button: Show again: " .. first.title, "  button: Show again: " .. second.title }
	same(h.MenuLines(), {
		"title: " .. ns.Route().steps[1].title,
		"button: Go",
		"button: Stop",
		"button: Skip for now",
		"button: Skipped (2)",
		submenu[1],
		submenu[2],
		"button: Choose another journey",
	}, "step menu: the Skipped submenu")
	h.Click(button)
	same(
		h.MenuLines(),
		{ "button: Show again: " .. first.title, "button: Show again: " .. second.title },
		"skipped: the same submenu"
	)
	h.menu.entries[2].onClick()
	h.menu.entries[1].onClick()
	h.flush()
	equal(Keys(), before, "skipped: Show again restores the route")
	equal(button:IsShown(), false, "skipped: hidden again at 0")
	clean(h, "step menu")
end
-- A skipped step the route no longer has (the quest turned in anyway) leaves Skipped (n); one it still has stays.
do
	local completed = { 844 }
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
	}
	local h = harness.load({ completed = completed, log = log })
	local ns = h.ns
	h.flush()
	-- A town's step stays while the town offers anything, so the gone step here is the objective's.
	ns.Skip("objective:843", "Gann's Reclamation")
	h.flush()
	local other = ns.Route().steps[1]
	ns.Skip(other.key, other.title)
	h.flush()
	equal(#ns.Skipped(), 2, "skipped, pruned: both counted")
	table.remove(log, 2)
	completed[#completed + 1] = 843
	ns.Invalidate()
	h.flush()
	equal(#ns.Skipped(), 1, "skipped, pruned: the turned-in quest leaves")
	equal(ns.Skipped()[1].key, other.key, "skipped, pruned: the other stays")
	equal(ns.Prefs().skipped["objective:843"], nil, "skipped, pruned: and is no longer skipped")
	clean(h, "skipped, pruned")
end

-- F8, the tracker (design §2.5): step 1's place, its reason and, with Shortest Path, its travel line, dashed; then the
-- next step, undashed.
local function TrackerLines(h)
	local block = h.tracker.liveBlocks[h.ns.Route().steps[1].key]
	local lines = {}
	for index, key in ipairs(block.order) do
		lines[index] = block.lines[key] .. (block.dashes[key] == 3 and " (no dash)" or "")
	end
	return lines, block
end
for _, spf in ipairs({ false, "v1" }) do
	local label = "tracker: " .. (spf or "no Shortest Path")
	local h = Load(spf)
	local steps = h.ns.Route().steps
	local expected = { "Crossroads, The Barrens" }
	expected[#expected + 1] = spf and "About 6 min away" or nil
	expected[#expected + 1] = "Next: " .. steps[2].title .. " (no dash)"
	local lines, block = TrackerLines(h)
	equal(block.header, steps[1].title, label .. ": step 1's title heads the block")
	same(lines, expected, label .. ": a turn-in's header is its reason; its town, travel, next")
	clean(h, label)
end
-- A row's detail has no right anchor, so the tag can follow it: its width is capped instead, so a long one is cut
-- short with "..." and the tag stays beside it, all within 230px.
do
	local h = Load(false)
	local ns = h.ns
	ns.OpenPanel()
	h.flush()
	local steps = ns.Route().steps
	steps[1].detail = "short"
	steps[2].detail, steps[2].optional = string.rep("a long detail ", 10), true
	ns.OpenPanel()
	local rows = Shown(h, function(frame)
		return frame.SkipButton ~= nil
	end)
	equal(rows[1].Detail:GetWidth(), 5 * 6, "detail width: a short one keeps its own width")
	local tag = rows[2].Tag:GetUnboundedStringWidth() + 6
	equal(rows[2].Tag:IsShown(), true, "detail width: the tag shows")
	equal(rows[2].Detail:GetWidth(), 230 - tag, "detail width: a long one stops short of the tag")
	equal(rows[2].Group:IsShown(), false, "group icon: none without a group quest")

	-- A stop with a group quest: Blizzard's group tag follows the detail, the tag follows it, and the detail makes room.
	steps[2].group = 1
	ns.OpenPanel()
	equal(rows[2].Group:IsShown(), true, "group icon: shown")
	equal(rows[2].Group:GetAtlas(), "questlog-questtypeicon-group", "group icon: the stock tag")
	equal(select(2, rows[2].Tag:GetPoint()), rows[2].Group, "group icon: the tag follows it")
	equal(rows[2].Detail:GetWidth(), 230 - 16 - (tag - 2), "group icon: the detail makes room")
	equal(
		select(2, rows[1].Tag:GetPoint()),
		rows[1].Detail,
		"group icon: a row without one keeps the tag on its detail"
	)
	clean(h, "detail width")
end

-- A town's tooltip (plan §7.4), from its row and its ring alike: after the reason, each NPC and its quests, hand-ins
-- first, each coloured by the stock difficulty colour, 8 at most and the rest counted; the click line stays last.
do
	local h = Load(false, PINS_ON)
	local ns = h.ns
	ns.Prefs().journey = ns.Route().journeys[2].key
	ns.Invalidate()
	h.flush()
	ns.OpenPanel()
	h.flush()
	local step = ns.Route().steps[1]
	equal(#step.quests, 9, "hub tooltip: Crossroads has 9 quests")
	local rows = Shown(h, function(frame)
		return frame.SkipButton ~= nil
	end)
	h.Hover(rows[1])
	local lines, colors = h.tooltip, h.tooltipColors
	equal(lines[1], "title: 1. Crossroads, The Barrens", "hub tooltip: the numbered town")
	equal(lines[2], "highlight: " .. step.reason, "hub tooltip: the reason")
	equal(lines[3], "normal: Sergra Darkthorn", "hub tooltip: the hand-in's NPC first")
	equal(lines[4], "colored: |A:questturnin:14:14|a The Zhevra", "hub tooltip: a hand-in has the turn-in mark")
	equal(lines[6], "colored: |A:questnormal:14:14|a [13] Raptor Thieves", "hub tooltip: a pickup has its level")
	local quests, npcs = 0, 0
	for index, line in ipairs(lines) do
		if line:find("^colored: ") then
			quests = quests + 1
			local level = tonumber(line:match("%[(%d+)%]")) or 13
			local expected = h.G.GetQuestDifficultyColor(level)
			same(colors[index], { expected.r, expected.g, expected.b }, "hub tooltip: line " .. index .. "'s colour")
		end
		npcs = npcs + (line:find("^normal: ") and 1 or 0)
	end
	equal(quests, 8, "hub tooltip: 8 quest lines")
	equal(npcs, 7, "hub tooltip: one line per NPC shown")
	equal(lines[#lines], "highlight: And 1 more", "hub tooltip: the rest counted")
	same(colors[12], { 1, 1, 0 }, "hub tooltip: a quest 2 over the player is yellow")

	-- The ring's tooltip lists the same, then the click line.
	h.providers[1]:RefreshAllData()
	local ring = h.pins.AdventureGuideForeverPinTemplate[1]
	equal(ring.step.key, step.key, "hub tooltip: ring 1 is the town")
	h.Hover(ring)
	equal(h.tooltip[#h.tooltip - 1], "highlight: And 1 more", "hub tooltip: the ring's quests")
	equal(h.tooltip[#h.tooltip], "instruction: Click to set a waypoint", "hub tooltip: the click line last")

	-- A group quest carries the quest log's group tag.
	ns.Data.quests[step.quests[1]].elite = true
	h.Hover(rows[1])
	equal(
		h.tooltip[4],
		"colored: |A:questturnin:14:14|a The Zhevra |A:questlog-questtypeicon-group:12:12|a",
		"hub tooltip: group"
	)
	ns.Data.quests[step.quests[1]].elite = nil
	clean(h, "hub tooltip")
end

-- A town (plan §7.4) is titled by its name, so step 1 of the story (Crossroads) shows its counts, then its reason in
-- place of the NPC line, since The Zhevra opens its next chapter. With a reason that is only the counts, the line
-- names its NPCs: two, then how many more. One quest's stop reads "NPC, zone".
do
	local h = Load(false)
	local ns = h.ns
	ns.Prefs().journey = ns.Route().journeys[2].key
	ns.Invalidate()
	h.flush()
	local steps = ns.Route().steps
	local step = steps[1]
	equal(step.title, "Crossroads, The Barrens", "tracker, town: titled by its flight master")
	equal(step.detail, "1 to hand in, 8 to pick up", "tracker, town: the hand-in joins the pickups")
	same(TrackerLines(h), {
		step.detail,
		"Opens the next chapter here",
		"Next: " .. steps[2].title .. " (no dash)",
	}, "tracker, town: its counts, then its reason, never the place again")

	step.reason = step.detail
	h.tracker:MarkDirty()
	same(TrackerLines(h), {
		step.detail,
		"Sergra Darkthorn, Gazrog and 6 more",
		"Next: " .. steps[2].title .. " (no dash)",
	}, "tracker, town: its NPCs, two named")
	step.givers = { "Sergra Darkthorn", "Gazrog" }
	h.tracker:MarkDirty()
	equal(TrackerLines(h)[2], "Sergra Darkthorn, Gazrog", "tracker, town: two NPCs, both named")

	-- Kadrak's one quest: its NPC and zone, since its title names only the NPC.
	ns.Skip(steps[1].key, steps[1].title)
	ns.Skip(steps[2].key, steps[2].title)
	h.flush()
	step = ns.Route().steps[1]
	equal(step.title, "Pick up quests: Kadrak", "tracker, one quest: Kadrak leads")
	equal(TrackerLines(h)[1], "Kadrak, The Barrens", "tracker, one quest: NPC, zone")
	clean(h, "tracker, town")
end

-- F8, the resume line: a login shows "Where you left off" once, when last session's step 1 is still step 1; a
-- /reload, a stale key or a route change shows none.
do
	local function Resumed(h)
		local count = 0
		for _, line in ipairs((TrackerLines(h))) do
			count = count + (line:find("^Where you left off: ") and 1 or 0)
		end
		return count
	end
	local session = Load(false)
	local saved = session.G.AdventureGuideForeverCharDB.last
	equal(saved and saved.key, "hub:346", "resume: each rebuild saves step 1")
	equal(Resumed(session), 0, "resume: nothing saved, nothing to resume")
	local function Login(options)
		options.charDB = { last = { key = saved.key, reason = "finishes a story" } }
		options.completed = { 844 }
		options.log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
		}
		return harness.load(options)
	end
	local h = Login({})
	equal(Resumed(h), 1, "resume: a login with a matching key shows the line")
	equal(TrackerLines(h)[2], "Where you left off: finishes a story", "resume: in place of the reason, after the town")
	local capital = harness.load({
		charDB = { last = { key = saved.key, reason = "Continues a story you started" } },
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		},
	})
	equal(
		TrackerLines(capital)[2],
		"Where you left off: continues a story you started",
		"resume: sentence case mid-line"
	)
	clean(capital, "resume: sentence case")
	local first = h.ns.Route().steps[1]
	h.ns.Skip(first.key, first.title)
	h.flush()
	h.ns.Unskip(first.key)
	h.flush()
	equal(Resumed(h), 0, "resume: gone after a route change, even when step 1 comes back")
	clean(h, "resume: login")

	local pending = Login({ completedPending = true })
	equal(#pending.ns.Route().steps, 0, "resume: no route before completed quests load")
	pending.completedPending = false
	pending.fire("PLAYER_ENTERING_WORLD", false, false)
	pending.flush()
	equal(Resumed(pending), 1, "resume: the login waits for the first route with a step")
	clean(pending, "resume: pending")

	local reload = Login({ initialLogin = false })
	equal(Resumed(reload), 0, "resume: a /reload shows none")
	saved.key = "hub:0"
	local stale = Login({})
	equal(Resumed(stale), 0, "resume: a stale key shows none")
	clean(reload, "resume: reload")
	clean(stale, "resume: stale")
end

-- F11, the chapter end (design §2.7): handing in the last quest of a chain whose end the data proves glows a
-- "Story complete" header once and plays the stage-end sound; a chain with no proven end, or a quest before the
-- end, does neither. The header stays above the steps until step 1 moves on.
do
	local h = Load(false)
	local ns = h.ns
	local last, open, middle
	for id in pairs(ns.Data.quests) do
		local story = ns.Model.Story(ns.Data, id)
		if story and story.total == story.chapter then
			last = math.min(last or id, id)
		elseif story and story.total then
			middle = math.min(middle or id, id)
		elseif story then
			open = math.min(open or id, id)
		end
	end
	equal(last and open and middle and true, true, "fanfare: the data has each kind of chain quest")
	for _, id in ipairs({ open, middle }) do
		h.fire("QUEST_TURNED_IN", id)
		h.flush()
	end
	equal(#h.sounds + #h.fanfares, 0, "fanfare: none for an unproven end or a middle chapter")
	h.fire("QUEST_TURNED_IN", last)
	h.flush()
	same(h.sounds, { 31757 }, "fanfare: the stage-end sound, once")
	same(h.fanfares, { "story-complete" }, "fanfare: the header glows once")
	local block = h.tracker.liveBlocks["story-complete"]
	equal(block.header, "Story complete", "fanfare: the header")
	equal(h.tracker.layoutOrder[1], "story-complete", "fanfare: above the steps")
	-- The header is not the step's: clicking it neither guides, opens the guide nor opens the step's menu.
	local waypoints, opened, menus = h.counts.SetUserWaypoint, 0, 0
	local openPanel, openMenu = ns.OpenPanel, ns.Menu.Open
	ns.OpenPanel = function()
		opened = opened + 1
	end
	ns.Menu.Open = function()
		menus = menus + 1
	end
	h.tracker:OnBlockHeaderClick(block, "LeftButton")
	h.tracker:OnBlockHeaderClick(block, "RightButton")
	h.flush()
	ns.OpenPanel, ns.Menu.Open = openPanel, openMenu
	equal(h.counts.SetUserWaypoint - waypoints, 0, "fanfare: the header sets no waypoint")
	equal(opened + menus, 0, "fanfare: nor opens the guide or the step's menu")
	h.tracker:MarkDirty()
	equal(#h.fanfares, 1, "fanfare: a later layout doesn't glow again")
	equal(h.tracker.layoutOrder[1], "story-complete", "fanfare: and still shows the header")
	local first = ns.Route().steps[1]
	ns.Skip(first.key, first.title)
	h.flush()
	equal(h.tracker.layoutOrder[1], ns.Route().steps[1].key, "fanfare: gone once step 1 moves on")
	clean(h, "fanfare")

	h = Load(false, { showTracker = false })
	h.fire("QUEST_TURNED_IN", last)
	h.flush()
	equal(#h.sounds, 0, "fanfare: no sound without the tracker section")
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

-- The guide (F2): at most three cards. The chosen one is lit, never moved, 288x86 with a 46x46 ring and followed by
-- its steps; the others sit above it as one-line 288x26 header rows with a 16x16 icon and no ring, in the dumped
-- layout the client's own dump is compared with.
do
	local h = Load(false)
	h.ns.OpenPanel()
	h.flush()
	local route, full, compact, lit = h.ns.Route(), 0, 0, 0
	local sizes = {}
	for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
		if entry.path:match("%.Button%[%d%]$") and entry.size and entry.size[1] == 288 then
			sizes[entry.path] = entry.size[2]
			full = full + (entry.size[2] == 86 and 1 or 0)
			compact = compact + (entry.size[2] == 26 and 1 or 0)
			lit = lit + (entry.highlightLocked and 1 or 0)
		elseif entry.path:match("%.IconFrame$") then
			local ring = sizes[entry.path:gsub("%.IconFrame$", "")] == 86 and "46x46" or "16x16"
			equal(("%dx%d"):format(entry.size[1], entry.size[2]), ring, "guide: " .. entry.path .. " is " .. ring)
		elseif entry.atlas == "ui-journeys-renown-button-pressed" then
			error("guide: the pressed art is drawn off true, so no card shows it: " .. entry.path)
		end
	end
	equal(full + compact, #route.journeys, "guide: a card per journey")
	equal(#route.journeys, 3, "guide: the fixture has three cards")
	equal(full, 1, "guide: only the chosen card is whole")
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
	h.Type(search, "ca")
	equal(#Results(), 0, "search: two characters keep the cards")
	h.Type(search, "\231\139\188\231\139\188") -- two CJK characters, six bytes
	equal(#Results() + Says(h, h.ns.L.SEARCH_NONE), 0, "search: counts characters, not bytes")
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
	local lines = Lines(assert(suppressed, "search: Call of Fire, whose start the data suppresses"))
	equal(#lines, 1, "search: a suppressed start shows exactly 1 line")
	equal(lines[1], h.ns.L.WHY_NO_START, "search: saying the guide can't tell where it starts")
	equal(suppressed.Lock:IsShown(), true, "search: behind a lock")
	h.Hover(suppressed)
	equal(table.concat(h.tooltip, "\n"), "title: Call of Fire\nerror: " .. h.ns.L.WHY_NO_START, "search: tooltip")
	equal(#Lines(assert(open, "search: a quest open now")), 0, "search: an open quest has nothing to explain")
	local ready = h.ns.State.Ready
	h.ns.State.Ready = function()
		return false
	end
	h.Type(search, "Call of")
	equal(#Results(), 0, "search: none while completed quests load")
	equal(Says(h, h.ns.L.LOADING), 1, "search: which it says")
	h.ns.State.Ready = ready
	-- Uncached titles are asked for once each, and the results redraw as one arrives.
	local asked = #h.titleRequests
	equal(asked > 0, true, "search: asks for uncached titles")
	local fire = h.ns.Model.Search(h.ns.Data, h.ns.State.Player(), "Call of")[1]
	h.Type(search, "Call of ")
	equal(#h.titleRequests, asked, "search: once each")
	h.G.C_QuestLog.GetTitleForQuestID = function(questID)
		return questID == fire and "Call of Aardvarks" or nil
	end
	h.fire("QUEST_DATA_LOAD_RESULT", fire, true)
	equal(Says(h, "Call of Aardvarks"), 1, "search: a title that arrives is shown")
	h.G.C_QuestLog.GetTitleForQuestID = function() end
	h.Type(search, "no such quest")
	equal(#Results(), 0, "search: nothing found")
	equal(Says(h, h.ns.L.SEARCH_NONE), 1, "search: says so")
	h.Type(search, "")
	equal(#Results(), 0, "search: cleared")
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

-- F3, select: with the setting that starts the route off, choosing a journey starts nothing; it turns the map to the
-- journey and its rings preview it while the guide is open, even with map pins off. Closing the guide takes them away.
for _, spf in ipairs({ false, "v1" }) do
	local label = "select: " .. (spf or "no Shortest Path")
	local h = Load(spf, { titleStartsRoute = false })
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

-- None chosen (docs/design.md §2.2): a fresh character sees every card whole, no steps, no rings and the hint, and
-- nothing guides while the tracker still follows the first card. Choosing one starts its route and folds the others
-- into one-line rows above it, each keeping its lines in a tooltip; a row chooses its card and starts its route in
-- place of the first, and the chosen card toggles back to none, stopping the route it started.
for _, spf in ipairs({ false, "v1" }) do
	local label = "none chosen: " .. (spf or "no Shortest Path")
	local h = Load(spf, nil, false)
	h.ns.OpenPanel()
	h.flush()
	local route = h.ns.Route()
	-- Top to bottom as laid out, not in pool order.
	local function Cards()
		local shown = Shown(h, function(frame)
			return frame.IconFrame ~= nil and frame.journey ~= nil
		end)
		table.sort(shown, function(a, b)
			return select(5, a:GetPoint(1)) > select(5, b:GetPoint(1)) -- multi-value: the y offset only
		end)
		return shown
	end
	local function Heights()
		local heights = {}
		for index, card in ipairs(Cards()) do
			heights[index] = select(2, card:GetSize()) -- multi-value: the height only
		end
		return table.concat(heights, " ")
	end
	local function Rows()
		return #Shown(h, function(frame)
			return frame.SkipButton ~= nil
		end)
	end
	-- The dump holds only what is shown.
	local function Says(text)
		local count = 0
		for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
			count = count + (entry.text == text and 1 or 0)
		end
		return count
	end
	local function Hint()
		return Says(h.ns.L.CHOOSE_TO_SEE_STEPS)
	end
	-- Every start: Shortest Path's routes, or the native waypoints without it.
	local function Starts()
		return h.spf and h.spf.NavigateRoute or h.counts.SetUserWaypoint
	end
	local function Stops()
		return h.spf and h.spf.Cancel or h.counts.ClearUserWaypoint
	end
	equal(route.chosen, false, label .. ": nothing chosen")
	equal(route.journey, "carry", label .. ": the route falls back to the first card")
	equal(h.tracker.liveBlocks[route.steps[1].key] ~= nil, true, label .. ": which the tracker still follows")
	equal(Heights(), "86 86 86", label .. ": every card whole")
	equal(Rows(), 0, label .. ": no steps listed")
	equal(Hint(), 1, label .. ": the hint under the cards")
	equal(Says(h.ns.L.STEP_COUNT:format(0)), 1, label .. ": and no steps counted")
	equal(#(h.pins.AdventureGuideForeverPinTemplate or {}), 0, label .. ": no rings previewed")
	equal(Starts(), 0, label .. ": nothing guides")
	for _, card in ipairs(Cards()) do
		equal(card.highlightLocked == true, false, label .. ": no card lit")
	end

	-- A compact row's tooltip keeps the card's lines.
	local story = Cards()[2].journey
	h.Click(Cards()[2])
	equal(Starts(), 0, label .. ": the route waits for the rebuild with its steps")
	h.flush()
	equal(h.ns.Route().journey, story.key, label .. ": a click chooses")
	equal(Starts(), 1, label .. ": and starts its route")
	equal(h.ns.Integrations.Owns(), true, label .. ": ours, which Stop ends")
	equal(h.G.AdventureGuideForeverCharDB.journey, story.key, label .. ": and is saved")
	equal(Heights(), "26 26 86", label .. ": the others fold above the chosen card")
	equal(Cards()[3].journey.key, story.key, label .. ": the chosen card last, over its steps")
	-- The chosen card is lit, not pressed: its art, pressed or not, is the card's own, so nothing moves.
	local chosenCard = Cards()[3]
	equal(chosenCard.highlightLocked, true, label .. ": the chosen card stays lit")
	equal(chosenCard.NormalTexture:GetAtlas(), "ui-journeys-renown-button", label .. ": in its own art")
	equal(chosenCard.PushedTexture:GetAtlas(), "ui-journeys-renown-button", label .. ": a press moves nothing")
	equal(Cards()[1].PushedTexture:GetAtlas(), Cards()[1].NormalTexture:GetAtlas(), label .. ": nor on a row")
	equal(Rows(), #h.ns.Route().steps, label .. ": its steps listed")
	equal(Hint(), 0, label .. ": no hint")
	local nextZone = Cards()[2]
	h.Hover(nextZone)
	local tip = table.concat(h.tooltip, "\n")
	equal(tip:find(nextZone.journey.title, 1, true) ~= nil, true, label .. ": the row's tooltip has its title")
	equal(tip:find(nextZone.journey.subline, 1, true) ~= nil, true, label .. ": its subline")
	equal(tip:find(nextZone.journey.reason, 1, true) ~= nil, true, label .. ": and its reason")
	h.Hover(Cards()[3])
	tip = table.concat(h.tooltip, "\n")
	equal(
		tip:find(h.ns.L.STOP_AND_SHOW_EVERY_JOURNEY, 1, true) ~= nil,
		true,
		label .. ": the chosen card says how back, and that it stops the route"
	)

	-- A row chooses its card; the one chosen before folds in its place.
	local key = nextZone.journey.key
	h.Click(nextZone)
	h.flush()
	equal(h.ns.Route().journey, key, label .. ": a row chooses its card")
	equal(Starts(), 2, label .. ": and starts its route in place of the first")
	equal(Heights(), "26 26 86", label .. ": still one whole card")
	equal(Cards()[3].journey.key, key, label .. ": the new choice over the steps")

	-- The chosen card again: none chosen, every card whole, and the map stays where it was.
	local maps, stops = h.counts.SetMapID, Stops()
	h.Click(Cards()[3])
	h.flush()
	equal(Stops() - stops, 1, label .. ": clearing the choice stops our route")
	equal(h.ns.Integrations.Owns(), false, label .. ": so nothing of ours guides")
	equal(Starts(), 2, label .. ": and nothing new starts")
	equal(h.ns.Route().chosen, false, label .. ": clicking the chosen card chooses none")
	equal(h.G.AdventureGuideForeverCharDB.journey, nil, label .. ": and saves none")
	equal(h.counts.SetMapID, maps, label .. ": without turning the map")
	equal(Heights(), "86 86 86", label .. ": every card whole again")
	clean(h, label)
end

-- A saved choice from before survives the update, and one whose card is gone reads as none chosen.
do
	local kept = Load(false, nil, { journey = "story:1413" })
	equal(kept.ns.Route().chosen, true, "saves: a saved card stays chosen")
	equal(kept.ns.Route().journey, "story:1413", "saves: the same card")
	local gone = Load(false, nil, { journey = "dungeon:36" })
	equal(gone.ns.Route().chosen, false, "saves: a card no longer offered is none chosen")
	equal(gone.G.AdventureGuideForeverCharDB.journey, "dungeon:36", "saves: kept, should it come back")
	clean(kept, "saves: kept")
	clean(gone, "saves: gone")
end

-- A choice in combat, when Shortest Path refuses every route: the card is chosen at once and its route starts on the
-- rebuild combat's end brings, while the footer says it waits. A choice cleared before then starts nothing. With the
-- setting off a choice starts nothing and clearing it stops nothing.
for _, spf in ipairs({ false, "v1" }) do
	local label = "combat choice: " .. (spf or "no Shortest Path")
	local h = Load(spf, nil, false)
	h.ns.OpenPanel()
	h.flush()
	local function Queued()
		local count = 0
		for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
			count = count + (entry.text == h.ns.L.STARTS_AFTER_COMBAT and 1 or 0)
		end
		return count
	end
	local function Starts()
		return h.spf and h.spf.NavigateRoute or h.counts.SetUserWaypoint
	end
	local function Card(state)
		return Shown(h, function(frame)
			return frame.IconFrame ~= nil and frame.state == state
		end)[1]
	end
	equal(Queued(), 0, label .. ": nothing waits")
	h.SetCombat(true)
	local card = Card("full")
	h.Click(card)
	h.flush()
	equal(h.ns.Route().journey, card.journey.key, label .. ": the card is chosen at once")
	equal(Starts(), 0, label .. ": its route waits for combat's end")
	equal(Queued(), 1, label .. ": which the footer says")
	h.SetCombat(false)
	h.flush()
	equal(Starts(), 1, label .. ": the route starts when combat ends")
	equal(Queued(), 0, label .. ": and the footer stops waiting")

	h.SetCombat(true)
	h.Click(Card("compact"))
	h.flush()
	h.Click(Card("chosen"))
	h.flush()
	h.SetCombat(false)
	h.flush()
	equal(Starts(), 1, label .. ": a choice cleared in combat starts nothing")
	equal(Queued(), 0, label .. ": nor waits")

	h.ns.SetSetting("titleStartsRoute", false)
	h.Click(Card("full"))
	h.flush()
	equal(Starts(), 1, label .. ": with the setting off a choice only chooses")
	h.ns.Integrations.Navigate(h.ns.Route().steps[1])
	h.Click(Card("chosen"))
	h.flush()
	equal(h.ns.Integrations.Owns(), true, label .. ": and clearing it stops nothing")
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

-- F16: with spells to train, one text-only trainer line in the guide and the tracker; otherwise none. Four Tweaks
-- Forever profiles: absent, no answer yet, nothing to train, and three spells.
do
	local SPELL = { name = "Lightning Bolt", level = 14, line = "Elemental", lineID = 375, general = false }
	local THREE = { SPELL, SPELL, SPELL }
	local rings0
	for _, case in ipairs({
		{ label = "no Tweaks Forever", lines = 0 },
		{ label = "no answer", tf = {}, lines = 0 },
		{ label = "nothing to train", tf = { spells = {} }, lines = 0 },
		{
			label = "three spells",
			tf = { spells = THREE },
			lines = 1,
			text = "Visit your class trainer · 3 new spells",
		},
	}) do
		local label = "trainer, " .. case.label
		local h = harness.load({
			spf = "v1+",
			db = PINS_ON,
			tf = case.tf,
			completed = { 844 },
			log = {
				{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
				{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
			},
		})
		h.ns.OpenPanel()
		h.flush()
		local lines = {}
		for _, frame in ipairs(h.frames) do
			for _, region in ipairs(frame.regions or {}) do
				local text = region:GetObjectType() == "FontString" and region:IsVisible() and region:GetText()
				if text and text:find("class trainer", 1, true) then
					lines[#lines + 1] = text
				end
			end
		end
		equal(#lines, case.lines, label .. ": panel lines")
		-- While completion data loads, the loading line sits under the trainer line, not over it.
		local ready = h.ns.State.Ready
		h.ns.State.Ready = function()
			return false
		end
		h.ns.Invalidate()
		h.flush()
		local trainerY, emptyY
		for _, frame in ipairs(h.frames) do
			for _, region in ipairs(frame.regions or {}) do
				local text = region:GetObjectType() == "FontString" and region:IsVisible() and region:GetText()
				local _, _, _, _, y = region:GetPoint(1)
				trainerY = text and text:find("class trainer", 1, true) and y or trainerY
				emptyY = text == h.ns.L.LOADING and y or emptyY
			end
		end
		equal(emptyY ~= nil, true, label .. ": the loading line")
		equal(emptyY <= (trainerY and trainerY - 14 or -8), true, label .. ": the loading line under the trainer's")
		h.ns.State.Ready = ready
		h.ns.Invalidate()
		h.flush()
		equal(lines[1], case.text, label .. ": the panel's line")
		local block = h.tracker.liveBlocks.trainer
		local shown = block and block.used and block.lines[1] or nil
		equal(shown, case.text and "3 new spells", label .. ": the tracker's line")
		-- Text only: no ring for it, and its tracker title neither guides nor sets a waypoint.
		local steps, rings = {}, 0
		for _, step in ipairs(h.ns.Route().steps) do
			steps[step] = true
		end
		for _, pin in ipairs(h.pins.AdventureGuideForeverPinTemplate or {}) do
			equal(steps[pin.step] or false, true, label .. ": every ring is a route step's")
			rings = rings + 1
		end
		rings0 = rings0 or rings
		equal(rings > 0 and rings == rings0, true, label .. ": as many rings as without Tweaks Forever")
		local waypoints, routes = h.counts.SetUserWaypoint, h.spf.Navigate + h.spf.NavigateRoute
		if block then
			h.tracker:OnBlockHeaderClick(block, "LeftButton")
			h.tracker:OnBlockHeaderClick(block, "RightButton")
			h.flush()
		end
		equal(h.counts.SetUserWaypoint - waypoints, 0, label .. ": no waypoint")
		equal(h.spf.Navigate + h.spf.NavigateRoute - routes, 0, label .. ": no guidance")
		equal(h.ns.Route().steps[1].key, "hub:346", label .. ": the route is unchanged")
		-- A spell learned at the trainer shortens the line at once.
		if case.tf and case.tf.spells == THREE then
			case.tf.spells = { SPELL }
			h.fire("SPELLS_CHANGED")
			h.flush()
			equal(h.tracker.liveBlocks.trainer.lines[1], "1 new spell", label .. ": one left")
			case.tf.spells = THREE
		end
		clean(h, label)
	end
end

-- The golden layout: any change to what the guide draws shows as a reviewable diff of tests/golden/layout.json. It is
-- the story card's towns with Shortest Path loaded (their counts, and step 1's minutes), as tests/scenes.lua draws it.
do
	local json, diff = dofile("tests/json.lua"), dofile("tests/dump_diff.lua")
	local h = Load("v1", nil, { journey = "story:1413" })
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
	equal(stored:lower():find("unreachable", 1, true), nil, "golden: no line ever says unreachable")

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
