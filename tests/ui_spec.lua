-- Run from the repository root: luajit tests/ui_spec.lua
-- Headless UI checks through tests/harness.lua. What they cannot reach is a /reload check.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- A table's array part in order, then its keyed fields by name, as one string.
local function Flat(value)
	if type(value) ~= "table" then
		return tostring(value)
	end
	local fields = {}
	for key, field in pairs(value) do
		if not (type(key) == "number" and key >= 1 and key <= #value and key % 1 == 0) then
			fields[#fields + 1] = tostring(key) .. " = " .. tostring(field)
		end
	end
	table.sort(fields)
	return table.concat(value, "\n") .. (#fields > 0 and "\n{" .. table.concat(fields, ", ") .. "}" or "")
end

local function same(actual, expected, label)
	equal(Flat(actual), Flat(expected), label)
end

-- The route's places: a ring each, a town the route comes back to sharing its first visit's (docs/design.md §2.9).
local function Places(route)
	local seen, count = {}, 0
	for _, step in ipairs(route.steps) do
		local place = step.kind == "town" and step.hub and (step.map .. ":town:" .. step.hub)
			or (step.map .. ":" .. step.x .. ":" .. step.y)
		if not seen[place] then
			seen[place], count = true, count + 1
		end
	end
	return count
end

-- A step menu's lines with "Not this quest" (design §2.18) after "Skip for now": one button for a lone quest, else
-- one per quest under it, titled as the log titles it.
local function WithNotThisQuest(ns, step, lines)
	local out = {}
	for _, line in ipairs(lines) do
		out[#out + 1] = line
		if line == "button: Skip for now" and #step.quests == 1 then
			out[#out + 1] = "button: " .. ns.L.NOT_THIS_QUEST
		elseif line == "button: Skip for now" and #step.quests > 1 then
			out[#out + 1] = "button: " .. ns.L.NOT_THIS_QUEST
			for _, id in ipairs(step.quests) do
				local entry = ns.State.Log()[id]
				out[#out + 1] = "  button: " .. ((entry and entry.title) or ns.Data.quests[id].title)
			end
		end
		if line == "button: " .. ns.L.ORDER_LATER then
			local added = false
			for _, giver in ipairs(step.checklist or {}) do
				if not giver.done then
					if not added then
						out[#out + 1] = "button: " .. ns.L.TOWN_SKIP_GIVER
						added = true
					end
					out[#out + 1] = "  button: " .. giver.name
				end
			end
		end
	end
	return out
end

local function clean(h, label)
	equal(#h.errors, 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
end

-- A level-18 orc shaman in The Barrens with one quest ready to hand in and one under way. `db` is the account's
-- saved settings; the map marks are off unless it turns them on. The character chose the Barrens story before, as a
-- player past their first session has; `charDB` false is a fresh character, with no card chosen. `away` adds a
-- finished quest handed in at Orgrimmar, off the story's map, so the log has a carry card.
local PINS_ON = { showMapPins = true, showQuestGivers = true }
local AWAY = 5729
local function Load(spf, db, charDB, away)
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	if away then
		log[3] =
			{ id = AWAY, title = "Hidden Enemies", level = 15, complete = true, map = 1454, x = 0.4947, y = 0.5059 }
	end
	-- autoStart is off here: these specs drive every route start explicitly (the title click, Go), so the auto-start on
	-- load would double it. tests/autostart_spec.lua covers the auto-start itself. Set after the copy: a shared db
	-- table (PINS_ON) has already had the addon's defaults merged into it by Core.LoadDB, autoStart included.
	local settings = {}
	for key, value in pairs(db or {}) do
		settings[key] = value
	end
	settings.autoStart = false
	return harness.load({
		planned = true,
		spf = spf or nil,
		db = settings,
		charDB = charDB ~= false and (charDB or { journey = "zone:1413" }) or nil,
		completed = { 844 },
		log = log,
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
	equal(h.ns.Route().steps[1].key, "town:376", label .. ": the hand-in leads the route")

	-- Blizzard's displayMode is never written, whatever the player clicks (Panel.lua ShowGuide).
	local panel, questsFrame = h.G.AdventureGuideForeverPanel, h.questMap.QuestsFrame
	h.ns.OpenPanel()
	h.flush()
	equal(panel:IsVisible(), true, label .. ": the guide opens")
	equal(questsFrame:IsShown(), false, label .. ": the quest list steps aside")
	-- F6: the first step, a quest in the log, is selected and shown on the map from its row and from the tracker,
	-- through C_Map.OpenWorldMap alone; in combat the row turns the map and the tracker opens the guide instead.
	local first = h.ns.Route().steps[1]
	local function Row()
		return Shown(h, function(frame)
			return frame.SkipButton ~= nil
		end)[1]
	end
	h.Click(Row())
	h.flush()
	equal(table.concat(h.selectedQuests, " "), tostring(first.quests[1]), label .. ": a row in the log selects it")
	equal(h.map:GetMapID(), h.G.GetQuestUiMapID(first.quests[1]), label .. ": and turns the map to its zone")
	equal(panel:IsShown(), true, label .. ": the guide stays open")
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	equal(panel:IsShown(), false, label .. ": the Quests tab closes the guide")
	equal(questsFrame:IsShown(), true, label .. ": the quest list is back")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[first.key], "LeftButton")
	h.flush()
	equal(#h.selectedQuests, 2, label .. ": so does a tracker click")
	equal(h.map:IsShown(), true, label .. ": which opens the map")
	h.SetCombat(true)
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[first.key], "LeftButton")
	h.flush()
	equal(panel:IsShown(), true, label .. ": a tracker click in combat opens the guide")
	h.Click(Row())
	equal(#h.selectedQuests, 2, label .. ": no quest is shown in combat")
	h.SetCombat(false)
	h.flush()
	h.ns.OpenPanel()
	h.flush()
	h.TriggerEvent("QuestLog.SetDisplayMode")
	equal(panel:IsShown(), false, label .. ": a display mode change closes the guide")
	h.ns.OpenPanel()
	h.G.QuestMapFrame_ShowQuestDetails(845)
	equal(panel:IsShown(), false, label .. ": quest details the player opens close the guide")
	equal(#h.questDetails, 1, label .. ": the guide never opens them itself")
	equal(h.counts.OpenQuestLog, 0, label .. ": nor the quest log, while its sidebar is shown")
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

-- F6: a group quest in the log (a "dungeon" step) is shown too; a group quest's pickup does not, and a town
-- opens its first hand-in.
do
	local h = Load(false)
	local show = h.ns.ShowQuest
	equal(show({ kind = "dungeon", key = "area:843:0", quests = { 843 } }), true, "a group quest in the log opens")
	local town = { kind = "town", key = "town:376", quests = { 843 }, pickups = { 843 }, handins = {} }
	equal(show(town), false, "a group pickup does not")
	town.quests, town.pickups, town.handins = { 845, 843 }, { 843 }, { 845 }
	equal(show(town), true, "a town with a hand-in opens it")
	equal(table.concat(h.selectedQuests, " "), "843 845", "each was selected once")
	equal(#h.questDetails, 0, "without Blizzard's details")
	h.SetCombat(true)
	equal(show(town), false, "nothing opens in combat")
	h.SetCombat(false)
end

-- The tracker title sets off along the route and tracks its quests; each part has its own setting, and untracking
-- the player's other quests is opt-in.
do
	local function RouteQuests(h)
		local quests, seen = {}, {}
		for _, step in ipairs(h.ns.Route().steps) do
			-- A town's log quests are its hand-ins; its pickups, and a lap's quests it picks up first, are not in the log.
			for _, questID in ipairs(step.kind == "town" and step.handins or step.quests) do
				if not seen[questID] and not (step.planned and step.planned[questID]) then
					quests[#quests + 1], seen[questID] = questID, true
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

	-- Tracking the route's quests is opt-in, so a title click leaves the player's watches alone.
	local h = Load("v1")
	h.watched[1] = 99
	ClickTitle(h)
	equal(h.ns.Setting("trackRouteQuests"), false, "tracking the route's quests is off by default")
	equal(table.concat(h.watched, " "), "99", "so the title click tracks nothing")
	clean(h, "title click, default tracking")

	-- A saved choice keeps its value.
	h = Load("v1", { trackRouteQuests = true })
	h.watched[1] = 99
	ClickTitle(h)
	equal(h.spf.NavigateRoute, 1, "the title starts the route")
	-- Each stop tells Shortest Path what stands there, so its pin shows the game's own mark rather than hiding it.
	for index, stop in ipairs(h.spfRoute.stops) do
		equal(stop.kind, h.ns.Integrations.Kind(h.ns.Route().steps[index]), "stop " .. index .. "'s kind")
		equal(stop.kind ~= nil, true, "stop " .. index .. " shows what stands there")
		local step = h.ns.Route().steps[index]
		equal(
			stop.hold,
			#(step.quests or {}) > 0 or #(step.handins or {}) > 0,
			"stop " .. index .. " holds quest interactions"
		)
	end
	local Kind = h.ns.Integrations.Kind
	local here, there = { map = 1429, x = 0.4, y = 0.5 }, { map = 1429, x = 0.6, y = 0.5 }
	equal(Kind({ kind = "turnin" } --[[@as AGFStep]]), "turnin", "kind: a hand-in")
	equal(Kind({ kind = "area" } --[[@as AGFStep]]), "objective", "kind: an objective area")
	equal(Kind({ kind = "trainer" } --[[@as AGFStep]]), "trainer", "kind: a trainer")
	equal(Kind({ map = 1429, x = 0.1, y = 0.1, title = "Giver", quests = { 1 } }), "pickup", "kind: a giver")
	local town = { kind = "town", map = here.map, x = here.x, y = here.y, handins = { 7 }, spots = { [7] = here } }
	equal(Kind(town --[[@as AGFStep]]), "turnin", "kind: a town whose point is a hand-in")
	town.spots[7] = there
	equal(Kind(town --[[@as AGFStep]]), "pickup", "kind: a town whose point is a giver")
	equal(h.watched[1], 99, "the player's own tracked quest stays")
	-- Gann's Reclamation is done on a later lap, so carry holds it.
	equal(RouteQuests(h), "845", "the route holds the log quest its lap hands in")
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

	-- With none chosen the tracker shows the first card's step, which the guide draws on its own (design §2.5), and
	-- its title's click chooses that card; in combat the start waits, and Shortest Path starts it once combat ends,
	-- with no waypoint meanwhile.
	h = Load("v1", nil, false)
	equal(h.ns.Route().chosen, false, "none chosen: nothing chosen yet")
	equal(h.tracker.liveBlocks[h.ns.Route().steps[1].key] ~= nil, true, "none chosen: the first card's step")
	h.SetCombat(true)
	ClickTitle(h)
	equal(h.ns.Prefs().journey, "zone:1413", "none chosen: the title chooses the first card")
	equal(h.spf.NavigateRoute + h.counts.SetUserWaypoint, 0, "none chosen: in combat nothing starts yet")
	h.SetCombat(false)
	h.flush()
	equal(h.spf.NavigateRoute, 1, "none chosen: the route starts once combat ends")
	equal(h.counts.SetUserWaypoint, 0, "none chosen: and no waypoint was set")
	equal(h.ns.Prefs().guided, "zone:1413", "none chosen: recorded as the chosen journey's route")
	clean(h, "title click chooses")

	h = Load("v1", { trackRouteQuests = true, untrackOthers = true })
	h.watched[1] = 99
	ClickTitle(h)
	equal(table.concat(h.watched, " "), RouteQuests(h), "untrackOthers leaves only the route's quests")

	h = Load("v1", { titleStartsRoute = false, trackRouteQuests = false, untrackOthers = true })
	h.watched[1] = 99
	ClickTitle(h)
	equal(h.spf.NavigateRoute, 0, "the route setting off: no route")
	local unset = Load("v1", { titleStartsRoute = false }, false)
	ClickTitle(unset)
	equal(unset.ns.Prefs().journey, nil, "the route setting off: the title chooses nothing")
	equal(unset.spf.NavigateRoute, 0, "the route setting off: and starts nothing")
	equal(table.concat(h.watched, " "), "99", "the tracking setting off: the tracked quests are untouched")

	local byKey, pages = {}, {}
	for _, entry in ipairs(h.settings) do
		if entry.key then
			byKey[entry.key] = entry
			local group = pages[entry.category] or {}
			pages[entry.category] = group
			group[#group + 1] = entry.key
		end
	end
	-- Every row goes in through the secure delegate; none from addon code, which taints the search. The rows are
	-- grouped into subcategories with a short index page, so no page grows tall.
	equal(h.taintedRows, 0, "no settings row is inserted from addon code")
	equal(#h.settings, 20, "16 rows and 4 index buttons, all through Settings.RegisterInitializer")
	local L = h.ns.L
	equal(
		table.concat(pages[L.SETTINGS_GROUP_ROUTE] or {}, " "),
		"wanderer followQuest optimisedRoute includeDungeonsDefault titleStartsRoute autoStart stepSound",
		"Route holds its rows in order"
	)
	equal(table.concat(pages[L.SETTINGS_GROUP_MAP] or {}, " "), "showMapPins showQuestGivers", "Map holds its rows")
	equal(
		table.concat(pages[L.SETTINGS_GROUP_TRACKER] or {}, " "),
		"attachTracker showTracker trackRouteQuests untrackOthers",
		"the objective tracker rows sit together, the parent first"
	)
	equal(
		table.concat(pages[L.SETTINGS_GROUP_INTERFACE] or {}, " "),
		"floatWindow suggestCompanions whatsNew",
		"Interface holds the window, companion and update rows"
	)
	-- The index page's buttons are on the addon's own category, one per group, in index order, and open its subpage.
	local buttons = {}
	for _, entry in ipairs(h.settings) do
		if entry.kind == "button" then
			buttons[#buttons + 1] = entry
		end
	end
	equal(#buttons, 4, "one index button per group")
	equal(
		buttons[1].name .. " " .. buttons[2].name .. " " .. buttons[3].name .. " " .. buttons[4].name,
		L.SETTINGS_GROUP_ROUTE
			.. " "
			.. L.SETTINGS_GROUP_MAP
			.. " "
			.. L.SETTINGS_GROUP_TRACKER
			.. " "
			.. L.SETTINGS_GROUP_INTERFACE,
		"the index lists every group in order"
	)
	for index, button in ipairs(buttons) do
		equal(button.category, h.ns.TITLE, "index button " .. index .. " stays on the addon's page")
		equal(button.addSearchTags, false, "index button " .. index .. " stays out of search")
		equal(button.tooltip, L.SETTINGS_OPEN, "index button " .. index .. " is the Open button")
		button.onClick()
		equal(h.openedSettings, h.subcategories[index].GetID(), "index button " .. index .. " opens its own subpage")
		equal(h.subcategories[index].name, button.name, "index button " .. index .. " names its subpage")
		equal(h.subcategories[index].parent.name, h.ns.TITLE, "and the subpage hangs off the addon's page")
	end
	equal(byKey.untrackOthers.indented, true, "untrackOthers is indented under tracking")
	equal(byKey.untrackOthers.evaluateCVar, "AdventureGuideForever_trackRouteQuests", "parent changes reevaluate child")
	equal(byKey.untrackOthers.enabled(), false, "and is greyed while it is off")
	local attachSetting
	for _, setting in ipairs(h.addonSettings) do
		if setting.key == "attachTracker" then
			attachSetting = setting
		end
	end
	equal(attachSetting ~= nil, true, "shared tracker setting is registered")
	equal(attachSetting.GetValue(), true, "shared tracker defaults attached")
	h.ns.TrackerHostSettings().attached = false
	equal(h.ns.TrackerHostSettings().attached, false, "AGF account host state retains saved false")
	local malformed = Load("v1", { trackerHost = "bad" })
	equal(malformed.ns.TrackerHostSettings().attached, true, "AGF account host state normalizes malformed value")
	h.trackerHostSettings.attached = false
	equal(attachSetting.GetValue(), false, "shared tracker reads the host owner state")
	h.trackerHostSettings.attached = true
	attachSetting:SetValue(false)
	equal(h.trackerHostSettings.attached, false, "shared tracker setting writes shared host state")
	attachSetting:SetValue(true)
	equal(attachSetting.GetValue(), true, "shared tracker setting round trips attached")
	-- The client re-sorts its watches by distance on every zone change (Blizzard_ObjectiveTracker.lua
	-- SortQuestWatches), so the tooltip promises no order it cannot keep.
	equal(byKey.trackRouteQuests.tooltip:find("order") ~= nil, false, "the tracking tooltip promises no order")
	clean(h, "title click settings")
end

-- Guidance follows the chosen journey (design §2.10): a route AGF started for it is sent again, once, when a stop
-- it has yet to reach leaves the steps, step 1 is neither the stop it heads for nor the one just reached, or step 1's
-- point has moved past the town linkage. Never in combat, in the air, off the map, or once it no longer guides ours.
do
	local function S(...)
		local steps = {}
		for index, key in ipairs({ ... }) do
			steps[index] = { key = key }
		end
		return steps
	end
	local function never()
		return false
	end
	local function always()
		return true
	end
	local Stale, handed = Load(false).ns.Guidance.Stale, S("a", "b", "c")
	for _, case in ipairs({
		{ 1, S("a", "b", "c"), never, false, "unchanged" },
		{ 1, S("a", "c", "b"), never, false, "later stops reorder" },
		{ 2, S("b", "c"), never, false, "arrived at a: b is next" },
		{ 2, S("a", "b", "c"), never, false, "a still open where it just arrived" },
		{ 1, S("b", "c"), never, true, "a skipped before arriving" },
		{ 2, S("b"), never, true, "c left the steps" },
		{ 1, S("c", "a", "b"), never, true, "step 1 is elsewhere" },
		{ 1, S("a", "b", "c"), always, true, "step 1's point moved far" },
		{ 1, S("d", "a", "b", "c"), never, true, "a new stop comes first" },
		{ 3, S("c", "d"), never, false, "a new stop after the one it heads for" },
		{ 1, {}, never, true, "no steps: every stop left" },
	}) do
		equal(Stale(handed, case[1], case[2], case[3]), case[4], "stale: " .. case[5])
	end

	local function Moved(h, map, x, y)
		h.MovePlayer(map, x, y)
		h.ns.Invalidate()
		h.flush()
	end
	-- A rebuild far from the route keeps it (design §4.2): the player moving is no reason to change the way.
	local h = Load("ended")
	local function Keys()
		local keys = {}
		for index, step in ipairs(h.ns.Route().steps) do
			keys[index] = step.key
		end
		return table.concat(keys, " ")
	end
	local before = Keys()
	Moved(h, 1413, 0.46, 0.79)
	equal(Keys(), before, "follow: a rebuild away from the route keeps it")
	h = Load("ended")
	h.ns.StartRoute()
	h.flush()
	equal(h.ns.Prefs().guided, "zone:1413", "follow: the chosen journey's route")
	equal(h.spf.NavigateRoute, 1, "follow: started once")
	Moved(h, h.player.map, h.player.x, h.player.y)
	equal(h.spf.NavigateRoute, 1, "follow: a rebuild that changes nothing sends nothing")
	-- Southsea Freebooters and Baron Longshore are in the log: their objective areas join the route after the town's
	-- stops, so the way is sent again, and once the player stands in the first, it leads.
	h.log[#h.log + 1] = { id = 887, title = "Southsea Freebooters", level = 14, complete = false }
	h.log[#h.log + 1] = { id = 895, title = "WANTED: Baron Longshore", level = 16, complete = false }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(h.spf.NavigateRoute, 2, "follow: a route change after step 1 sends once")
	Moved(h, 1413, 0.64, 0.46)
	local head = h.ns.Route().steps[1]
	equal(head.key, "area:887:0", "follow: the area the player stands in leads")
	-- Entering an objective area retains the current approach and all later route stops.
	equal(head.here, true, "follow: you're here")
	equal(h.spf.NavigateRoute, 3, "follow: in step 1's area, the stops after it sent")
	local onward = h.ns.Route().steps
	equal(#h.spfRoute.stops, #onward, "follow: proximity keeps every stop")
	equal(h.spfRoute.stops[1].x, onward[1].x, "follow: current area retains its destination")
	equal(h.ns.Guidance.Owns(), true, "follow: guidance holds, so Stop still shows")
	Moved(h, 1413, 0.64, 0.47)
	equal(h.spf.NavigateRoute, 3, "follow: nothing again while the player is in it")
	h.SetCombat(true)
	Moved(h, 1413, 0.5223, 0.3101)
	equal(h.spf.NavigateRoute, 3, "follow: nothing in combat")
	h.SetCombat(false)
	h.flush()
	equal(h.spf.NavigateRoute, 4, "follow: out of the area, once combat ends, the route goes on")
	equal(h.ns.Prefs().guided, "zone:1413", "follow: still the chosen journey's")
	-- Standing in the Crossroads still shows the complete route.
	equal(#h.spfRoute.stops, #h.ns.Route().steps, "follow: town proximity keeps later stops")
	h.onTaxi = true
	Moved(h, 1413, 0.46, 0.79)
	equal(h.spf.NavigateRoute, 4, "follow: nothing in the air")
	h.onTaxi = false
	Moved(h, nil, nil, nil)
	equal(h.spf.NavigateRoute, 4, "follow: nothing off the map")
	Moved(h, 1413, 0.5223, 0.3101)
	Moved(h, 1413, 0.5224, 0.3101)
	equal(h.spf.NavigateRoute, 4, "follow: near the town, its complete route remains active")
	Moved(h, 1413, 0.46, 0.79)
	equal(h.spf.NavigateRoute, 5, "follow: out of the town, the journey goes on")
	equal(#h.spfRoute.stops, #h.ns.Route().steps, "follow: every step")
	-- Shortest Path moves on stop by stop until it heads for the Crossroads, then the player reaches it.
	for _, step in ipairs(h.ns.Route().steps) do
		if step.key == "town:376" then
			break
		end
		h.spfAdvance()
	end
	Moved(h, 1413, 0.5223, 0.3101)
	equal(h.spf.NavigateRoute, 6, "follow: retarget the nearest remaining giver in town")
	h.spfOther()
	Moved(h, 1413, 0.46, 0.79)
	Moved(h, 1413, 0.5223, 0.3101)
	equal(h.spf.NavigateRoute, 6, "follow: another journey replaced ours: nothing")
	clean(h, "follow")

	-- The "you're here" head (design §4.2): checked every 2 s only while the player moves, and a rebuild only on
	-- walking into an open area the route reaches later, once.
	h = Load("ended")
	h.log[#h.log + 1] = { id = 887, title = "Southsea Freebooters", level = 14, complete = false }
	h.log[#h.log + 1] = { id = 895, title = "WANTED: Baron Longshore", level = 16, complete = false }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(h.ns.Route().steps[1].key ~= "area:887:0", true, "here: the area is later while the player is in town")
	h.fire("PLAYER_STARTED_MOVING")
	equal(next(h.ticking) ~= nil, true, "here: moving checks")
	local builds = h.modelCalls.Journeys
	h.tickers()
	h.flush()
	equal(h.modelCalls.Journeys, builds, "here: no rebuild while the player is in no area")
	h.MovePlayer(1413, 0.64, 0.46)
	h.tickers()
	h.flush()
	equal(h.ns.Route().steps[1].key, "area:887:0", "here: walking into the area makes it step 1")
	builds = h.modelCalls.Journeys
	h.tickers()
	h.flush()
	equal(h.modelCalls.Journeys, builds, "here: once")
	h.fire("PLAYER_STOPPED_MOVING")
	h.flush()
	equal(next(h.ticking), nil, "here: standing still checks nothing")
	clean(h, "here")

	-- Following the quest worked on (Focus.lua): walking into step 1's area selects its quest, so the map draws its
	-- blue area; walking out clears it. Never over the player's own selection.
	h = Load("ended")
	h.log[#h.log + 1] = { id = 887, title = "Southsea Freebooters", level = 14, complete = false }
	h.log[#h.log + 1] = { id = 895, title = "WANTED: Baron Longshore", level = 16, complete = false }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(h.superTrackedQuest, 0, "focus: nothing selected outside the area")
	Moved(h, 1413, 0.64, 0.46)
	equal(h.ns.Route().steps[1].here, true, "focus: in step 1's area")
	equal(h.superTrackedQuest, 887, "focus: its quest selected")
	equal(h.ns.Prefs().focus, 887, "focus: kept as AGF's")
	-- They are there: no "Walk to <zone>" line to the area's middle.
	equal(h.ns.Integrations.Travel(h.ns.Route().steps[1]), nil, "focus: no travel line in the area")
	local selected = h.counts.SetSuperTrackedQuestID
	Moved(h, 1413, 0.64, 0.47)
	equal(h.counts.SetSuperTrackedQuestID, selected, "focus: once, on walking in")
	Moved(h, 1413, 0.5223, 0.3101)
	equal(h.superTrackedQuest, 0, "focus: walking out clears it")
	equal(h.ns.Prefs().focus, nil, "focus: forgotten")
	h.superTrackedQuest = 843
	Moved(h, 1413, 0.64, 0.46)
	equal(h.superTrackedQuest, 843, "focus: the player's own selection stays")
	Moved(h, 1413, 0.5223, 0.3101)
	equal(h.superTrackedQuest, 843, "focus: and stays on walking out")
	h.superTrackedQuest = 0
	h.ns.SetSetting("followQuest", false)
	Moved(h, 1413, 0.64, 0.46)
	equal(h.superTrackedQuest, 0, "focus: the setting off selects nothing")
	clean(h, "focus")

	-- Without Shortest Path, Go sets the waypoint at the step; walking out does not move it, since the area's
	-- objective is unfinished and its point sits on the work rather than chasing the player.
	h = Load(false, PINS_ON)
	h.log[#h.log + 1] = { id = 887, title = "Southsea Freebooters", level = 14, complete = false }
	h.log[#h.log + 1] = { id = 895, title = "WANTED: Baron Longshore", level = 16, complete = false }
	Moved(h, 1413, 0.64, 0.46)
	local standing = h.ns.Route().steps[1]
	equal(standing.here, true, "here, waypoint: in the area")
	h.G.C_Map.OpenWorldMap()
	h.map:SetMapID(1413)
	h.flush()
	h.providers[1]:RefreshAllData()
	local numbered = false
	for _, pin in ipairs(h.pins.AdventureGuideForeverPinTemplate or {}) do
		numbered = numbered or pin.step == standing
	end
	equal(numbered, false, "here, waypoint: no numbered pin where the player is")
	local later = false
	for _, pin in ipairs(h.pins.AdventureGuideForeverPinTemplate or {}) do
		later = later or pin.step == h.ns.Route().steps[2]
	end
	equal(later, true, "here, waypoint: the stops after it keep theirs")
	h.ns.StartRoute()
	h.flush()
	equal(h.counts.SetUserWaypoint, 1, "here, waypoint: Go retains the nearby destination")
	equal(h.ns.Guidance.Owns(), true, "here, waypoint: guidance holds")
	Moved(h, 1413, 0.46, 0.79)
	local leftFor = h.ns.Route().steps[1]
	equal(leftFor.here, nil, "here, waypoint: out of it")
	equal(leftFor.key, standing.key, "here, waypoint: the route holds its unfinished step")
	equal(h.counts.SetUserWaypoint, 1, "here, waypoint: the destination does not chase the player")
	local point = h.G.C_Map.GetUserWaypoint()
	equal(point and point.position.x, leftFor.x, "here, waypoint: at step 1")
	clean(h, "here, waypoint")

	-- Started outside the town, every step is handed; Shortest Path reaching the town moves on at once, and the player
	-- in it with work left gets the town alone again, so the minimap draws no way out before its quests are taken.
	h = Load("ended")
	Moved(h, 1413, 0.5383, 0.3101)
	h.ns.StartRoute()
	h.flush()
	local steps = #h.ns.Route().steps
	equal(#h.spfRoute.stops, steps, "follow, town: started outside it, every step")
	h.spfAdvance()
	Moved(h, 1413, 0.5223, 0.3101)
	equal(h.spf.NavigateRoute, 1, "follow, town: reaching it never truncates the route")
	equal(#h.spfRoute.stops, steps, "follow, town: every stop remains visible")
	h.spfEnd("arrived")
	Moved(h, 1413, 0.5224, 0.3101)
	equal(h.spf.NavigateRoute, 1, "follow, town: explicit arrival does not restart unchanged guidance")
	clean(h, "follow, town")

	-- The town is as wide as its quests' places, not its point: by the giver farthest from the point, still in it.
	h = Load("ended")
	local town = h.ns.Route().steps[1]
	---@type AGFPlace?
	local far, farYards = nil, 0
	for _, quest in pairs(h.ns.Data.quests) do
		for _, place in ipairs({ quest.start or false, quest.finish or false }) do
			local yards = place and place.hub == town.hub and h.ns.Model.Yards(h.ns.Data, town, place)
			if yards and yards > farYards then
				far, farYards = place, yards
			end
		end
	end
	equal(farYards > 100, true, "follow, town wide: a giver past the linkage from its point")
	---@cast far -?
	Moved(h, far.map, far.x, far.y)
	equal(h.ns.Route().steps[1].key, town.key, "follow, town wide: the town still step 1")
	h.ns.StartRoute()
	h.flush()
	equal(#h.spfRoute.stops, #h.ns.Route().steps, "follow, town wide: proximity preserves the route")
	clean(h, "follow, town wide")

	-- Without Shortest Path, the waypoint Go set for the chosen journey moves to its new step 1; on a map that refuses
	-- one it stays, with no error line; one the player moved is theirs and never touched.
	h = Load(false)
	h.ns.StartRoute()
	h.flush()
	local sets = h.counts.SetUserWaypoint
	Moved(h, 1413, 0.46, 0.79)
	local first = h.ns.Route().steps[1]
	equal(h.counts.SetUserWaypoint, sets + 1, "waypoint follows: moved to the new step 1")
	equal(h.waypoint.position.x .. " " .. h.waypoint.position.y, first.x .. " " .. first.y, "waypoint follows: there")
	equal(h.ns.Guidance.Owns(), true, "waypoint follows: still ours")
	Moved(h, 1413, 0.46, 0.78)
	equal(h.counts.SetUserWaypoint, sets + 1, "waypoint follows: once")
	h.noWaypoint[1413] = true
	Moved(h, 1413, 0.5223, 0.3101)
	equal(h.counts.SetUserWaypoint, sets + 1, "waypoint follows: a map that refuses one leaves it")
	equal(#h.uiErrors, 0, "waypoint follows: with no error line")
	h.noWaypoint[1413] = nil
	h.waypoint = { uiMapID = 1413, position = { x = 0.3, y = 0.3 } }
	Moved(h, 1413, 0.46, 0.79)
	Moved(h, 1413, 0.5223, 0.3101)
	equal(h.counts.SetUserWaypoint, sets + 1, "waypoint follows: one the player moved is never touched")
	clean(h, "waypoint follows")

	-- A route the step menu or a giver started is not the chosen journey's: it is never sent again.
	h = Load("ended")
	h.ns.Guidance.Navigate(h.ns.Route().steps[1])
	h.flush()
	Moved(h, 1413, 0.46, 0.79)
	equal(h.spf.NavigateRoute, 1, "follow: a route not the journey's stays as handed")
end

-- A chosen journey the full build no longer has ends (design §2.10): its route stops and the cards are whole again,
-- "complete" only after a turn-in. A filter keeps the choice but stops the route; nothing ends before the completed
-- quests load, or in combat.
do
	-- The carry card is the journey that ends: the story's zone always has more.
	local function Started(spf, charDB)
		local h = Load(spf, nil, charDB or { journey = "carry" }, true)
		h.ns.StartRoute()
		h.flush()
		h.completes = 0
		local complete = h.ns.OnJourneyComplete
		h.ns.OnJourneyComplete = function()
			h.completes = h.completes + 1
			complete()
		end
		return h
	end
	local function Emptied(h, event, id)
		for index = #h.log, 1, -1 do
			table.remove(h.log, index)
		end
		h.fire(event, id)
		h.flush()
	end
	for _, case in ipairs({ { "QUEST_TURNED_IN", AWAY, 1, "turned in" }, { "QUEST_LOG_UPDATE", nil, 0, "abandoned" } }) do
		local h, label = Started("v1"), "ends, " .. case[4]
		equal(h.ns.Prefs().guided, "carry", label .. ": guided before")
		Emptied(h, case[1], case[2])
		equal(h.ns.Prefs().journey, nil, label .. ": the choice is cleared")
		equal(h.ns.Prefs().guided, nil, label .. ": and its guidance")
		equal(h.spf.Cancel, 1, label .. ": our route cancelled once")
		equal(h.ns.Route().chosen, false, label .. ": none chosen again")
		equal(h.completes, case[3], label .. ": complete only after a turn-in")
		equal(#h.fanfares, case[3], label .. ": the tracker glows once, or not at all")
		clean(h, label)
	end

	-- The tracker's "Journey complete": its glow without the story's sound, its click opens the guide, and the next
	-- route change takes it away.
	local h = Started("v1")
	Emptied(h, "QUEST_TURNED_IN", AWAY)
	local block = h.tracker.liveBlocks["journey-complete"]
	equal(block and block.header, "Journey complete", "journey complete: the header")
	-- None is chosen now: the header, then the step of the first card, which the guide draws on its own.
	local first = h.ns.Route().steps[1].key
	same(
		h.tracker.layoutOrder,
		{ "journey-complete", "journey", first },
		"journey complete: over the first card's step"
	)
	same(h.fanfares, { "journey-complete" }, "journey complete: glows once")
	equal(#h.sounds, 0, "journey complete: no stage-end sound")
	local opened, openPanel = 0, h.ns.OpenPanel
	h.ns.OpenPanel = function()
		opened = opened + 1
	end
	h.tracker:OnBlockHeaderClick(block, "LeftButton")
	h.ns.OpenPanel = openPanel
	equal(opened, 1, "journey complete: a click opens the guide")
	equal(h.spf.NavigateRoute, 1, "journey complete: and starts nothing")
	h.ns.Invalidate()
	h.flush()
	same(h.tracker.layoutOrder, { "journey", first }, "journey complete: gone on the next route change")

	h = Started("v1")
	h.SetCombat(true)
	Emptied(h, "QUEST_LOG_UPDATE")
	equal(h.ns.Prefs().journey, "carry", "ends: not in combat")
	equal(h.spf.Cancel, 0, "ends: nothing cancelled in combat")
	h.SetCombat(false)
	h.flush()
	equal(h.ns.Prefs().journey, nil, "ends: on the full build combat's end brings")
	clean(h, "ends, combat")

	h = Started(false)
	Emptied(h, "QUEST_LOG_UPDATE")
	equal(h.counts.ClearUserWaypoint, 1, "ends, no Shortest Path: the waypoint Go set is cleared")

	h = Started("v1", { journey = "zone:1413" })
	equal(h.ns.Prefs().guided, "zone:1413", "filtered: guided before")
	h.ns.Prefs().quests = false
	h.ns.Invalidate()
	h.flush()
	equal(h.ns.Prefs().journey, "zone:1413", "filtered: the choice kept, should the toggle bring it back")
	equal(h.spf.Cancel, 1, "filtered: our route cancelled")
	clean(h, "filtered")

	-- Your calling holds quests, so the Quests toggle keeps its choice too: a level-12 orc warrior in
	-- Durotar, whose trainer has a task.
	h = harness.load({
		planned = true,
		player = { level = 12, classID = 1, map = 1411, x = 0.52, y = 0.44 },
		charDB = { journey = "calling" },
	})
	h.flush()
	equal(h.ns.Route().chosen and h.ns.Route().journey, "calling", "filtered calling: chosen")
	h.ns.Prefs().quests = false
	h.ns.Invalidate()
	h.flush()
	equal(h.ns.Route().chosen, false, "filtered calling: no card with Quests off")
	equal(h.ns.Prefs().journey, "calling", "filtered calling: the choice kept")
	clean(h, "filtered calling")

	-- With no next zone Dungeons hides nothing, so a chosen dungeon that went has ended; below the cap
	-- the toggle keeps it.
	for _, case in ipairs({ { 70, nil, "at the cap" }, { 18, "dungeon:1", "below the cap" } }) do
		h = harness.load({
			planned = true,
			player = { level = case[1] },
			charDB = { journey = "dungeon:1", dungeons = false },
		})
		h.flush()
		equal(h.ns.Prefs().journey, case[2], "dungeon gone, " .. case[3])
		clean(h, "dungeon gone, " .. case[3])
	end

	h = harness.load({ planned = true, charDB = { journey = "zone:1413" }, completedPending = true })
	h.flush()
	equal(h.ns.Prefs().journey, "zone:1413", "ends: nothing before the completed quests load")
end

-- How our journey ended (design §2.10), from Shortest Path's Ended or, without it, guessed: another journey running
-- replaced it, the player at its last stop arrived, anything else was cleared. Arriving keeps the guidance, and a
-- step it was never handed extends it; cleared or replaced forgets it, so nothing sends it again.
do
	local function Ending(spf, how, at)
		local h = Load(spf)
		h.ns.StartRoute()
		h.flush()
		local handed = h.spfRoute.stops
		if at then
			local last = handed[#handed]
			h.MovePlayer(last.map, last.x, last.y)
		else
			-- Out of the Crossroads, where the route starts as the town alone: its last stop is not where it ends.
			h.MovePlayer(1413, 0.46, 0.79)
		end
		how(h)
		h.fire("SUPER_TRACKING_CHANGED")
		h.flush()
		return h
	end
	local function Arrive(h)
		h.spfEnd("arrived")
	end
	local function Clear(h)
		h.spfEnd("cleared")
	end
	local function Replace(h)
		h.spfOther()
	end
	for _, spf in ipairs({ "ended", "v1+", "v1" }) do
		local label = "ended, " .. spf
		local h = Ending(spf, Arrive, true)
		equal(h.ns.Prefs().guided, "zone:1413", label .. ", arrived: the guidance is kept")
		equal(h.ns.Guidance.Status(), "arrived", label .. ", arrived: and known")
		h = Ending(spf, Clear, spf == "ended")
		equal(h.ns.Prefs().guided, nil, label .. ", cleared: the guidance is forgotten")
		h.ns.Invalidate()
		h.flush()
		equal(h.spf.NavigateRoute, 1, label .. ", cleared: nothing sends it again")
		if spf ~= "v1" then
			h = Ending(spf, Replace, true)
			equal(h.ns.Prefs().guided, nil, label .. ", replaced: the guidance is forgotten")
		end
	end
	-- A genuinely new stop extends an arrived route once. Keep this API contract independent of planner scoring.
	local h = Ending("ended", Arrive, true)
	local expanded = h.ns.Route()
	expanded.steps[#expanded.steps + 1] = {
		key = "area:new",
		kind = "area",
		title = "Fresh",
		quests = { 846 },
		map = 1413,
		x = 0.2,
		y = 0.2,
	}
	h.ns.Route = function()
		return expanded
	end
	h.fire("SUPER_TRACKING_CHANGED")
	h.flush()
	equal(h.spf.NavigateRoute, 2, "ended, arrived: a new stop extends the route")
	equal(h.ns.Guidance.Status() == "arrived", false, "ended, arrived: which guides again")
	h.fire("SUPER_TRACKING_CHANGED")
	h.flush()
	equal(h.spf.NavigateRoute, 2, "ended, arrived: once")
	-- Our own Stop is no ending to judge.
	h = Ending("ended", function(stopped)
		stopped.ns.Guidance.Cancel()
	end)
	equal(h.ns.Guidance.Status() == "arrived", false, "ended, cancelled: not arrived")
end

-- The one question the views ask (Guidance.Status), and a reorder's restart (Guidance.Reroute): only a route AGF runs
-- for the chosen journey starts again, a frame on.
do
	local h = Load("ended")
	equal(h.ns.Guidance.Status(), nil, "status: nothing chosen, nothing to tell")
	h.ns.Guidance.Reroute()
	h.flush()
	equal(h.spf.NavigateRoute, 0, "reroute: nothing of ours runs, nothing starts")
	h.ns.StartRoute()
	h.flush()
	equal(h.ns.Guidance.Status(), nil, "status: running")
	equal(h.ns.Guidance.Owns(), true, "status: running is Owns")
	h.ns.Guidance.Reroute()
	equal(h.spf.NavigateRoute, 1, "reroute: not in the reorder's own frame")
	h.flush()
	equal(h.spf.NavigateRoute, 2, "reroute: the chosen journey's route starts again")
	h.SetCombat(true)
	equal(h.ns.StartRoute(), true, "status: a start in combat waits")
	equal(h.ns.Guidance.Status(), "queued", "status: queued until combat ends")
	h.SetCombat(false)
	h.flush()
	equal(h.ns.Guidance.Status(), nil, "status: then it runs")
	h.spfEnd("arrived")
	h.fire("SUPER_TRACKING_CHANGED")
	h.flush()
	equal(h.ns.Guidance.Status(), "arrived", "status: arrived at its last stop, not paused")
	h.ns.Stop()
	h.flush()
	equal(h.ns.Guidance.Status(), nil, "status: the player's Stop leaves nothing to resume")
	clean(h, "status")
end

-- No Go (design §2.10): while the chosen journey's route is paused (cleared in Shortest Path, replaced, refused), its
-- card resumes it, says so, and the footer says how; while the route runs, a click on it stops nothing and its tooltip
-- points to the back arrow. Our own Stop, a route that arrived, or the setting off pause nothing.
do
	local L
	local function Chosen(h)
		return Shown(h, function(frame)
			return frame.IconFrame ~= nil and frame.state == "chosen"
		end)[1]
	end
	local function Hint(h)
		for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
			if entry.text == L.ROUTE_PAUSED then
				return true
			end
		end
		return false
	end
	local function Tip(h)
		h.Hover(Chosen(h))
		return table.concat(h.tooltip, "\n")
	end
	local function Opened(spf, db, how)
		local h = Load(spf, db)
		L = h.ns.L
		h.ns.OpenPanel()
		h.flush()
		h.ns.StartRoute()
		h.flush()
		if how then
			how(h)
			h.fire("SUPER_TRACKING_CHANGED")
			h.flush()
		end
		return h
	end

	local h = Opened("ended")
	equal(h.ns.Guidance.Status() == "paused", false, "paused: not while it guides")
	equal(Hint(h), false, "paused: no hint while it guides")
	equal(Tip(h):find(L.BACK_TO_ALL, 1, true) ~= nil, true, "paused: guiding, the tooltip points to the back arrow")
	h.Click(Chosen(h))
	h.flush()
	equal(h.ns.Guidance.Owns(), true, "paused: guiding, the click stops nothing")
	equal(h.ns.Prefs().journey, "zone:1413", "paused: guiding, and keeps the choice")

	h = Opened("ended", nil, function(cleared)
		cleared.spfEnd("cleared")
	end)
	equal(h.ns.Guidance.Status(), "paused", "paused: cleared in Shortest Path")
	equal(Hint(h), true, "paused: the footer says the card resumes it")
	equal(Tip(h):find(L.CLICK_TO_RESUME, 1, true) ~= nil, true, "paused: the tooltip says the click resumes")
	equal(Tip(h):find(L.REPLACES_JOURNEY, 1, true), nil, "paused: nothing to replace")
	h.Click(Chosen(h))
	h.flush()
	equal(h.spf.NavigateRoute, 2, "paused: the click resumes the route")
	equal(h.ns.Prefs().journey, "zone:1413", "paused: and keeps the choice")
	equal(h.ns.Prefs().guided, "zone:1413", "paused: as the chosen journey's route")
	equal(Hint(h), false, "paused: the hint goes")
	h.Click(Chosen(h))
	h.flush()
	equal(h.ns.Prefs().journey, "zone:1413", "paused: once resumed, the next click keeps the choice")
	equal(h.ns.Guidance.Owns(), true, "paused: and the route")
	equal(h.spf.NavigateRoute, 2, "paused: without starting it again")
	clean(h, "paused")

	h = Opened("ended", nil, function(replaced)
		replaced.spfOther()
	end)
	equal(h.ns.Guidance.Status(), "paused", "paused: replaced by another journey")
	equal(Tip(h):find(L.REPLACES_JOURNEY, 1, true) ~= nil, true, "paused, replaced: resuming warns first")

	-- The tracker title resumes it too.
	h = Opened("ended", nil, function(cleared)
		cleared.spfEnd("cleared")
	end)
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[h.ns.Route().steps[1].key], "LeftButton")
	h.flush()
	equal(h.spf.NavigateRoute, 2, "paused: the tracker title resumes it")

	for _, case in ipairs({
		{
			"our Stop",
			nil,
			function(stopped)
				stopped.ns.Guidance.Cancel()
			end,
		},
		{
			"arrived",
			nil,
			function(done)
				done.spfEnd("arrived")
			end,
		},
		{
			"held",
			nil,
			function(held)
				held.spfHeld = true
			end,
		},
		{
			"the setting off",
			{ titleStartsRoute = false },
			function(cleared)
				cleared.ns.Guidance.Navigate(cleared.ns.Route().steps[1])
				cleared.spfEnd("cleared")
			end,
		},
	}) do
		h = Opened("ended", case[2], case[3])
		equal(h.ns.Guidance.Status() == "paused", false, "not paused: " .. case[1])
		equal(Hint(h), false, "not paused, " .. case[1] .. ": no hint")
	end
	local routes = h.spf.NavigateRoute
	h.Click(Chosen(h))
	h.flush()
	equal(h.ns.Prefs().journey, "zone:1413", "not paused: the click keeps the choice")
	equal(h.spf.NavigateRoute, routes, "not paused: and starts nothing")
end

-- Shortest Path's journeys end with the session: a /reload or login with a route AGF started for the chosen journey
-- sends it again once, on the first full build out of combat. Not over someone else's journey; a refusal sets no
-- waypoint and asks again on the next full build; Stop, a cleared card or no saved variables restore nothing.
do
	-- autoStart off: this block is about restoring a route that was started before (prefs.guided), not about the
	-- auto-start on load, which tests/autostart_spec.lua covers.
	local function Reloaded(charDB, setup)
		local h = harness.load({
			planned = true,
			spf = "v1+",
			db = { autoStart = false },
			charDB = charDB,
			initialLogin = false,
			completed = { 844 },
			log = {
				{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			},
			setup = setup,
		})
		h.flush()
		return h
	end
	local h = Reloaded({ journey = "zone:1413", guided = "zone:1413" })
	equal(h.spf.NavigateRoute, 1, "restore: our route runs again")
	equal(h.ns.Integrations.Guiding(), true, "restore: and guides")
	equal(h.ns.Prefs().guided, "zone:1413", "restore: still the chosen journey's")
	h.ns.Invalidate()
	h.flush()
	equal(h.spf.NavigateRoute, 1, "restore: once")
	clean(h, "restore")

	h = Reloaded({ journey = "zone:1413", guided = "zone:1413" }, function(reloaded)
		reloaded.spfOther()
	end)
	equal(h.spf.NavigateRoute, 0, "restore: never over someone else's journey")
	equal(h.ns.Prefs().guided, nil, "restore: which keeps the way")

	h = Reloaded({ journey = "zone:1413", guided = "zone:1413" }, function(reloaded)
		reloaded.SetCombat(true)
	end)
	equal(h.spf.NavigateRoute, 0, "restore: not in combat")
	h.SetCombat(false)
	h.flush()
	equal(h.spf.NavigateRoute, 1, "restore: once combat ends")

	h = Reloaded({ journey = "zone:1413", guided = "zone:1413" }, function(reloaded)
		reloaded.spfDeclines = true
	end)
	equal(h.counts.SetUserWaypoint, 0, "restore, declined: no waypoint")
	equal(h.ns.Prefs().guided, "zone:1413", "restore, declined: the route is kept")
	h.spfDeclines = false
	h.ns.Invalidate()
	h.flush()
	equal(h.spf.NavigateRoute, 2, "restore, declined: asked again on the next full build")
	equal(h.ns.Integrations.Guiding(), true, "restore, declined: and guides once it takes it")

	for _, case in ipairs({
		{ { journey = "zone:1413" }, "after Stop" },
		{ { guided = "zone:1413" }, "after a cleared card" },
		{ nil, "no saved variables" },
	}) do
		h = Reloaded(case[1])
		equal(h.spf.NavigateRoute + h.counts.SetUserWaypoint, 0, "restore, " .. case[2] .. ": nothing starts")
	end
end

-- WFA-13: nothing runs per frame while idle, and a refresh reuses the frames it has.
local function IdleUpdates(h)
	local busy = 0
	for _, frame in ipairs(h.frames) do
		busy = busy + (frame.scripts.OnUpdate and 1 or 0)
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
	equal(#h.pins.AdventureGuideForeverPinTemplate, Places(h.ns.Route()), label .. ": the refreshes drew the route")
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	h.flush()
	equal(IdleUpdates(h), 0, label .. ": per-frame work once the guide is closed")
	clean(h, label .. ": idle")
end

-- Background markers have exactly one owner; route rings remain separate.
do
	local h = Load(false, PINS_ON)
	h.G.C_Map.OpenWorldMap()
	h.flush()
	h.map:SetMapID(1442)
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate > 0, true, "standalone giver baseline")
	h.installed.Questie = true
	h.providers[1]:RefreshAllData()
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate > 0, true, "disabled Questie does not claim markers")
	h.metadata.Questie = { Version = "test" }
	h.providers[1]:RefreshAllData()
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, 0, "loaded Questie owns background markers")
	h.G.Questie = { db = { profile = { enabled = false } } }
	h.providers[1]:RefreshAllData()
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, 0, "Questie hide toggle cannot reveal duplicates")
	h.map:SetMapID(1413)
	equal(#h.pins.AdventureGuideForeverPinTemplate > 0, true, "route markers remain with Questie")
end

-- Map pins: a refresh replaces, never adds; removal leaves none; the tooltips read as design §2.9 and the tracker
-- menu as §2.8.
for _, spf in ipairs({ false, "v1" }) do
	local label = spf or "no Shortest Path"
	local click = spf and "instruction: Click to travel with Shortest Path" or "instruction: Click to set a waypoint"
	local h = Load(spf, PINS_ON)
	local provider, ns = h.providers[1], h.ns
	h.G.C_Map.OpenWorldMap()
	h.flush()
	local function Live()
		return #h.pins.AdventureGuideForeverPinTemplate + #h.pins.AdventureGuideForeverGiverPinTemplate
	end
	provider:RefreshAllData()
	local first = Live()
	provider:RefreshAllData()
	equal(Live(), first, label .. ": a second refresh keeps the pin count")
	equal(#h.pins.AdventureGuideForeverPinTemplate, Places(ns.Route()), label .. ": one ring per place on this map")

	local ring = h.pins.AdventureGuideForeverPinTemplate[1]
	equal(ring.Number.file, "Interface\\WorldMap\\UI-QuestPoi-NumberIcons", label .. ": the stock quest numeral")
	same(ring.Number.texCoord, { 0, 0.125, 0.5, 0.625 }, label .. ": stock gold numeral 1")
	-- Rings draw above the stock quest marks; givers stay under them (Blizzard_WorldMap.lua:291-311).
	equal(ring.frameLevelType, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", label .. ": rings at the user waypoint's level")
	h.Hover(ring)
	-- With Shortest Path, step 1 adds its travel line; the stub answers 360 s. Step 1 is the Crossroads, where The
	-- Zhevra opens its next chapter, handed in before the town's pickups.
	local expected = { "title: 1. Visit Crossroads, The Barrens: Pick up 4, turn in 1" }
	expected[#expected + 1] = spf and "highlight: About 6 min away" or nil
	expected[#expected + 1] = "highlight: Opens the next chapter here"
	expected[#expected + 1] = "normal: Sergra Darkthorn"
	expected[#expected + 1] = "colored: |A:questturnin:14:14|a [13] The Zhevra"
	same({ unpack(h.tooltip, 1, #expected) }, expected, label .. ": ring tooltip")
	equal(h.tooltip[#h.tooltip], click, label .. ": ring tooltip instruction")
	equal(ring.Glow:IsShown(), true, label .. ": hover glow")
	ring:OnMouseLeave()
	equal(ring.Glow:IsShown(), false, label .. ": glow off after hover")

	-- Stonetalon has quest givers and no route step, so every eligible giver gets a "!".
	h.map:SetMapID(1442)
	local givers = ns.Model.Givers(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), 1442)
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, #givers, label .. ": a giver pin per eligible giver")
	equal(#h.pins.AdventureGuideForeverPinTemplate, 0, label .. ": no rings off the route's map")
	-- The first giver whose quests the route can take: a giver's hard quests get a pin but no shift-click.
	local giverPin
	for _, pin in ipairs(h.pins.AdventureGuideForeverGiverPinTemplate) do
		if #pin.giver.adds > 0 then
			giverPin = pin
			break
		end
	end
	equal(giverPin ~= nil, true, label .. ": a giver the route can take from")
	equal(giverPin.frameLevelType, "PIN_FRAME_LEVEL_AREA_POI", label .. ": givers at the area POI level")
	h.Hover(giverPin)
	-- Closing the map fires no OnMouseLeave: the pin's own OnHide takes its tooltip.
	h.map:SetShown(not h.map:IsShown())
	equal(h.G.GameTooltip:IsShown(), false, label .. ": closing the map takes a hovered giver's tooltip")
	h.map:SetShown(not h.map:IsShown())
	h.Hover(giverPin)
	equal(h.tooltip[1], "title: " .. giverPin.giver.title, label .. ": giver tooltip title")
	equal(#h.tooltip, #giverPin.giver.quests + 3, label .. ": a giver tooltip line per quest")
	equal(h.tooltip[#h.tooltip - 1], click, label .. ": giver tooltip instruction")
	equal(h.tooltip[#h.tooltip], "instruction: " .. ns.L.SHIFT_ADD, label .. ": and the shift-click's")
	-- The client answers "" for a title it hasn't cached: the line falls back to the data's title.
	local titleFor = h.G.C_QuestLog.GetTitleForQuestID
	h.G.C_QuestLog.GetTitleForQuestID = function()
		return ""
	end
	h.Hover(giverPin)
	local uncached = ns.Data.quests[giverPin.giver.quests[1]]
	equal(
		h.tooltip[2],
		"normal: "
			.. ns.L.QUEST_LEVEL:format(
				uncached.level == -1 and h.G.UnitLevel("player") or uncached.level,
				uncached.title
			),
		label .. ": an uncached title reads the data's"
	)
	h.G.C_QuestLog.GetTitleForQuestID = titleFor
	-- A shift-click adds the giver's quests to the route (design §2.18), and a second takes them off.
	-- Pinning puts the quests on the route, so the redraw can hand this pin another giver: the click keeps its own.
	local navigated = h.counts.SetUserWaypoint + (h.spf and h.spf.NavigateRoute or 0)
	local giver = giverPin.giver
	h.Shift(function()
		giverPin:OnClick("LeftButton")
	end)
	equal(ns.Pinned(giver.adds), true, label .. ": a shift-click adds the giver's quests")
	equal(h.counts.SetUserWaypoint + (h.spf and h.spf.NavigateRoute or 0), navigated, label .. ": and goes nowhere")
	h.Hover(giverPin)
	equal(h.tooltip[#h.tooltip], "instruction: " .. ns.L.SHIFT_REMOVE, label .. ": then offers to take them off")
	h.Shift(function()
		giverPin:OnClick("LeftButton")
	end)
	h.flush()
	equal(next(ns.Prefs().pinned), nil, label .. ": a second shift-click takes them off")

	-- The story card's step tells its chapter under the title (design §2.9).
	h.map:SetMapID(1413)
	ns.Prefs().journey = ns.Route().journeys[1].key
	ns.Invalidate()
	h.flush()
	local chapter
	for _, pin in ipairs(h.pins.AdventureGuideForeverPinTemplate) do
		chapter = pin.step.chapter and pin or chapter
	end
	h.Hover(chapter)
	equal(h.tooltip[2], "normal: Chapter 1 of 8", label .. ": the story's ring tells its chapter")
	ns.Prefs().journey = nil
	ns.Invalidate()
	h.flush()

	provider:RemoveAllData()
	equal(Live(), 0, label .. ": RemoveAllData leaves no pins")

	-- Design §2.8's menu for a town holding a log quest; Stop only once Go runs, Show quest never in combat.
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks["town:376"], "RightButton")
	local menu = {
		"title: Visit Crossroads, The Barrens: Pick up 4, turn in 1",
		"button: Go",
		"button: Show quest",
		"button: Skip for now",
		"button: Choose another journey",
	}
	same(h.MenuLines(), WithNotThisQuest(ns, ns.Route().steps[1], menu), label .. ": tracker menu")
	ns.Guidance.Navigate(ns.Route().steps[1])
	h.SetCombat(true)
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks["town:376"], "RightButton")
	h.SetCombat(false)
	menu[3] = "button: Stop"
	same(
		h.MenuLines(),
		WithNotThisQuest(ns, ns.Route().steps[1], menu),
		label .. ": tracker menu while Go guides, in combat"
	)
	ns.Guidance.Cancel()
	clean(h, label .. ": pins")
end

-- A pooled stop can change from a later shared pin to the current stop, and cross the numeric texture's limit.
do
	local h = Load(false, PINS_ON)
	h.G.C_Map.OpenWorldMap()
	h.flush()
	local pin = h.pins.AdventureGuideForeverPinTemplate[1]
	local step = pin.step
	local visits = { { step = step, index = 25 }, { step = step, index = 26 } }
	pin:OnAcquired(step, 25, visits)
	equal(pin:GetWidth(), 20, "POI: fixed 20-unit button")
	equal(pin.ignoreGlobalPinScale, true, "POI: ignores the global pin scale")
	same(pin.scalingLimits, { 1, 1, 1 }, "POI: unchanged by map zoom")
	equal(pin.Icon:GetAtlas(), "UI-QuestPoi-QuestNumber", "POI: stock button")
	equal(pin.Disc:GetAtlas(), pin.Icon:GetAtlas(), "POI: silhouette follows the stock art")
	same(pin.Disc.vertexColor, { 0, 0, 0 }, "POI: black silhouette")
	equal(pin.Disc:GetAlpha(), 1, "POI: faded stops keep an opaque silhouette")
	for _, region in ipairs({ pin.Icon, pin.Number, pin.NumberText, pin.Badge }) do
		equal(region:GetAlpha(), 0.9, "POI: later stop fades every foreground part")
	end
	for _, region in ipairs({ pin.Disc, pin.Icon, pin.Number, pin.Glow }) do
		same({ region:GetSize() }, { 32, 32 }, "POI: stock 32-unit art") -- multi-value: width and height
	end
	same(pin.Number.texCoord, { 0, 0.125, 0.875, 1 }, "POI: final tinted numeral")
	equal(pin.Badge:IsShown(), true, "POI: repeated visits keep the quest badge")
	equal(pin.More, nil, "POI: no count covering the badge")
	h.ns.Pins.Ping(step.key)
	equal(pin.Glow.flashing, true, "POI: the glow flashes when the guide pings a stop")
	h.G.UIFrameFlashStop(pin.Glow)
	equal(pin.Icon:GetAlpha(), 0.9, "POI: a completed ping preserves the later stop's fade")
	h.ns.Pins.Ping(step.key)
	pin:OnMouseEnter()
	equal(pin.Glow.flashing, nil, "POI: hover takes over from the ping")
	equal(pin.Glow:IsShown(), true, "POI: hover restores the steady glow")
	h.ns.Pins.Ping(step.key)
	pin:OnMouseLeave()
	equal(pin.Glow.flashing, nil, "POI: leaving cancels the ping before the pin is reused")
	equal(pin.Glow:IsShown(), false, "POI: leaving clears the glow")
	pin:OnAcquired(step, 26)
	equal(pin.Number:IsShown(), false, "POI: no texture cell after 25")
	equal(pin.NumberText:GetText(), "26", "POI: font fallback after 25")
	equal(pin.NumberText.font, "GameFontNormal", "POI: stock fallback font")
	equal(pin.More, nil, "POI: reused lone stop has no count")
	equal(pin.Badge:IsShown(), true, "POI: reused lone stop restores its kind")
	pin:OnAcquired(step, 1)
	equal(pin.Number:IsShown(), true, "POI: reused current stop restores its numeral")
	equal(pin.NumberText:GetText(), "", "POI: reused current stop clears its fallback")
	for _, region in ipairs({ pin.Icon, pin.Number, pin.NumberText, pin.Badge }) do
		equal(region:GetAlpha(), 1, "POI: reused current stop restores full strength")
	end
	pin:OnAcquired({ x = step.x, y = step.y }, 9)
	same(pin.Number.texCoord, { 0, 0.125, 0.625, 0.75 }, "POI: tinted numerals wrap to the next row")
	equal(pin.Badge:IsShown(), false, "POI: an unmarked stop loses its badge")
	same(pin.hitRectInsets, { 0, 0, 0, 0 }, "POI: an unmarked stop restores the plain hit rect")
	clean(h, "POI reuse")
end

-- An area step on the map (design §2.6): its numbered pin where the route enters it and nothing more, since the
-- game's own objective mark shows the area; its tooltip lists each open objective under its quest in the client's
-- words, else its count.
do
	-- With the Barrens story ruled out, Gann's Reclamation is off every zone loop, so carry (Quests in your log) holds it.
	local h = harness.load({
		planned = true,
		-- A copy, never the shared PINS_ON table: Core.LoadDB merges the addon's defaults into whatever db it is given.
		db = { showMapPins = true, showQuestGivers = true },
		charDB = {
			journey = "carry",
			notInterested = { ["zone:1413"] = { title = "The Barrens story" } },
		},
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{
				id = 843,
				title = "Gann's Reclamation",
				level = 23,
				complete = false,
				objectives = {
					{ type = "monster", done = false, have = 7, need = 15, text = "Bael'dun Excavator slain: 7/15" },
					{ type = "monster", done = false, have = 2, need = 5, text = "" },
					{ type = "item", done = true, have = 1, need = 1, text = "Resonite Crystal: 1/1" },
				},
			},
		},
	})
	h.G.C_Map.OpenWorldMap()
	h.flush()
	h.providers[1]:RefreshAllData()
	local index, step
	for i, candidate in ipairs(h.ns.Route().steps) do
		index, step = candidate.key == "area:843:0" and i or index, candidate.key == "area:843:0" and candidate or step
	end
	equal(step and step.kind, "area", "area step: Gann's Reclamation is an area step")
	equal(h.pins.AdventureGuideForeverAreaPinTemplate, nil, "area step: no disc of ours over the area")
	-- The step's point, and its pin, is the objective node nearest the stop before (design §4.2), a spot inside one of
	-- its shapes rather than on the ring's border.
	local inside = false
	for _, shape in ipairs(step.shapes) do
		local yards = h.ns.Model.Yards(h.ns.Data, step, shape)
		inside = inside or (yards ~= nil and yards <= shape.r)
	end
	equal(inside, true, "area step: its pin on an objective's spot, inside a shape")
	local pin
	for _, candidate in ipairs(h.pins.AdventureGuideForeverPinTemplate) do
		pin = candidate.step == step and candidate or pin
	end
	h.Hover(pin)
	local expected = {
		"title: " .. index .. ". Defeat Bael'dun Excavator slain: 7/15 · Gann's Reclamation",
		"highlight: quests in progress",
		"colored: [23] Gann's Reclamation",
		"highlight: - Bael'dun Excavator slain: 7/15",
		"highlight: - 2/5",
	}
	same({ unpack(h.tooltip, 1, #expected) }, expected, "area step: the pin's tooltip counts what is left")
	equal(h.tooltip[#expected + 1], "instruction: Click to set a waypoint", "area step: the done objective left out")
	pin:OnMouseLeave()
	clean(h, "area step")
end

-- F1, the map budget: a fresh install draws no mark with the tab closed; opted in, at most 9 rings and exactly the
-- zone's eligible givers, which stay while Shortest Path guides; either switch off hides every giver. The rings,
-- the open guide's preview included, step aside while it guides.
do
	local h = Load(false)
	h.G.C_Map.OpenWorldMap()
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
	h.G.C_Map.OpenWorldMap()
	h.flush()
	local rings = #h.pins.AdventureGuideForeverPinTemplate
	equal(rings <= ns.Model.MAX_STEPS, true, label .. ": at most 9 rings")
	equal(rings, case.db.showMapPins and Places(ns.Route()) or 0, label .. ": a ring per place, only with pins on")
	h.map:SetMapID(1442)
	local givers = #ns.Model.Givers(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), 1442)
	equal(givers > 0, true, label .. ": Stonetalon has givers")
	local expected = case.givers and givers or 0
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, expected, label .. ": givers")
	ns.Guidance.Navigate(ns.Route().steps[1])
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
-- are drawn, not left to stops nobody draws. A card on a map the old route walks picks a giver only where no
-- guided stop already draws one, so the card here is one on a map the old route never reaches.
do
	local h = Load("v1", PINS_ON)
	local ns = h.ns
	h.G.C_Map.OpenWorldMap()
	h.flush()
	ns.Guidance.Navigate(ns.Route().steps[1])
	local walked = {}
	for _, step in ipairs(ns.Guidance.Guided()) do
		walked[step.map] = true
	end
	local nextZone
	for _, journey in ipairs(ns.Route().journeys) do
		nextZone = nextZone or (journey.kind == "nextzone" and not walked[journey.map] and journey or nil)
	end
	equal(nextZone and nextZone.kind, "nextzone", "guided givers: a next-zone card")
	---@cast nextZone -?
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
	-- One Model.Plan call per rebuild, and an invalidation that lands while a rebuild is under way is coalesced into
	-- exactly one follow-up (Core.StepRebuild). The rebuild itself is sliced across frames, so a tick is a slice, not
	-- the whole build; only each rebuild's travel frame asks Shortest Path, once (unit F0).
	local plan, builds = h.ns.Model.Plan, 0
	h.ns.Model.Plan = function(...)
		builds = builds + 1
		return plan(...) -- multi-value: the wrapper is transparent
	end
	local est = Estimates()
	h.ns.Invalidate()
	h.flush()
	equal(builds, 1, spf .. ": one build per rebuild")
	equal(Estimates() - est, 1, spf .. ": the rebuild's travel frame asks once")
	h.ns.Invalidate()
	h.tick() -- begin the next rebuild (one slice, not the whole build)
	h.ns.Invalidate() -- lands while it is under way: one follow-up, not two builds
	h.flush()
	equal(builds, 3, spf .. ": the second rebuild and the one its invalidation earns")
	equal(Estimates() - est, 2, spf .. ": the skipped travel frame asks nothing; the follow-up asks once")
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
			-- Shortest Path names only the zone; the step knows the town.
			"Walk to Crossroads, The Barrens · 3 min",
		},
		{ "no route", false, nil },
	}
	h.spfLegs = cases[4][2]
	-- A step with no place: the player already stands in the zone Shortest Path names, so a walk within it names the
	-- stop the step is, never the zone the player is in.
	local area = setmetatable(
		{ place = false, title = "Complete objectives · The Greenbelt", zone = "The Barrens" },
		{ __index = step }
	)
	equal(
		ns.Integrations.TravelLine(area),
		"Walk to Complete objectives · The Greenbelt · 3 min",
		"travel line, on foot to a step with no place: where the walk ends"
	)
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
	ns.Prefs().journey = "zone:1413"
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
	-- Step 1 begins the town's work and opens the lead chain's next chapter, so the way comes before the chapter line.
	same({ unpack(h.tooltip, 1, 3) }, {
		"title: 1. " .. rows[1].step.title,
		"highlight: " .. cases[4][3],
		"highlight: Opens the next chapter here",
	}, "travel line: step 1's tooltip")
	h.spfLegs = cases[1][2]
	h.Hover(rows[2])
	equal(h.spf.EstimateDetail, calls + 1, "travel line: another row's tooltip asks once")
	-- Step 2 is the lead chain's chapter, so its chapter line comes before the way.
	same({ unpack(h.tooltip, 1, 3) }, {
		"title: 2. " .. rows[2].step.title,
		"normal: Chapter 1 of 8",
		"highlight: " .. cases[1][3],
	}, "travel line: another row's tooltip")
	clean(h, "travel line")

	h = Load(false)
	equal(h.ns.Integrations.TravelLine(h.ns.Route().steps[1]), nil, "travel line: none without Shortest Path")
end

-- The combat rule: in combat a rebuild runs only the cheap path, which still shows the
-- log's news, and the full build runs once, when combat ends. No timer: PLAYER_REGEN_ENABLED brings it.
do
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	local h = harness.load({ planned = true, completed = { 844 }, log = log })
	local ns, before = h.ns, h.modelCalls.Journeys
	local story = ns.Route().journeys[1]
	h.SetCombat(true)
	for _ = 1, 10 do
		ns.Invalidate()
		h.flush()
	end
	log[2].complete = true
	ns.Invalidate()
	ns.Route()
	h.flush()
	equal(h.modelCalls.Journeys - before, 0, "combat: no full build in combat")
	equal(ns.Route().journey, "zone:1413", "combat: the chosen card holds")
	-- A quest finished mid-fight: carry, fresh from the log, hands it in. Gann's waits for a later lap on the story
	-- (Ratchet's leads), so the story, which never drew it, keeps every step.
	local keys, cards = {}, ns.Route().journeys
	for _, journey in ipairs(cards) do
		for _, step in ipairs(journey.steps) do
			keys[step.key] = journey.kind
		end
	end
	equal(keys["turnin:843"], "carry", "combat: a quest finished mid-fight is ready to hand in")
	equal(keys["area:843:0"], nil, "combat: its objective step is gone")
	equal(cards[1].key, story.key, "combat: the story stays first")
	equal(#cards[1].steps, #story.steps, "combat: the story's steps hold")
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
	h.ns.Guidance.Navigate(h.ns.Route().steps[1])
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
	local guided = h.ns.Guidance.Navigate(step)
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
	h.ns.Guidance.Navigate(step)
	equal(h.ns.Integrations.Guiding(), true, "declined later: the first Go guides")
	h.spfDeclines, h.noWaypoint[step.map] = true, true
	equal(h.ns.Guidance.Navigate(step), false, "declined later, no waypoint map: nothing new guides")
	equal(h.spf.Cancel, 0, "declined later, no waypoint map: the earlier journey is kept")
	h.noWaypoint[step.map], h.uiErrors = nil, {}
	equal(h.ns.Guidance.Navigate(step), true, "declined later: the waypoint guides")
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
	ns.Guidance.Navigate(ns.Route().steps[1])
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
	ns.Guidance.Navigate(ns.Route().steps[1])
	local moved = h.waypoint
	h.waypoint = { uiMapID = moved.uiMapID, position = { x = moved.position.x + 0.01, y = moved.position.y } }
	equal(ns.Guidance.Owns(), false, "stop: a waypoint the player moved is theirs")
	ns.Guidance.Cancel()
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
		planned = true,
		charDB = h.G.AdventureGuideForeverCharDB,
		waypoint = h.waypoint,
		initialLogin = false,
		completed = { 844 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	})
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
	equal(reloaded.ns.Prefs().journey, nil, "stop: the menu's Stop clears the choice too")
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
	-- As a click on the guided card: no journey is left chosen with nothing to resume it.
	equal(ns.Prefs().journey, nil, "stop, Shortest Path: and clears the choice")
	equal(ns.Guidance.Status() == "paused", false, "stop, Shortest Path: nothing is paused")
	equal(h.counts.ClearUserWaypoint, 0, "stop, Shortest Path: no native waypoint to clear")
	ns.Guidance.Navigate(ns.Route().steps[1])
	h.G.ShortestPathForever.API.Cancel("AdventureGuideForever")
	ns.Invalidate()
	h.flush()
	equal(stop:IsShown(), false, "stop, Shortest Path: hidden once CurrentStop is nil")
	clean(h, "stop, Shortest Path")

	-- Held, its "Guide me" off: the journey stays ours to stop, but nothing walks it, so the rings come back, and a
	-- click in combat sets no waypoint over it.
	h = Load("v1+", PINS_ON)
	h.ns.StartRoute()
	h.flush()
	equal(h.ns.Integrations.Guiding(), true, "held: guiding before")
	h.spfHeld = true
	h.ns.Invalidate()
	h.flush()
	equal(h.ns.Integrations.Guiding(), false, "held: not guiding")
	equal(h.ns.Guidance.Owns(), true, "held: still ours to stop")
	equal(#h.ns.Guidance.Guided(), 0, "held: no stops it walks")
	h.SetCombat(true)
	equal(h.ns.Guidance.Navigate(h.ns.Route().steps[1]), false, "held, combat: Go waits")
	equal(h.counts.SetUserWaypoint, 0, "held, combat: no waypoint over it")
	h.SetCombat(false)
	clean(h, "held")
end

-- The step menu (design §2.8) from a step row, and "Skipped (n)": hidden at 0, it counts the session's skips and
-- opens the same Skipped submenu, whose "Show again" puts a step back where the route had it.
do
	local h = Load(false, nil, false)
	local ns = h.ns
	ns.OpenPanel()
	h.flush()
	local story = ns.Route().journeys[1]
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
	local before, first = Keys(), ns.Route().steps[1]
	local function Rows()
		return Shown(h, function(frame)
			return frame.SkipButton ~= nil
		end)
	end
	h.Click(Rows()[1], "RightButton")
	same(
		h.MenuLines(),
		WithNotThisQuest(ns, first, {
			"title: " .. first.title,
			"button: Go",
			"button: Stop",
			"button: Show quest",
			"button: Skip for now",
			"button: Choose another journey",
			-- The chosen journey's order (docs/design.md §2.20).
			"divider",
			"button: " .. ns.L.ORDER_NEXT,
			"button: " .. ns.L.ORDER_SOONER,
			"button: " .. ns.L.ORDER_LATER,
		}),
		"step menu: a town with a hand-in shows it; choosing started the route, which Stop ends"
	)
	local skipped = h.Find(function(frame)
		return frame.text ~= nil and frame.text:match("^Skipped")
	end)
	equal(#skipped, 0, "skipped: no button at 0")
	h.menu.entries[5].onClick()
	h.flush()
	local row = Rows()[1]
	-- Skipping the lead re-plans the lap, so the second skip is the step now at the head.
	local second = row.step
	local skip = row.SkipButton
	equal(skip:GetAlpha(), 0, "skip X: hidden while its row is not under the mouse")
	row.mouseOver = true
	row:GetScript("OnEnter")(row)
	equal(skip:GetAlpha(), 1, "skip X: shows on the row's hover")
	equal(skip.Icon.desaturated, true, "skip X: grey on the row's hover, never a red mark at rest")
	skip.mouseOver = true
	skip:GetScript("OnEnter")(skip)
	equal(skip.Icon.desaturated, false, "skip X: red with the mouse on it")
	skip.mouseOver, row.mouseOver = false, false
	skip:GetScript("OnLeave")(skip)
	equal(skip:GetAlpha(), 0, "skip X: hidden again once the mouse leaves")
	h.Click(skip)
	h.flush()
	local button = Shown(h, function(frame)
		return frame.text == "Skipped (2)"
	end)[1]
	equal(button ~= nil, true, "skipped: reads Skipped (2) after 2 skips")
	h.Click(Rows()[1], "RightButton")
	local submenu = { "  button: Show again: " .. first.title, "  button: Show again: " .. second.title }
	same(
		h.MenuLines(),
		WithNotThisQuest(ns, ns.Route().steps[1], {
			"title: " .. ns.Route().steps[1].title,
			"button: Go",
			"button: Stop",
			"button: Skip for now",
			"button: Skipped (2)",
			submenu[1],
			submenu[2],
			"button: Choose another journey",
			"divider",
			"button: " .. ns.L.ORDER_NEXT,
			"button: " .. ns.L.ORDER_SOONER,
			"button: " .. ns.L.ORDER_LATER,
		}),
		"step menu: the Skipped submenu"
	)
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
-- "Not this quest" (design §2.18): a step's menu drops one of its quests on this character, off the route and left in
-- the log; Skipped lists it, and Show again brings it back.
do
	local h = Load(false)
	local ns = h.ns
	h.flush()
	local step = ns.Route().steps[1]
	local id = step.quests[1]
	local function Holds()
		for _, candidate in ipairs(ns.Route().steps) do
			for _, quest in ipairs(candidate.quests) do
				if quest == id then
					return true
				end
			end
		end
		return false
	end
	local function Entry(entries, text)
		for _, entry in ipairs(entries) do
			if entry.text == text then
				return entry
			end
		end
	end
	local logged = ns.State.Log()[id] ~= nil
	equal(Holds(), true, "not this quest: the route has it")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[step.key], "RightButton")
	local entry = assert(Entry(h.menu.entries, ns.L.NOT_THIS_QUEST), "not this quest: in the step's menu")
	entry = #step.quests > 1 and entry.entries[1] or entry
	h.call(entry.onClick)
	h.flush()
	equal(Holds(), false, "not this quest: off the route")
	equal(ns.State.Log()[id] ~= nil, logged, "not this quest: the log keeps what it had")
	local saved = h.G.AdventureGuideForeverCharDB.notInterested["quest:" .. id]
	equal(saved and saved.title ~= nil, true, "not this quest: saved on this character, with its title")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[ns.Route().steps[1].key], "RightButton")
	local skipped = assert(Entry(h.menu.entries, "Skipped (1)"), "not this quest: Skipped (1)")
	equal(skipped.entries[1].text, ns.L.SHOW_AGAIN:format(saved.title), "not this quest: Show again names it")
	h.call(skipped.entries[1].onClick)
	h.flush()
	equal(Holds(), true, "not this quest: Show again brings it back")
	equal(h.G.AdventureGuideForeverCharDB.notInterested["quest:" .. id], nil, "not this quest: and forgets it")
	clean(h, "not this quest")
end

-- The log-full note (design §2.18): with 2 or fewer free slots, the first card counts the quests the guide would let go
-- and its tooltip names them. Advice only: nothing is abandoned.
do
	local grey = 788
	local h = harness.load({
		planned = true,
		logMax = 4,
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = grey, title = "Cutting Teeth", level = 2, complete = false },
		},
	})
	local ns = h.ns
	ns.OpenPanel()
	h.flush()
	local first = ns.Route().journeys[1]
	equal(first.drop and table.concat(first.drop, " "), tostring(grey), "log full: the grey quest could go")
	local card = Shown(h, function(frame)
		return frame.IconFrame ~= nil and frame.journey == first
	end)[1]
	equal(card.Reason:GetText(), ns.L.LOG_FULL_ONE, "log full: line 3 counts them")
	h.Hover(card)
	local tip = table.concat(h.tooltip, "\n")
	equal(tip:find(ns.L.LOG_FULL_LIST, 1, true) ~= nil, true, "log full: the tooltip says why")
	equal(tip:find("highlight: Cutting Teeth", 1, true) ~= nil, true, "log full: and names each")
	clean(h, "log full")
end

-- "Not interested": a journey card's right-click hides it on this character, the choice of it ends, and
-- Skipped (n) under the cards and in the cog lists it with Show again. The carry card, here for the quest handed in
-- at Orgrimmar, has no menu.
do
	local h = Load(false, nil, {
		journey = "carry",
		notInterested = {
			["zone:1"] = 5,
			[2] = "x",
			["zone:3"] = { chosen = true },
			["zone:9"] = "Kept",
			["zone:8"] = { title = "Chosen", chosen = true, extra = 1 },
		},
	}, true)
	local ns = h.ns
	local kept = ns.Prefs().notInterested
	equal(
		kept["zone:1"] == nil and kept[2] == nil and kept["zone:3"] == nil,
		true,
		"not interested: a malformed saved entry is dropped"
	)
	same(kept["zone:9"], { title = "Kept" }, "not interested: a saved title alone is a journey that was not chosen")
	same(kept["zone:8"], { title = "Chosen", chosen = true }, "not interested: a good one stays")
	ns.Unskip("zone:9")
	equal(ns.Prefs().journey, "carry", "not interested: Show again of one not chosen chooses nothing")
	ns.Unskip("zone:8")
	equal(ns.Prefs().journey, "zone:8", "not interested: Show again of a saved choice chooses it")
	ns.Choose("carry")
	ns.OpenPanel()
	h.flush()
	local function Card(kind)
		return Shown(h, function(frame)
			return frame.IconFrame ~= nil and frame.journey ~= nil and frame.journey.kind == kind
		end)[1]
	end
	h.menu = nil
	h.Click(Card("carry"), "RightButton")
	equal(h.menu, nil, "not interested: the carry card has no menu")
	local story = Card("story").journey
	h.Click(Card("story"))
	h.flush()
	equal(ns.Route().journey, story.key, "not interested: the story chosen")
	h.Click(Card("story"), "RightButton")
	same(h.MenuLines(), { "title: " .. story.title, "button: Not interested" }, "not interested: the card's menu")
	local hovered = Card("story")
	hovered:GetScript("OnEnter")(hovered)
	h.menu.entries[2].onClick()
	h.flush()
	equal(ns.Prefs().journey, nil, "not interested: the choice of it ends")
	-- The choice ended, so the overview shows, the chosen view's card with it gone.
	equal(hovered:IsVisible(), false, "not interested: the chosen card goes with its choice")
	local featured = Shown(h, function(frame)
		return frame.Icon ~= nil and frame.Icon.Clip ~= nil and frame.journey ~= nil
	end)[1]
	equal(featured ~= nil and featured.journey.key ~= story.key, true, "not interested: the overview, without it")
	equal(h.ns.Guidance.Owns(), false, "not interested: and its route stops")
	same(
		h.G.AdventureGuideForeverCharDB.notInterested[story.key],
		{ title = story.title, chosen = true },
		"not interested: saved per character, with the choice it ended"
	)
	for _, journey in ipairs(ns.Route().journeys) do
		equal(journey.key ~= story.key, true, "not interested: its card is gone")
	end
	local button = Shown(h, function(frame)
		return frame.text == "Skipped (1)"
	end)[1]
	equal(button ~= nil, true, "not interested: Skipped (1) under the cards")
	local cog = h.Find(function(frame)
		return frame.name == "AdventureGuideForeverSettingsButton"
	end)[1]
	local lines = h.MenuLines(h.OpenMenu(cog))
	local listed = false
	for index, line in ipairs(lines) do
		listed = listed
			or (line == "button: Skipped (1)" and lines[index + 1] == "  button: Show again: " .. story.title)
	end
	equal(listed, true, "not interested: the cog's Skipped (1) offers it back")
	h.Click(button)
	h.menu.entries[1].onClick()
	h.flush()
	equal(h.G.AdventureGuideForeverCharDB.notInterested[story.key], nil, "not interested: Show again forgets it")
	equal(ns.Prefs().journey, story.key, "not interested: Show again chooses the journey it ended")
	local back = false
	for _, journey in ipairs(ns.Route().journeys) do
		back = back or journey.key == story.key
	end
	equal(back, true, "not interested: and its card returns")
	-- From the overview: the card under the pointer takes the next journey, and its tooltip speaks for it.
	ns.Choose(nil)
	h.flush()
	local over = Shown(h, function(frame)
		return frame.Icon ~= nil and frame.Icon.Clip ~= nil and frame.journey ~= nil
	end)[1]
	local gone = over.journey
	h.Click(over, "RightButton")
	h.Hover(over)
	h.menu.entries[2].onClick()
	h.flush()
	equal(
		over.journey.key ~= gone.key and h.tooltip[1] == "title: " .. over.journey.title,
		true,
		"not interested: the tooltip over its card speaks for the journey that takes its place"
	)
	-- Closing the map fires no OnLeave: the card's tooltip goes with the panel, and a rebuild while the map is closed
	-- leaves it gone. Another addon's tooltip stays.
	h.map:SetShown(not h.map:IsShown())
	equal(h.G.GameTooltip:IsShown(), false, "closing the map: the hovered card's tooltip goes with it")
	ns.Unskip(gone.key)
	ns.Choose(story.key)
	h.flush()
	equal(h.G.GameTooltip:IsShown(), false, "closing the map: a rebuild does not bring the card's tooltip back")
	h.map:SetShown(not h.map:IsShown())
	h.flush()
	h.G.GameTooltip:SetOwner(h.G.UIParent, "ANCHOR_CURSOR")
	h.G.GameTooltip:Show()
	h.map:SetShown(not h.map:IsShown())
	equal(h.G.GameTooltip:IsShown(), true, "closing the map: another addon's tooltip stays")
	h.G.GameTooltip:Hide()
	h.map:SetShown(not h.map:IsShown())
	h.flush()
	clean(h, "not interested")
	-- After a /reload, Show again still chooses the journey the Not interested ended.
	h.menu = nil
	h.Click(Card("story"), "RightButton")
	h.menu.entries[2].onClick()
	h.flush()
	local saved = h.G.AdventureGuideForeverCharDB
	equal(saved.journey, nil, "not interested: the choice ends before the /reload")
	local reloaded = Load(false, nil, saved)
	reloaded.ns.Unskip(story.key)
	reloaded.flush()
	equal(reloaded.ns.Prefs().journey, story.key, "not interested: Show again after a /reload chooses it again")
	clean(reloaded, "not interested: reloaded")
end
-- A skipped step the route no longer has (the quest turned in anyway) leaves Skipped (n); one it still has stays.
do
	local completed = { 844 }
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	local h = harness.load({ planned = true, completed = completed, log = log })
	local ns = h.ns
	h.flush()
	-- A town's step stays while the town offers anything, so the gone step here is the objective's.
	ns.Skip("area:843:0", "Gann's Reclamation")
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
	equal(ns.Prefs().skipped["area:843:0"], nil, "skipped, pruned: and is no longer skipped")
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
	local expected = { "1 to hand in, 4 to pick up", "Opens the next chapter here" }
	for _, giver in ipairs(steps[1].checklist) do
		expected[#expected + 1] = giver.text
	end
	expected[#expected + 1] = spf and "About 6 min away" or nil
	expected[#expected + 1] = "Next: " .. steps[2].title .. " (no dash)"
	local lines, block = TrackerLines(h)
	equal(block.header, steps[1].title, label .. ": step 1's title heads the block")
	same(lines, expected, label .. ": a town's counts, its reason, travel, next")
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

-- New Forever turn-ins without a provider record still show the client's level and difficulty.
do
	local h = Load(false)
	h.G.C_QuestLog.GetQuestDifficultyLevel = function(id)
		return id == 99158 and 8 or nil
	end
	h.ns.State.QuestTitle = function(id)
		return id == 99158 and "Dawn in the Mountains" or nil
	end
	h.G.GameTooltip:SetOwner(h.G.UIParent, "ANCHOR_CURSOR")
	h.ns.Pins.StepTooltip(
		h.G.GameTooltip,
		{ kind = "turnin", title = "Turn in: Dawn in the Mountains", reason = "ready to hand in", quests = { 99158 } },
		3
	)
	equal(h.tooltip[3], "colored: |A:questturnin:14:14|a [8] Dawn in the Mountains", "new quest turn-in level")
	local color = h.G.GetQuestDifficultyColor(8)
	same(h.tooltipColors[3], { color.r, color.g, color.b }, "new quest turn-in difficulty")
end

-- A town's tooltip, from its row and its ring alike: after the reason, each NPC and its quests, hand-ins
-- first, each coloured by the stock difficulty colour, 8 at most and the rest counted; the click line stays last.
do
	local h = Load(false, PINS_ON)
	local ns = h.ns
	-- Egg Hunt at 20, two over the player: yellow, so offered (at 22 it is orange and never is), a ninth to count.
	ns.Data.quests[868].level = 20
	-- Their work a step from town and alike in XP, so the lap keeps all of them (one worth less per yard waits).
	for _, quest in pairs(ns.Data.quests) do
		if quest.start and quest.start.hub == 376 then
			quest.xp = 1000
			if quest.obj then
				quest.need, quest.obj = { [4] = 1 }, { { 4, 530, 310, 20 } }
			end
		end
	end
	ns.Prefs().journey = ns.Route().journeys[1].key
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
	equal(lines[1], "title: 1. Visit Crossroads, The Barrens: Pick up 8, turn in 1", "hub tooltip: the numbered town")
	equal(lines[2], "highlight: " .. step.reason, "hub tooltip: the reason")
	equal(lines[3], "normal: Sergra Darkthorn", "hub tooltip: the hand-in's NPC first")
	equal(lines[4], "colored: |A:questturnin:14:14|a [13] The Zhevra", "hub tooltip: a hand-in has the turn-in mark")
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
	equal(npcs, 6, "hub tooltip: one line per NPC shown")
	equal(lines[#lines - 2], "highlight: And 1 more", "hub tooltip: the rest counted")
	equal(lines[#lines - 1], "instruction: " .. ns.L.ORDER_DRAG, "hub tooltip: then how to reorder")
	equal(lines[#lines], "instruction: " .. ns.L.SPF_MISSING, "hub tooltip: then the Shortest Path hint")
	same(colors[11], { 1, 1, 0 }, "hub tooltip: a quest 2 over the player is yellow")

	-- The ring's tooltip lists the same, then the click line.
	h.providers[1]:RefreshAllData()
	local ring = h.pins.AdventureGuideForeverPinTemplate[1]
	equal(ring.step.key, step.key, "hub tooltip: ring 1 is the town")
	h.Hover(ring)
	-- The route comes back to Crossroads to hand in, so the ring names its two visits after the quest list.
	local last, visits = #h.tooltip, 0
	for index = last - 1, 1, -1 do
		if h.tooltip[index]:find("^normal: Stop ") then
			visits = visits + 1
		else
			break
		end
	end
	equal(visits >= 1, true, "hub tooltip: the ring's visits")
	equal(h.tooltip[last - visits - 1], "highlight: And 1 more", "hub tooltip: the ring's quests")
	equal(h.tooltip[last], "instruction: Click to set a waypoint", "hub tooltip: the click line last")

	-- A group quest carries the quest log's group tag.
	ns.Data.quests[step.quests[1]].elite = true
	h.Hover(rows[1])
	equal(
		h.tooltip[4],
		"colored: |A:questturnin:14:14|a [13] The Zhevra |A:questlog-questtypeicon-group:12:12|a",
		"hub tooltip: group"
	)
	ns.Data.quests[step.quests[1]].elite = nil
	clean(h, "hub tooltip")
end

-- A town is titled by its name, so step 1 of the story (Crossroads) shows its counts, then its reason in
-- place of the NPC line, since the story begins there. With a reason that is only the counts, the line
-- names its NPCs: two, then how many more. One quest's stop reads "NPC, zone".
do
	local h = Load(false)
	local ns = h.ns
	ns.Prefs().journey = ns.Route().journeys[1].key
	ns.Invalidate()
	h.flush()
	local steps = ns.Route().steps
	local step = steps[1]
	equal(step.title, "Visit Crossroads, The Barrens: Pick up 4, turn in 1", "tracker, town: town and actions")
	equal(step.detail, "1 to hand in, 4 to pick up", "tracker, town: the hand-in joins the pickups")
	local expected = { step.detail, "Opens the next chapter here" }
	for _, giver in ipairs(step.checklist) do
		expected[#expected + 1] = giver.text
	end
	expected[#expected + 1] = "Next: " .. steps[2].title .. " (no dash)"
	same(TrackerLines(h), expected, "tracker, town: counts, reason, checklist and next")

	step.reason = step.detail
	h.tracker:MarkDirty()
	local detailed = { step.detail }
	for _, giver in ipairs(step.checklist) do
		detailed[#detailed + 1] = giver.text
	end
	detailed[#detailed + 1] = "Next: " .. steps[2].title .. " (no dash)"
	same(TrackerLines(h), detailed, "tracker, town: checklist suppresses duplicate giver summary")
	step.givers = { "Sergra Darkthorn", "Gazrog" }
	h.tracker:MarkDirty()
	same(TrackerLines(h), detailed, "tracker, town: givers do not duplicate checklist")

	-- A town with one quest: its NPC and zone, since its title names only the NPC. The towns before it are skipped.
	for _ = 1, 6 do
		step = ns.Route().steps[1]
		if step.kind == "town" and #step.quests == 1 then
			break
		end
		ns.Skip(step.key, step.title)
		h.flush()
	end
	step = ns.Route().steps[1]
	local npc = step.kind == "town" and #step.quests == 1 and step.spots[step.quests[1]].name
	equal(step.title:find("^Pick up: ") ~= nil, true, "tracker: pickup title names its action")
	equal(npc ~= nil, true, "tracker, one quest: a town of one leads, " .. step.title)
	equal(TrackerLines(h)[1], npc .. ", The Barrens", "tracker, one quest: NPC, zone")
	clean(h, "tracker, town")
end

-- F8, the resume line: a login shows "Where you left off" once, when last session's step 1 is still step 1; a
-- /reload, a stale key or a route change shows none. The step shows only once a journey is chosen, so each has one.
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
	equal(saved and saved.key, "town:376", "resume: each rebuild saves step 1")
	equal(Resumed(session), 0, "resume: nothing saved, nothing to resume")
	local function Login(options)
		options.charDB = { journey = "zone:1413", last = { key = saved.key, reason = "finishes a story" } }
		options.completed = { 844 }
		options.log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		}
		return harness.load(options)
	end
	local h = Login({})
	equal(Resumed(h), 1, "resume: a login with a matching key shows the line")
	equal(TrackerLines(h)[2], "Where you left off: finishes a story", "resume: in place of the reason, after the town")
	local capital = harness.load({
		planned = true,
		charDB = { journey = "zone:1413", last = { key = saved.key, reason = "Continues a story you started" } },
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
	saved.key = "town:0"
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
	same(h.sounds, { h.G.SOUNDKIT.UI_SCENARIO_STAGE_END }, "fanfare: a proven story end plays its sound")
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
	same(h.tracker.layoutOrder, { "journey", ns.Route().steps[1].key }, "fanfare: gone once step 1 moves on")
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
	for index, line in ipairs({ L.HELP_OPEN, L.HELP_AUDIT, L.HELP_DUMP, L.HELP_TRACKER }) do
		equal(h.prints[before + index]:sub(-#line), line, "L: help line " .. index)
	end
	equal(#h.prints, before + 4, "L: four help lines")
	-- Map names come from the client (C_Map.GetMapInfo), which the planner prefers over the data's English.
	h.G.C_Map.GetMapInfo = function()
		return { name = "Client Stormwind" }
	end
	equal(h.ns.State.MapName(1453), "Client Stormwind", "L: the client's map name")
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
	local kept = { planned = true, db = h.G.AdventureGuideForeverDB, initialLogin = false }
	local dropped = { planned = true, db = h.G.AdventureGuideForeverDB, initialLogin = true }
	equal(harness.load(kept).G.AdventureGuideForeverDB.dump, dump, "dump: kept by /reload")
	equal(harness.load(dropped).G.AdventureGuideForeverDB.dump, nil, "dump: dropped at login")
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

-- The guide (F2): seven cards in this fixture. The chosen one is lit, never moved, 288x86 with a 46x46 ring
-- and followed by its steps; the others sit above it as one-line 288x26 header rows with a 16x16 icon and no ring, in
-- the dumped layout the client's own dump is compared with.
do
	local h = Load(false, nil, nil, true)
	h.ns.OpenPanel()
	h.flush()
	local route, full, compact, lit = h.ns.Route(), 0, 0, 0
	local sizes = {}
	for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
		if entry.path:match("%.Button%[%d+%]$") and entry.size and entry.size[1] == 288 then
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
	equal(#route.journeys, 7, "guide: all seven eligible journeys survive")
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
	equal(Says(h, h.ns.L.NO_JOURNEY), 0, "guide: no empty line beside the cards")

	-- F4: the chosen story shows its chapter track, one square per proven chapter, and never a later chapter's title.
	local story = route.journeys[1]
	h.ns.Prefs().journey = story.key
	h.ns.Invalidate()
	h.flush()
	local chain, squares, texts = story.story, {}, {}
	equal(chain and chain.total, 8, "story: the fixture's chain is proven at 8")
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
	-- Call of Air - Guse's Fleet (6825) has no start in the data.
	assert(h.ns.Data.quests[6825].title == "Call of Air - Guse's Fleet" and not h.ns.Data.quests[6825].start)
	h.Type(search, "Call of Air - Guse's Fleet")
	local suppressed
	for _, row in ipairs(Results()) do
		local first = row.Title:GetText() == "Call of Air - Guse's Fleet" and Lines(row)[1]
		suppressed = suppressed or (first == h.ns.L.WHY_NO_START and row) or nil
	end
	h.Type(search, "Call of")
	local found, open = Results(), nil
	for _, row in ipairs(found) do
		open = open or (not row.Lock:IsShown() and row) or nil
	end
	equal(#found, 10, "search: ten results at most")
	equal(Says(h, story.title), 0, "search: the cards step aside")
	equal(#Shown(h, function(frame)
		return frame.SkipButton ~= nil
	end), 0, "search: and their steps")
	h.Type(search, "Call of Air - Guse's Fleet")
	local lines = Lines(assert(suppressed, "search: Call of Air - Guse's Fleet, whose start the data suppresses"))
	equal(#lines, 1, "search: a suppressed start shows exactly 1 line")
	equal(lines[1], h.ns.L.WHY_NO_START, "search: saying the guide can't tell where it starts")
	equal(suppressed.Lock:IsShown(), true, "search: behind a lock")
	h.Hover(suppressed)
	equal(
		table.concat(h.tooltip, "\n"),
		"title: Call of Air - Guse's Fleet\nerror: " .. h.ns.L.WHY_NO_START,
		"search: tooltip"
	)
	h.Type(search, "Call of")
	equal(#Lines(assert(open, "search: a quest open now")), 0, "search: an open quest has nothing to explain")
	-- A shift-click adds an open quest to the route (design §2.18), starred; a second takes it off. A plain click, or a
	-- locked quest's, adds nothing.
	local openID = open.id
	local function Row()
		for _, row in ipairs(Results()) do
			if row.id == openID then
				return row
			end
		end
	end
	local function ShiftUp(row, shift)
		h.shift = shift
		h.call(row.scripts.OnMouseUp, row, "LeftButton")
		h.shift = false
		h.flush()
	end
	h.Hover(open)
	equal(
		h.tooltip[#h.tooltip],
		"instruction: " .. h.ns.L.SHIFT_ADD,
		"search: an open quest's tooltip offers to add it"
	)
	equal(open.Star:IsShown(), false, "search: no star yet")
	ShiftUp(open, false)
	equal(h.ns.Pinned({ openID }), false, "search: a plain click adds nothing")
	ShiftUp(open, true)
	equal(h.ns.Pinned({ openID }), true, "search: a shift-click adds it")
	equal(Row().Star:IsShown(), true, "search: starred")
	h.Hover(Row())
	equal(h.tooltip[#h.tooltip], "instruction: " .. h.ns.L.SHIFT_REMOVE, "search: then offers to take it off")
	ShiftUp(Row(), true)
	equal(next(h.ns.Prefs().pinned), nil, "search: a second takes it off")
	equal(Row().Star:IsShown(), false, "search: unstarred")
	h.Type(search, "Call of Air - Guse's Fleet")
	ShiftUp(suppressed, true)
	equal(next(h.ns.Prefs().pinned), nil, "search: a locked quest is never added")
	-- Nor an orange or red one open now, which no route takes: no shift-click line, and a shift-click adds nothing.
	local player, hardID = h.ns.State.Player(), nil
	for id, quest in pairs(h.ns.Data.quests) do
		if
			(hardID == nil or id < hardID)
			and h.ns.Model.Hard(quest, player)
			and h.ns.Model.Eligible(h.ns.Data, player, h.ns.State.Completed(), h.ns.State.Log(), id)
			and #h.ns.Model.Search(h.ns.Data, player, quest.title) == 1
		then
			hardID = id
		end
	end
	h.Type(search, h.ns.Data.quests[assert(hardID, "search: an orange quest open now")].title)
	local hard = Results()[1]
	equal(#Lines(hard), 0, "search: an orange quest is open")
	h.Hover(hard)
	equal(h.tooltip[#h.tooltip]:find("^instruction: "), nil, "search: an orange quest offers no shift-click")
	ShiftUp(hard, true)
	equal(next(h.ns.Prefs().pinned), nil, "search: nor is it added")
	h.Type(search, "Call of")
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

	-- Past the cap with quests and dungeons off, the dungeon card and a way into an instance still show.
	local capped = harness.load({ planned = true, player = { level = 70 } })
	capped.ns.Prefs().quests = false
	capped.ns.Invalidate()
	capped.ns.OpenPanel()
	capped.flush()
	equal(#capped.ns.Route().journeys, 2, "guide: at the cap, never nothing")
	equal(Says(capped, "Blackrock Spire"), 1, "guide: the dungeon card, toggle off")
	equal(Says(capped, capped.ns.L.JOURNEY_INTO:format("Scholomance")), 1, "guide: the way in, as a story")
	equal(Says(capped, capped.ns.L.NO_JOURNEY), 0, "guide: no empty line")
	clean(capped, "guide: at the cap")

	local none = harness.load({ planned = true, player = { level = 1 } })
	none.ns.Prefs().quests = false
	none.ns.Invalidate()
	none.ns.OpenPanel()
	none.flush()
	equal(#none.ns.Route().journeys, 0, "guide: nothing fits")
	equal(Says(none, none.ns.L.NO_JOURNEY), 1, "guide: says so, and where to look")
	clean(none, "guide: empty")
end

-- F3, select: with the setting that starts the route off, choosing a journey starts nothing; it turns the map to the
-- journey and its rings preview it while the guide is open, even with map pins off. Closing the guide takes them away.
for _, spf in ipairs({ false, "v1" }) do
	local label = "select: " .. (spf or "no Shortest Path")
	local h = Load(spf, { titleStartsRoute = false }, nil, true)
	h.ns.OpenPanel()
	h.flush()
	local function Cards()
		return Shown(h, function(frame)
			return frame.IconFrame ~= nil and frame.journey ~= nil
		end)
	end
	equal(#Cards(), #h.ns.Route().journeys, label .. ": every eligible card")
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
		-- A place the route comes back to keeps its first visit's ring: a town by its hub, anything else by its point.
		local seen = {}
		for _, step in ipairs(route.steps) do
			local place = (step.kind == "town" and step.hub) and step.hub or (step.x .. ":" .. step.y)
			if step.map == journey.map and not seen[place] then
				expected[#expected + 1], seen[place] = step.key, true
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

-- None chosen (docs/design.md §2.2): a fresh character sees compact full-width journey rows,
-- no route rows, and nothing guides until asked; the tracker
-- shows the first card's step (design §2.5). A click on any card chooses it and starts its route: the others fold into
-- one-line rows above it, each keeping its lines in a tooltip, and it sits lit over its steps; a row chooses its card
-- and starts its route in its place. The chosen card is no toggle: the header's back arrow, shown only while a card is
-- chosen, goes back to the overview and stops the route it started, as a right-click on the header does.
for _, spf in ipairs({ false, "v1" }) do
	local label = "none chosen: " .. (spf or "no Shortest Path")
	local h = Load(spf, nil, false, true)
	h.ns.OpenPanel()
	h.flush()
	local route = h.ns.Route()
	local L = h.ns.L
	-- The chosen view's cards, top to bottom as laid out, not in pool order.
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
	-- The overview's cards in reading order.
	local function Overview()
		local shown = Shown(h, function(frame)
			return frame.Icon ~= nil and frame.Icon.Clip ~= nil and frame.journey ~= nil
		end)
		local function Place(card)
			local _, _, _, x, y = card:GetPoint(1)
			return -y * 1000 + x
		end
		table.sort(shown, function(a, b)
			return Place(a) < Place(b)
		end)
		return shown
	end
	local function Rows()
		return #Shown(h, function(frame)
			return frame.SkipButton ~= nil
		end)
	end
	local function Previews()
		local lines = {}
		for _, row in
			ipairs(Shown(h, function(frame)
				return frame.Ring ~= nil and frame.SkipButton == nil and frame.step ~= nil
			end))
		do
			lines[row.index] = row.Title:GetText()
		end
		return table.concat(lines, "|")
	end
	-- The dump holds only what is shown.
	local function Says(text)
		local count = 0
		for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
			count = count + (entry.text == text and 1 or 0)
		end
		return count
	end
	-- Every start: Shortest Path's routes, or the native waypoints without it.
	local function Starts()
		return h.spf and h.spf.NavigateRoute or h.counts.SetUserWaypoint
	end
	local function Stops()
		return h.spf and h.spf.Cancel or h.counts.ClearUserWaypoint
	end
	local function Back()
		return Shown(h, function(frame)
			return frame.normalAtlas == "common-icon-backarrow"
		end)[1]
	end
	equal(route.chosen, false, label .. ": nothing chosen")
	equal(Back(), nil, label .. ": no back arrow with nothing chosen")
	equal(route.journey, "zone:1413", label .. ": the route falls back to the first card")
	same(h.tracker.layoutOrder, { "journey", route.steps[1].key }, label .. ": the tracker shows the first card's step")
	equal(route.journeys[1].kind, "story", label .. ": a story card")
	equal(#route.journeys >= 3, true, label .. ": several journey rows")
	equal(Heights(), "", label .. ": none of the chosen view's cards")
	local cards = Overview()
	equal(#cards, #route.journeys, label .. ": every card in the overview")
	for index, card in ipairs(cards) do
		equal(card.journey, route.journeys[index], label .. ": in the route's order")
		equal(card.state, "shown", label .. ": none chosen or folded")
		equal(card.highlightLocked == true, false, label .. ": no card lit")
	end
	local first = cards[1]
	equal(first:GetHeight(), 64, label .. ": compact first row")
	equal(cards[2]:GetHeight(), 64, label .. ": matching journey rows")
	equal(cards[2]:GetWidth(), first:GetWidth(), label .. ": full width")
	equal(select(5, cards[2]:GetPoint(1)) > select(5, cards[3]:GetPoint(1)), true, label .. ": one column")
	equal(Previews(), "", label .. ": no steps before choosing")
	equal(Rows(), 0, label .. ": and no route rows")
	equal(Says("Steps: 0"), 0, label .. ": and no step counter (docs/design.md §1)")
	equal(
		Says(L.OVERVIEW_WHERE:format("The Barrens", h.player.level)),
		1,
		label .. ": where the player is, by the title"
	)
	equal(Starts(), 0, label .. ": nothing guides")
	local story = first.journey
	equal(story.ready, 1, label .. ": the story holds a ready quest")
	-- Detail, then the progress, level or stop count on a compact third line.
	local function Hub(journey)
		local more = journey.more
		return (more > 1 and L.HUB_MORE:format(journey.hub, more))
			or (more == 1 and L.HUB_MORE_ONE:format(journey.hub))
			or journey.hub
	end
	equal(first.Reason:GetText(), story.reason or Hub(story), label .. ": the first row's reason")
	local zones, carried = 0, 0
	for index = 2, #cards do
		local card, journey = cards[index], cards[index].journey
		local foot = card.Foot:GetText()
		if journey.kind == "carry" then
			carried = carried + 1
			local total = journey.ready + journey.underway
			equal(foot, L.READY_OF:format(journey.ready, total), label .. ": Quests in your log counts what is ready")
			equal(card.Bar:IsShown(), journey.ready > 0, label .. ": and its bar")
			equal(card.Bar.Fill:GetWidth() > 0, true, label .. ": never empty")
		elseif journey.kind == "nextzone" then
			zones = zones + 1
			equal(foot, h.ns.Overview.Stops(journey), label .. ": " .. journey.key .. " current stops")
			equal(card.Bar:IsShown(), false, label .. ": " .. journey.key .. " no bar")
		end
		local reason = journey.reason ~= foot and journey.reason or nil
		equal(card.Reason:GetText(), reason or Hub(journey), label .. ": " .. journey.key .. " reason")
	end
	equal(carried, 1, label .. ": the Quests in your log card")
	equal(zones > 0, true, label .. ": a zone to head to")
	local longCard = cards[2]
	local title = longCard.journey.title
	longCard.journey.title = "Head to Stonetalon Mountains"
	h.ns.OpenPanel()
	equal(longCard.Title:GetNumLines(), 1, label .. ": a long title stays on one line")
	equal(longCard.Title.wordWrap, false, label .. ": titles never wrap")
	equal(longCard.Title.maxLines, 1, label .. ": titles have one line")
	equal(longCard.Reason.wordWrap, false, label .. ": details never wrap")
	equal(longCard.Reason.maxLines, 1, label .. ": details have one line")
	longCard.journey.title = title
	h.ns.OpenPanel()
	-- The zone icons: the zone's art cut round by the circle mask in a clipping frame, the ring over it and the kind
	-- as a badge; built once, not on every refresh; the plain ring where the data has no art.
	local icon = first.Icon
	equal(icon.Clip:IsShown(), true, label .. ": the story's zone art")
	equal(icon.Clip.clipsChildren, true, label .. ": clipped")
	equal(icon.Art.Mask:GetAtlas(), "CircleMaskScalable", label .. ": round")
	local tiles = 0
	for _, pool in ipairs({ icon.Art.base, icon.Art.overlays }) do
		for _, texture in ipairs(pool) do
			if texture:IsShown() then
				tiles = tiles + 1
				equal(texture.masks[1], icon.Art.Mask, label .. ": every tile masked")
			end
		end
	end
	equal(tiles > 1 and #icon.Art.overlays > 0, true, label .. ": base tiles and overlays")
	equal(icon.Ring:GetAtlas(), "adventureguide-ring", label .. ": in the ring")
	equal(icon.Kind:GetAtlas(), "questlog-questtypeicon-story", label .. ": the kind as a badge")
	local sets = 0
	for _, texture in ipairs(icon.Art.base) do
		local set = texture.SetTexture
		texture.SetTexture = function(...)
			sets = sets + 1
			return set(...)
		end
	end
	h.ns.OpenPanel()
	h.ns.Invalidate()
	h.flush()
	equal(sets, 0, label .. ": the art builds once")
	local art = h.ns.Data.zoneArt
	h.ns.Data.zoneArt = {}
	h.ns.OpenPanel()
	equal(icon.Clip:IsShown(), false, label .. ": no art in the data, no art drawn")
	equal(select(4, icon.Kind:GetPoint(1)), 0, label .. ": the kind centred in the plain ring") -- multi-value: x
	h.ns.Data.zoneArt = art
	h.ns.OpenPanel()
	equal(icon.Clip:IsShown(), true, label .. ": and back")
	-- An overview card's tooltip: its lines, the hub line when line 2 holds the reason, and what a click
	-- does.
	for _, card in ipairs(Overview()) do
		local journey = card.journey
		h.Hover(card)
		local expected = { "title: " .. journey.title, "normal: " .. journey.subline }
		if journey.reason then
			expected[#expected + 1] = "highlight: " .. journey.reason
		end
		if journey.reason or card.detail == Hub(journey) then
			expected[#expected + 1] = "highlight: " .. Hub(journey)
		end
		local travel = h.ns.Integrations.CardTravel(journey)
		equal(travel ~= nil and travel.line ~= nil, spf ~= false, label .. ": " .. journey.key .. "'s travel is cached")
		if travel and travel.line then
			expected[#expected + 1] = "highlight: " .. travel.line
		end
		if journey.kind == "carry" then
			expected[#expected + 1] = "normal: " .. L.CARRY_EXPLANATION
		end
		if (journey.group or 0) > 0 then
			expected[#expected + 1] = "highlight: "
				.. (journey.group == 1 and L.GROUP_ONE or L.GROUP_MANY:format(journey.group))
		end
		expected[#expected + 1] = "instruction: " .. L.CLICK_TO_CHOOSE
		expected[#expected + 1] = journey.kind ~= "carry" and "instruction: " .. L.RIGHT_CLICK_NOT_INTERESTED or nil
		same(h.tooltip, expected, label .. ": " .. journey.key .. "'s tooltip")
	end

	-- The first row chooses itself; its steps lead and alternatives fold below.
	h.Click(Overview()[1])
	equal(Starts(), 0, label .. ": the route waits for the rebuild with its steps")
	h.flush()
	equal(h.ns.Route().journey, story.key, label .. ": a click chooses")
	equal(Starts(), 1, label .. ": and starts its route")
	equal(h.ns.Guidance.Owns(), true, label .. ": ours, which Stop ends")
	equal(h.G.AdventureGuideForeverCharDB.journey, story.key, label .. ": and is saved")
	equal(#Overview(), 0, label .. ": the overview gives way")
	equal(Previews(), "", label .. ": with its steps")
	equal(Says(L.OVERVIEW_WHERE:format("The Barrens", h.player.level)), 0, label .. ": and the line by the title")
	equal(Heights(), "86 26 26 26 26 26 26", label .. ": the chosen route precedes alternatives")
	equal(Cards()[1].journey.key, story.key, label .. ": the chosen card first, over its steps")
	-- The chosen card is lit, not pressed: its art, pressed or not, is the card's own, so nothing moves.
	local chosenCard = Cards()[1]
	equal(chosenCard.highlightLocked, true, label .. ": the chosen card stays lit")
	equal(chosenCard.NormalTexture:GetAtlas(), "ui-journeys-renown-button", label .. ": in its own art")
	equal(chosenCard.PushedTexture:GetAtlas(), "ui-journeys-renown-button", label .. ": a press moves nothing")
	equal(Cards()[2].PushedTexture:GetAtlas(), Cards()[2].NormalTexture:GetAtlas(), label .. ": nor on a row")
	equal(Rows(), #h.ns.Route().steps, label .. ": its steps listed")
	local nextZone
	for _, card in ipairs(Cards()) do
		nextZone = nextZone or (card.journey.kind == "nextzone" and card or nil)
	end
	h.Hover(nextZone)
	local tip = table.concat(h.tooltip, "\n")
	equal(tip:find(nextZone.journey.title, 1, true) ~= nil, true, label .. ": the row's tooltip has its title")
	equal(tip:find(nextZone.journey.subline, 1, true) ~= nil, true, label .. ": its subline")
	if nextZone.journey.reason then
		equal(tip:find(nextZone.journey.reason, 1, true) ~= nil, true, label .. ": and its reason")
	end
	equal(tip:find(Hub(nextZone.journey), 1, true) ~= nil, true, label .. ": the hub line it no longer shows")
	equal(tip:find(L.CLICK_TO_CHOOSE, 1, true) ~= nil, true, label .. ": and what a click does")
	h.Hover(chosenCard)
	tip = table.concat(h.tooltip, "\n")
	equal(tip:find(L.BACK_TO_ALL, 1, true) ~= nil, true, label .. ": the chosen card points to the back arrow")
	local back = Back()
	equal(back ~= nil, true, label .. ": the back arrow shows while a card is chosen")
	h.Hover(back)
	same(
		h.tooltip,
		{ "title: " .. L.ALL_SUGGESTIONS, "normal: " .. L.BACK_STOPS_ROUTE },
		label .. ": its tooltip, and that it stops our route"
	)

	-- A row chooses its card; the one chosen before folds in its place.
	local key = nextZone.journey.key
	h.Click(nextZone)
	h.flush()
	equal(h.ns.Route().journey, key, label .. ": a row chooses its card")
	equal(Starts(), 2, label .. ": and starts its route in place of the first")
	equal(Heights(), "86 26 26 26 26 26 26", label .. ": still one whole card")
	equal(Cards()[1].journey.key, key, label .. ": the new choice over the steps")

	-- The chosen card again: nothing changes but the map, which turns to it.
	local maps, stops = h.counts.SetMapID, Stops()
	h.Click(Cards()[1])
	h.flush()
	equal(h.ns.Route().journey, key, label .. ": clicking the chosen card keeps it")
	equal(Stops(), stops, label .. ": and stops nothing")
	equal(h.ns.Guidance.Owns(), true, label .. ": so the route runs on")
	equal(Starts(), 2, label .. ": without starting again")
	equal(h.counts.SetMapID, maps + 1, label .. ": the map turns to it")

	-- The back arrow: none chosen, the overview again, and the map stays where it was.
	maps = h.counts.SetMapID
	h.Click(Back())
	h.flush()
	equal(Stops() - stops, 1, label .. ": going back stops our route")
	equal(h.ns.Guidance.Owns(), false, label .. ": so nothing of ours guides")
	equal(Starts(), 2, label .. ": and nothing new starts")
	equal(h.ns.Route().chosen, false, label .. ": the back arrow chooses none")
	equal(h.G.AdventureGuideForeverCharDB.journey, nil, label .. ": and saves none")
	equal(h.counts.SetMapID, maps, label .. ": without turning the map")
	equal(Heights(), "", label .. ": the overview again")
	equal(#Overview(), #h.ns.Route().journeys, label .. ": every card")
	equal(Overview()[1].journey.key, h.ns.Route().journeys[1].key, label .. ": in order")
	equal(Previews(), "", label .. ": no steps until choosing again")
	equal(Rows(), 0, label .. ": with no route rows")
	equal(Back(), nil, label .. ": and the back arrow goes")

	-- Another row chooses itself, lit over its own steps; back returns to the overview.
	local second = Overview()[2].journey
	h.Click(Overview()[2])
	h.flush()
	equal(h.ns.Route().chosen and h.ns.Route().journey, second.key, label .. ": a row chooses it")
	equal(Heights(), "86 26 26 26 26 26 26", label .. ": alternatives fold below it")
	equal(Cards()[1].journey.key, second.key, label .. ": lit over its steps")
	equal(Rows(), #h.ns.Route().steps, label .. ": which are listed")
	h.Click(Back())
	h.flush()
	equal(h.ns.Route().chosen, false, label .. ": and back again")
	equal(#Overview(), #h.ns.Route().journeys, label .. ": to the overview")

	-- A right-click on the header goes back too, and does nothing with none chosen.
	local header = back:GetParent()
	h.call(header.scripts.OnMouseUp, header, "RightButton")
	equal(h.ns.Route().chosen, false, label .. ": a right-click on the header with none chosen does nothing")
	h.Click(Overview()[1])
	h.flush()
	equal(h.ns.Route().chosen, true, label .. ": chosen again")
	h.call(header.scripts.OnMouseUp, header, "LeftButton")
	equal(h.ns.Route().chosen, true, label .. ": a left-click on the header keeps it")
	h.call(header.scripts.OnMouseUp, header, "RightButton")
	h.flush()
	equal(h.ns.Route().chosen, false, label .. ": a right-click on the header goes back")
	equal(Back(), nil, label .. ": its arrow gone")
	clean(h, label)
end

-- Card minutes: while the guide is open, one Shortest Path estimate a frame over the shown cards,
-- none in the rebuild's frame, none in step 1's travel frame beyond its own, none in combat (the last answers stand),
-- none with the guide closed and none without Shortest Path. A boat names itself where the subline leaves room.
for _, spf in ipairs({ false, "v1", "v1+" }) do
	local label = "card minutes: " .. (spf or "no Shortest Path")
	local h = Load(spf, nil, false, true)
	h.ns.OpenPanel()
	h.flush()
	local integrations, L = h.ns.Integrations, h.ns.L
	local function Calls()
		return h.spf and h.spf.Estimate + (h.spf.EstimateDetail or 0) or 0
	end
	local function Cached()
		local count = 0
		for _, journey in ipairs(h.ns.Route().journeys) do
			local travel = integrations.CardTravel(journey)
			count = count + (travel and travel.minutes and 1 or 0)
		end
		return count
	end
	local function Cards()
		return Shown(h, function(frame)
			return frame.IconFrame ~= nil and frame.journey ~= nil
		end)
	end
	local journeys = h.ns.Route().journeys
	equal(Cached(), spf and #journeys or 0, label .. ": every card has its minutes on opening")
	-- A new route: the rebuild's frame asks nothing, step 1's frame asks for step 1 only, then a card a frame.
	integrations.RefreshCards({})
	h.ns.Invalidate()
	-- The full build is sliced across frames (Core.StepRebuild), so the rebuild spans several frames, each asking
	-- nothing; then one estimate a frame over step 1 and the cards. Structural, so the slice count is not pinned.
	local function Frames(what)
		local rebuildFrames, askingFrames = 0, 0
		for _ = 1, 40 do
			local frameCalls = Calls()
			local rebuilding = h.ns.Rebuilding()
			if h.tick() == 0 then
				break
			end
			local asked = Calls() - frameCalls
			if rebuilding then
				equal(asked, 0, label .. ": a rebuild frame asks nothing")
				rebuildFrames = rebuildFrames + 1
			else
				equal(asked, spf and 1 or 0, label .. what)
				askingFrames = askingFrames + 1
			end
		end
		return rebuildFrames, askingFrames
	end
	local rebuildFrames, askedAfter = Frames(": a travel or card frame asks once")
	equal(rebuildFrames >= 1, true, label .. ": the full build is sliced across the rebuild frames")
	if spf then
		equal(askedAfter, #journeys + 1, label .. ": one estimate a frame over step 1 and the cards")
	end
	equal(Cached(), spf and #journeys or 0, label .. ": each card answered")
	-- None chosen, the overview's cards leave them to their tooltips; chosen, the whole card shows them and a folded
	-- row keeps them for its tooltip.
	equal(#Cards(), 0, label .. ": the overview has no minutes")
	h.ns.Choose(journeys[1].key)
	h.flush()
	local shown = 0
	for _, card in ipairs(Cards()) do
		local travel = integrations.CardTravel(card.journey)
		shown = shown + (card.Travel:IsShown() and 1 or 0)
		if travel and card.state ~= "compact" then
			equal(card.Travel:GetText(), L.CARD_MINUTES:format(travel.minutes), label .. ": the card reads its minutes")
			local _, beside = card.Subline:GetPoint(2)
			equal(beside, card.Travel, label .. ": and the subline stops short of them")
		end
	end
	equal(shown, spf and 1 or 0, label .. ": minutes on the whole card with an answer")
	h.ns.Choose(nil)
	h.flush()
	-- Once the player moves, the next route asks again, so a card's minutes are never older than step 1's; standing
	-- still, it asks nothing new; and no empty answer sticks.
	if spf then
		h.spfSeconds = 120
		local still = Calls()
		h.ns.Invalidate()
		h.flush()
		equal(Calls() - still, 1, label .. ": standing still, only step 1 asks again")
		h.player.x = h.player.x + 0.01
		h.ns.Invalidate()
		h.flush()
		for _, journey in ipairs(h.ns.Route().journeys) do
			local travel = integrations.CardTravel(journey)
			equal(travel and travel.minutes, 2, label .. ": " .. journey.key .. " asks again once the player moves")
		end
		h.spfSeconds, h.player.x = 360, h.player.x - 0.01
		h.ns.Invalidate()
		h.flush()
	end
	if spf == "v1+" then
		h.spfLegs, h.player.x = false, h.player.x + 0.01
		h.ns.Invalidate()
		h.flush()
		equal(Cached(), 0, label .. ": no route, no minutes")
		h.spfLegs = nil
		h.ns.Invalidate()
		h.flush()
		equal(Cached(), #journeys, label .. ": an empty answer is asked again, standing still")
		h.player.x = h.player.x - 0.01
		h.ns.Invalidate()
		h.flush()
	end
	-- A queue emptied before its frame asks nothing.
	integrations.RefreshCards({})
	integrations.RefreshCards(journeys)
	integrations.RefreshCards({})
	local before = Calls()
	h.flush()
	equal(Calls() - before, 0, label .. ": an emptied queue asks nothing")
	integrations.RefreshCards(journeys)
	h.flush()
	-- In combat nothing is asked and the answers stand.
	h.SetCombat(true)
	integrations.RefreshCards(journeys)
	before = Calls()
	h.flush()
	equal(Calls() - before, 0, label .. ": none in combat")
	equal(Cached(), spf and #journeys or 0, label .. ": the last answers stand")
	h.SetCombat(false)
	h.flush()
	-- Cards still unanswered when a fight starts ask once it ends, with no rebuild to requeue them.
	integrations.RefreshCards({})
	integrations.RefreshCards(journeys)
	h.SetCombat(true)
	h.flush()
	equal(Cached(), 0, label .. ": unanswered through the fight")
	h.SetCombat(false)
	h.flush()
	equal(Cached(), spf and #journeys or 0, label .. ": answered once it ends")
	-- Closed, nothing is asked.
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	h.flush()
	integrations.RefreshCards({})
	integrations.RefreshCards(journeys)
	before = Calls()
	h.flush()
	equal(Calls() - before, 0, label .. ": none with the guide closed")
	-- A boat names itself where the subline leaves room; the card falls back to the minutes where it doesn't.
	if spf == "v1+" then
		h.spfLegs = {
			{ mode = "walk", to = "Ratchet", seconds = 60 },
			{ mode = "boat", to = "Booty Bay", seconds = 300 },
		}
		h.ns.OpenPanel()
		h.flush()
		-- Each card whole in turn, chosen: only the whole card shows its minutes.
		local boats = 0
		for _, journey in ipairs(journeys) do
			h.ns.Prefs().journey = journey.key
			h.ns.Invalidate()
			h.flush()
			for _, card in ipairs(Cards()) do
				if card.state ~= "compact" then
					local long = L.CARD_BY_BOAT:format(6)
					local fits = card.Subline:GetUnboundedStringWidth() + 6 + #long * 6 <= 212 - 8
					local minutes = fits and long or L.CARD_MINUTES:format(6)
					equal(card.Travel:GetText(), minutes, label .. ": " .. card.journey.key)
					boats = boats + (fits and 1 or 0)
				end
			end
		end
		h.ns.Prefs().journey = nil
		h.ns.Invalidate()
		h.flush()
		equal(boats > 0 and boats < #journeys, true, label .. ": a short subline names the boat, a long one doesn't")
	end
	-- Opened in a rebuild's frame, after it: step 1's travel frame is still its own, whatever order the frames run in.
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	h.flush()
	h.player.x = h.player.x + 0.01
	h.ns.Invalidate()
	h.tick()
	h.ns.OpenPanel()
	-- The build is sliced (Core.StepRebuild): the remaining slices ask nothing, then one estimate a frame.
	local _, cardFrames = Frames(": a card frame asks once")
	if spf then
		equal(cardFrames, #journeys + 1, label .. ": opened in the rebuild's frame, one estimate a frame")
	end
	clean(h, label)
end

-- The footer's Stop follows Shortest Path ending our journey, or the player clearing the waypoint, on the frame after
-- the super-tracking event (Shortest Path's own handler runs first); the guide closed, the ending is still judged.
for _, spf in ipairs({ false, "v1+" }) do
	local label = "footer events: " .. (spf or "no Shortest Path")
	local h = Load(spf)
	h.ns.OpenPanel()
	h.flush()
	local event = spf and "SUPER_TRACKING_CHANGED" or "USER_WAYPOINT_UPDATED"
	h.ns.Guidance.Navigate(h.ns.Route().steps[1])
	h.flush()
	equal(StopButton(h):IsShown(), true, label .. ": Stop while ours guides")
	if spf then
		h.G.ShortestPathForever.API.Cancel("AdventureGuideForever")
	else
		h.G.C_Map.ClearUserWaypoint()
	end
	h.fire(event)
	equal(StopButton(h):IsShown(), true, label .. ": not in the event's own frame")
	h.fire(event)
	equal(h.tick(), 1, label .. ": one redraw however many events")
	equal(StopButton(h):IsShown(), false, label .. ": Stop goes on the next frame")
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	h.flush()
	h.fire(event)
	equal(h.tick(), 1, label .. ": the ending is judged with the guide closed too, in one frame")
	clean(h, label)
end

-- A saved choice from before survives the update, and one whose card is gone reads as none chosen.
do
	local kept = Load(false, nil, { journey = "story:1413" })
	equal(kept.ns.Route().chosen, true, "saves: a saved card stays chosen")
	equal(kept.ns.Route().journey, "zone:1413", "saves: the same card, under the one key a zone's journey has")
	equal(Load(false, nil, { journey = "nextzone:1442" }).ns.Prefs().journey, "zone:1442", "saves: a next zone too")
	local gone = Load(false, nil, { journey = "dungeon:36" })
	equal(gone.ns.Route().chosen, false, "saves: a card no longer offered is none chosen")
	equal(gone.G.AdventureGuideForeverCharDB.journey, "dungeon:36", "saves: kept, should it come back")
	clean(kept, "saves: kept")
	clean(gone, "saves: gone")
end

-- A choice in combat, when Shortest Path refuses every route: the card is chosen at once and its route starts on the
-- rebuild combat's end brings, while the footer says it waits. A choice cleared before then starts nothing. With the
-- setting off a choice starts nothing, yet clearing it still stops what a Go started meanwhile: none chosen draws none.
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
			-- The overview's cards and the chosen view's alike.
			return (frame.IconFrame ~= nil or (frame.Icon ~= nil and frame.Icon.Clip ~= nil)) and frame.state == state
		end)[1]
	end
	local function Back()
		h.Click(Shown(h, function(frame)
			return frame.normalAtlas == "common-icon-backarrow"
		end)[1])
	end
	equal(Queued(), 0, label .. ": nothing waits")
	h.SetCombat(true)
	local card = Card("shown")
	h.Click(card)
	h.flush()
	equal(h.ns.Route().journey, card.journey.key, label .. ": the card is chosen at once")
	equal(Starts(), 0, label .. ": its route waits for combat's end")
	equal(Queued(), 1, label .. ": which the footer says")
	equal(h.ns.Guidance.Status(), "queued", label .. ": as Guidance does")
	h.SetCombat(false)
	h.flush()
	equal(Starts(), 1, label .. ": the route starts when combat ends")
	equal(Queued(), 0, label .. ": and the footer stops waiting")
	equal(h.ns.Guidance.Status(), nil, label .. ": a running route has no status to tell")
	equal(h.ns.Prefs().guided, card.journey.key, label .. ": recorded as the chosen journey's route")

	h.SetCombat(true)
	h.Click(Card("compact"))
	h.flush()
	Back()
	h.flush()
	h.SetCombat(false)
	h.flush()
	equal(Starts(), 1, label .. ": a choice cleared in combat starts nothing")
	equal(Queued(), 0, label .. ": nor waits")
	equal(h.ns.Prefs().guided, nil, label .. ": and no route is recorded")

	h.ns.SetSetting("titleStartsRoute", false)
	h.Click(Card("shown"))
	h.flush()
	equal(Starts(), 1, label .. ": with the setting off a choice only chooses")
	h.ns.Guidance.Navigate(h.ns.Route().steps[1])
	Back()
	h.flush()
	equal(h.ns.Guidance.Owns(), false, label .. ": and clearing it stops what a Go started")
	clean(h, label)
end

-- The choice going, however it went, stops whatever of ours guides (design §2.6), a Go that left no record of the
-- journey included. A route the player started in Shortest Path is theirs and stays.
for _, spf in ipairs({ false, "v1" }) do
	local label = "cleared: " .. (spf or "no Shortest Path")
	local h = Load(spf, PINS_ON)
	h.ns.OpenPanel()
	h.flush()
	local function Rings()
		return #(h.pins.AdventureGuideForeverPinTemplate or {})
	end
	equal(Rings() > 0, true, label .. ": the chosen journey's rings")
	-- A Go that recorded no journey (prefs.guided), as an aside's or a giver's does.
	h.ns.Guidance.Navigate(h.ns.Route().steps[1])
	h.flush()
	equal(h.ns.Prefs().guided, nil, label .. ": no journey recorded")
	equal(StopButton(h):IsShown(), true, label .. ": Stop offered")
	h.ns.Choose(nil)
	h.flush()
	equal(h.ns.Guidance.Owns(), false, label .. ": nothing of ours guides")
	if spf then
		equal(h.spf.Cancel, 1, label .. ": our route cancelled")
		equal(h.spfRoute, nil, label .. ": and gone")
	else
		equal(h.counts.ClearUserWaypoint, 1, label .. ": our waypoint cleared")
	end
	equal(Rings() > 0, true, label .. ": the first card is previewed again")
	equal(StopButton(h):IsShown(), false, label .. ": Stop hides")
	clean(h, label)
end
do
	local h = Load("v1", PINS_ON)
	h.flush()
	h.spfOther()
	h.ns.Choose(nil)
	h.flush()
	equal(h.spf.Cancel, 0, "cleared, player's route: nothing cancelled")
	equal(h.spfRoute and h.spfRoute.owner, "Player", "cleared, player's route: it keeps guiding")
	clean(h, "cleared, player's route")
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
	-- Opening the guide never asks for the quest log: with the sidebar collapsed it opens in its own window.
	h.ns.OpenPanel()
	equal(h.ns.WindowShown(), false, "open: a shown sidebar holds the guide")
	h.G.QuestMapFrame:Hide()
	h.ns.OpenPanel()
	equal(h.counts.OpenQuestLog, 0, "open: a collapsed sidebar is left collapsed")
	equal(h.ns.WindowShown(), true, "open: and the guide opens in its window")
	h.G.QuestMapFrame:Show()
	clean(h, "preview")
end

-- The activity filters live in the cog's menu, not on the guide (design §2.1).
do
	local h = Load(false)
	h.ns.OpenPanel()
	h.flush()
	local cog = h.Find(function(frame)
		return frame.name == "AdventureGuideForeverSettingsButton"
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

-- F16, the first aside (Asides.lua): with spells to train, one trainer line in the guide and the tracker, at the
-- nearest trainer who teaches them; otherwise none. Four Tweaks Forever profiles: absent, no answer yet,
-- nothing to train, and three spells.
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
			-- Swart in Razor Hill, a town with no flight master: the zone names it.
			text = "Visit your class trainer in Durotar · 3 new spells",
		},
	}) do
		local label = "trainer, " .. case.label
		local h = harness.load({
			planned = true,
			spf = "v1+",
			db = { showMapPins = true, showQuestGivers = true, autoStart = false },
			tf = case.tf,
			completed = { 844 },
			log = {
				{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
				{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
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
		local block = h.tracker.liveBlocks.aside
		local shown = block and block.used and block.header or nil
		equal(shown, case.text, label .. ": the tracker's line")
		-- With no journey chosen it is the line above the first card's step.
		local order = case.text and { "aside", "journey", "town:376" } or { "journey", "town:376" }
		same(h.tracker.layoutOrder, order, label .. ": the tracker's lines")
		-- An aside, not a step: no ring for it, and its tracker title goes to the trainer as its Go does.
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
		equal(h.spf.Navigate + h.spf.NavigateRoute - routes, case.text and 1 or 0, label .. ": guidance to the trainer")
		if case.text then
			equal(h.spfRoute.stops[1].title, "Swart", label .. ": named for the trainer")
		end
		equal(h.ns.Route().steps[1].key, "town:376", label .. ": the route is unchanged")
		-- A spell learned at the trainer shortens the line at once.
		if case.tf and case.tf.spells == THREE then
			case.tf.spells = { SPELL }
			h.fire("SPELLS_CHANGED")
			h.flush()
			equal(
				h.tracker.liveBlocks.aside.header,
				"Visit your class trainer in Durotar · 1 new spell",
				label .. ": one left"
			)
			case.tf.spells = THREE
		end
		clean(h, label)
	end
end

-- Trainer recommendations must not send a character to buy spells they cannot afford.
do
	local h = harness.load({
		planned = true,
		preserveUnknownCosts = true,
		tf = {
			spells = {
				{ name = "Free", level = 1, cost = 0 },
				{ name = "Affordable", level = 2, cost = 4 },
				{ name = "Too expensive", level = 3, cost = 5 },
				{ name = "Unknown price", level = 4 },
			},
		},
		money = 4,
	})
	local training, known = h.ns.Integrations.Training()
	equal(known, true, "trainer affordability: provider known")
	equal(training.count .. "|" .. training.level, "2|2", "trainer affordability: only affordable known fees")
	h.G.GetMoney = function()
		return 5
	end
	h.fire("PLAYER_MONEY")
	training = h.ns.Integrations.Training()
	equal(
		training.count .. "|" .. training.level,
		"3|3",
		"trainer affordability: money change makes new spell actionable"
	)
	h.G.GetMoney = function()
		return 3
	end
	h.fire("PLAYER_MONEY")
	training = h.ns.Integrations.Training()
	equal(training.count .. "|" .. training.level, "1|1", "trainer affordability: money loss keeps only free spell")
	clean(h, "trainer affordability")
end

-- A chosen journey passing a trainer who teaches the spells to train stops there, a step like any other:
-- the tracker, a ring, Go. Learning the spell (SPELLS_CHANGED) ends the stop. A level-8 troll rogue in Razor Hill.
do
	local label = "trainer stop"
	local spells = { { spellID = 1, name = "Sprint", level = 8, line = "Combat", lineID = 38, general = false } }
	local tf = { spells = spells }
	local h = harness.load({
		planned = true,
		spf = "v1",
		db = { showMapPins = true, showQuestGivers = true, autoStart = false },
		tf = tf,
		player = { level = 8, map = 1411, x = 0.52, y = 0.43, classID = 4, raceID = 8 },
		charDB = { journey = "zone:1411" },
	})
	h.ns.OpenPanel()
	h.flush()
	-- Tweaks Forever's list, counted, at its highest level: the trainer must teach up to it.
	tf.spells =
		{ { spellID = 2, name = "Gouge", level = 10, line = "Combat", lineID = 38, general = false }, spells[1] }
	local training = h.ns.Integrations.Training() or {}
	equal(training.count .. "|" .. training.level, "2|10", label .. ": counted, at the highest level")
	tf.spells = spells
	local step = h.ns.Route().steps[1]
	equal(step.key, "trainer:3170", label .. ": the route's first stop")
	same({ h.tracker.liveBlocks[step.key].header, unpack((TrackerLines(h))) }, {
		"Train in Durotar",
		"Kaplak, Durotar",
		"1 new spell",
		"About 6 min away",
		"Next: " .. h.ns.Route().steps[2].title .. " (no dash)",
	}, label .. ": the tracker")
	local ringed = false
	for _, pin in ipairs(h.pins.AdventureGuideForeverPinTemplate or {}) do
		ringed = ringed or pin.step == step
	end
	equal(ringed, true, label .. ": its ring")
	local routes = h.spf.NavigateRoute
	h.ns.StartRoute(step)
	h.flush()
	equal(h.spf.NavigateRoute - routes, 1, label .. ": Go")
	equal(h.spfRoute.stops[1].title, "Train in Durotar", label .. ": to the trainer")
	-- In combat Tweaks Forever is never asked, and the cheap rebuild keeps the stop.
	h.SetCombat(true)
	local asked = h.tf.TrainableSpells
	h.fire("SPELLS_CHANGED")
	h.ns.Invalidate()
	h.flush()
	equal(h.tf.TrainableSpells - asked, 0, label .. ": not asked in combat")
	equal(h.ns.Route().steps[1].key, step.key, label .. ": kept in combat")
	h.SetCombat(false)
	h.flush()
	equal(h.ns.Route().steps[1].key, step.key, label .. ": and after it")
	tf.spells = nil
	h.fire("SPELLS_CHANGED")
	h.flush()
	equal(h.ns.Route().steps[1].kind, "town", label .. ": learned, no stop")
	clean(h, label)
end

-- The golden layout: any change to what the guide draws shows as a reviewable diff of tests/golden/layout.json. It is
-- the story card's towns with Shortest Path loaded (their counts, and step 1's minutes), as tests/scenes.lua draws it.
do
	local json, diff = dofile("tests/json.lua"), dofile("tests/dump_diff.lua")
	local h = Load("v1", nil, { journey = "zone:1413" })
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

-- #23 Honest coverage: one dimmed line under the cards when the log holds a quest the data lacks, or the player's zone
-- has quests Forever added that the data lacks; never beside the search's results.
do
	local UNKNOWN = { id = 99999, title = "A Forever quest", level = 18, complete = false }
	for _, case in ipairs({
		{ label = "every quest known", lines = 0 },
		{ label = "a log quest the data lacks", log = UNKNOWN, lines = 1 },
		{ label = "Westfall, where Forever added quests", player = { map = 1436, x = 0.5, y = 0.5 }, lines = 1 },
		{
			label = "Westfall, its added quests finished",
			player = { map = 1436, x = 0.5, y = 0.5 },
			completed = { 844, 92742, 92744, 92745, 92747, 92748, 92752, 92753, 92819 },
			lines = 0,
		},
	}) do
		local label = "unlisted, " .. case.label
		local log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		}
		log[#log + 1] = case.log
		local h =
			harness.load({ planned = true, completed = case.completed or { 844 }, log = log, player = case.player })
		h.ns.OpenPanel()
		h.flush()
		local function Line(text)
			for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
				if entry.text == text then
					return entry
				end
			end
		end
		local function Top(entry)
			for _, anchor in ipairs(entry and entry.anchors or {}) do
				if anchor.point == "TOPLEFT" then
					return anchor.y
				end
			end
		end
		local line = Line(h.ns.L.UNLISTED)
		equal(line and 1 or 0, case.lines, label .. ": the line")
		if line then
			-- The lowest of the list's other rows: the chosen card's last step, or the overview's last card.
			local list, lowest = line.path:match("^(.*)%.FontString%[%d+%]$"), 0
			for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverPanel, h.Describe)) do
				local anchor = entry.anchors and entry.anchors[1]
				local top = anchor and (anchor.point == "TOPLEFT" or anchor.point == "TOP")
				if entry ~= line and top and anchor.relativeTo == list then
					lowest = math.min(lowest, anchor.y)
				end
			end
			equal(line.font, "GameFontDisableSmall", label .. ": dimmed")
			equal(lowest < 0 and Top(line) < lowest, true, label .. ": under the steps")
			h.Type(
				h.Find(function(frame)
					return frame.stockTemplate == "SearchBoxTemplate"
				end)[1],
				"Call of"
			)
			equal(Line(h.ns.L.UNLISTED), nil, label .. ": not beside the search's results")
		end
		clean(h, label)
	end
end

-- State reads skill ranks from C_SkillInfo, again on SKILL_LINES_CHANGED, and standings from
-- C_Reputation; a change of either rebuilds, and the why-not search names both in the client's words.
do
	local label = "gates"
	local h = harness.load({
		planned = true,
		player = { level = 55 },
		skills = { { skillID = 197, name = "Tailoring", rank = 75 } },
		reputation = {
			[576] = { name = "Timbermaw Hold", currentStanding = 2999 },
			[889] = { name = "Warsong Outriders", currentStanding = 2999 },
		},
	})
	local State = h.ns.State
	equal(State.Player().skills[197], 75, label .. ": a learned line's rank")
	equal(State.Player().skills[186], nil, label .. ": no unlearned line")
	h.skills[1].rank = 150
	h.fire("SKILL_LINES_CHANGED")
	equal(State.Player().skills[197], 150, label .. ": read again when the lines change")
	equal(State.Reputation(576), 2999, label .. ": the client's standing")
	equal(State.Reputation(529), nil, label .. ": none where the client gives none")
	equal(State.SkillName(197), "Tailoring", label .. ": the client's skill name")
	equal(State.SkillName(186), nil, label .. ": none for an unlearned line")
	equal(State.FactionName(576), "Timbermaw Hold", label .. ": the client's faction name")
	h.G.FACTION_STANDING_LABEL5 = "Amical"
	equal(State.StandingName(5), "Amical", label .. ": the client's standing name")
	equal(State.StandingName(9), nil, label .. ": none past Exalted")
	equal(
		h.ns.Model.Eligible(h.ns.Data, State.Player(), {}, {}, 7868),
		false,
		label .. ": Outrider Advanced Care Package short of Friendly"
	)
	h.reputation[889].currentStanding = 3000
	equal(h.ns.Model.Eligible(h.ns.Data, State.Player(), {}, {}, 7868), true, label .. ": open at Friendly")
	h.ns.OpenPanel()
	h.flush()
	local plans = h.modelCalls.Plan
	h.fire("UPDATE_FACTION")
	h.flush()
	equal(h.modelCalls.Plan > plans, true, label .. ": a standing change rebuilds")
	plans = h.modelCalls.Plan
	h.fire("UPDATE_FACTION")
	h.skills[2] = { skillID = 43, name = "Swords", rank = 11 }
	h.fire("SKILL_LINES_CHANGED")
	h.flush()
	equal(h.modelCalls.Plan, plans, label .. ": no gated standing or rank moved, no rebuild")
	h.skills[1].rank = 151
	h.fire("SKILL_LINES_CHANGED")
	h.flush()
	equal(h.modelCalls.Plan > plans, true, label .. ": a gated rank moved")
	h.reputation[889].currentStanding = 2999
	h.Type(
		h.Find(function(frame)
			return frame.stockTemplate == "SearchBoxTemplate"
		end)[1],
		"Outrider Advanced Care Package"
	)
	local row = Shown(h, function(frame)
		return frame.Lines ~= nil and frame.Title:GetText() == "Outrider Advanced Care Package"
	end)[1]
	local lines = {}
	for _, line in ipairs(assert(row, label .. ": Outrider Advanced Care Package found").Lines) do
		lines[#lines + 1] = line:IsVisible() and line:GetText() or nil
	end
	equal(
		lines[1],
		"Requires Amical with Warsong Outriders",
		label .. ": the unmet standing leads, in the client's words"
	)
	equal(row.Lock:IsShown(), true, label .. ": behind a lock")
	clean(h, label)
end

-- With no rest the route ends at the inn its last town has; stepping into an inn ticks it off, and a
-- rest or XP event that moves nothing rebuilds nothing. The carry card's one stop is a hand-in in Durotar.
do
	local h = harness.load({
		planned = true,
		player = { rested = false },
		charDB = { journey = "carry" },
		completed = { 844 },
		log = {
			{ id = 830, title = "The Admiral's Orders", level = 7, complete = true, map = 1411, x = 0.5195, y = 0.435 },
		},
	})
	h.flush()
	local REST = h.ns.L.REST_HERE
	local function Last()
		local steps = h.ns.Route().steps
		return steps[#steps].reason
	end
	equal(Last(), REST, "rest: no rest, the route ends at an inn")
	local builds = h.modelCalls.Journeys
	h.fire("UPDATE_EXHAUSTION")
	h.fire("PLAYER_XP_UPDATE", "player")
	h.flush()
	equal(h.modelCalls.Journeys - builds, 0, "rest: an event that moves nothing rebuilds nothing")
	h.player.resting = true
	h.fire("PLAYER_UPDATE_RESTING")
	h.flush()
	equal(h.modelCalls.Journeys - builds, 1, "rest: resting rebuilds once")
	equal(Last() ~= REST, true, "rest: resting ticks it off")
	h.player.resting, h.player.rested = false, 5000
	h.fire("PLAYER_UPDATE_RESTING")
	h.fire("UPDATE_EXHAUSTION")
	h.flush()
	equal(Last() ~= REST, true, "rest: rested, no line")
	h.player.rested = 100
	h.fire("PLAYER_XP_UPDATE", "player")
	h.flush()
	equal(Last(), REST, "rest: XP that spends the rest brings it back")
	clean(h, "rest")
end

-- A wanderer is told where and never taken there. The one setting gates every waypoint, Shortest Path
-- route and map mark; choosing still chooses, and turning it on stops what Go started.
for _, spf in ipairs({ false, "v1" }) do
	local label = "wanderer, " .. (spf or "no Shortest Path")
	local h = Load(spf, { showMapPins = true, showQuestGivers = true, wanderer = true })
	local ns = h.ns
	equal(ns.Setting("wanderer"), true, label .. ": the saved setting")
	equal(Load(spf).ns.Setting("wanderer"), false, label .. ": Guide by default")
	local step = ns.Route().steps[1]
	equal(ns.StartRoute(step), false, label .. ": Go guides nothing")
	equal(ns.Guidance.Navigate(step), false, label .. ": nor does Navigate")
	equal(h.counts.SetUserWaypoint or 0, 0, label .. ": no waypoint")
	equal(spf and h.spf.NavigateRoute or 0, 0, label .. ": no Shortest Path route")
	equal(#h.uiErrors, 0, label .. ": and no error line")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[step.key], "LeftButton")
	h.flush()
	equal(h.counts.SetUserWaypoint or 0, 0, label .. ": the tracker title sets none either")
	equal(ns.Prefs().guided, nil, label .. ": nothing recorded as guided")
	equal(ns.Guidance.Status() == "paused", false, label .. ": so the journey never reads as paused")
	h.SetCombat(true)
	equal(ns.StartRoute(), false, label .. ": in combat nothing waits to start")
	equal(ns.Guidance.Status(), nil, label .. ": no start pending")
	ns.Choose("zone:1413", true)
	equal(ns.Guidance.Status(), nil, label .. ": a card chosen in combat waits for nothing")
	h.SetCombat(false)
	h.flush()
	equal(h.counts.SetUserWaypoint or 0, 0, label .. ": nor starts once combat ends")
	equal(spf and h.spf.NavigateRoute or 0, 0, label .. ": nor hands Shortest Path a route")
	h.G.C_Map.OpenWorldMap()
	h.flush()
	ns.OpenPanel()
	h.flush()
	h.providers[1]:RefreshAllData()
	equal(#h.pins.AdventureGuideForeverPinTemplate, 0, label .. ": no rings, even with the guide open")
	equal(#h.pins.AdventureGuideForeverGiverPinTemplate, 0, label .. ": no givers")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks[step.key], "RightButton")
	for _, entry in ipairs(h.menu.entries) do
		equal(entry.text ~= ns.L.GO, true, label .. ": the step menu offers no Go")
	end
	clean(h, label)

	-- Guide mode's Go, then wandering: what Go started stops.
	h = Load(spf)
	ns = h.ns
	equal(ns.StartRoute(), true, label .. ": Guide's Go guides")
	equal(ns.Guidance.Owns(), true, label .. ": ours")
	ns.SetSetting("wanderer", true)
	h.flush()
	equal(ns.Guidance.Owns(), false, label .. ": wandering stops it")
	equal(ns.Prefs().guided, nil, label .. ": and forgets it")
	clean(h, label .. ": turned on")
end

-- Stop tooltips retain quest difficulty styling and all quests represented by a merged stop.
do
	local h = Load(false)
	local tooltip = h.ns.Pins.StopTooltip({ quests = { 8, 590 } })
	equal(type(tooltip), "string", "stop tooltip: merged quests produce text")
	equal(tooltip:find("|cff", 1, true) ~= nil, true, "stop tooltip: difficulty color escape")
	equal(tooltip:find("A Rogue's Deal", 1, true) ~= nil, true, "stop tooltip: first quest title")
	equal(tooltip:find("\n", 1, true) ~= nil, true, "stop tooltip: merged quest separator")
	local plain = h.ns.Pins.StopTooltip({ quests = { 999999 } })
	equal(plain, nil, "stop tooltip: unknown quest has no invented level")
	local ns = h.ns
	-- Separate data tables keep the real chain index cache valid between scenarios.
	ns.Data = {
		quests = {
			[900001] = { title = "First chain", level = 2, next = 900002 },
			[900002] = { title = "Harder successor", level = 20, pre = { 900001 } },
			[900003] = { title = "Second chain", level = 3, next = 900004 },
			[900004] = { title = "Second successor", level = 4, pre = { 900003 } },
			[900005] = { title = "Unknown level", level = 0 },
		},
	}
	local details = ns.Pins.StopTooltip({ quests = { 900001, 900003, 900005 } })
	equal(details:find("[2] First chain", 1, true) ~= nil, true, "stop context: first known level")
	equal(details:find("[20] Harder successor", 1, true) ~= nil, true, "stop context: successor has own level")
	equal(details:find("Next: |cff", 1, true) ~= nil, true, "stop context: successor difficulty color")
	equal(details:find("Second successor", 1, true) ~= nil, true, "stop context: every quest carries chain context")
	local _, chapters = details:gsub("Chapter 1 of 2", "")
	equal(chapters, 2, "stop context: both proven chapters")
	equal(details:find("[0]", 1, true), nil, "stop context: unknown level omitted")
	local final = ns.Pins.StopTooltip({ quests = { 900002 } })
	equal(final:find("Chapter 2 of 2", 1, true) ~= nil, true, "stop context: final chapter")
	equal(final:find("Next:", 1, true), nil, "stop context: final chapter has no successor")
	ns.Data = {
		quests = {
			[900001] = { title = "Unproven chain", level = 2, next = 900002 },
			[900002] = { title = "Ambiguous successor", level = 3, preAny = { 900001, 900003 } },
			[900003] = { title = "Other predecessor", level = 2, next = 900002 },
		},
	}
	local uncertain = ns.Pins.StopTooltip({ quests = { 900001, 900002 } })
	equal(uncertain:find("Chapter", 1, true), nil, "stop context: no unproven chapter claim")
	equal(uncertain:find("Next:", 1, true), nil, "stop context: no ambiguous successor claim")
	clean(h, "stop tooltip context")
end

print(("ui_spec: %d checks passed"):format(checks))
