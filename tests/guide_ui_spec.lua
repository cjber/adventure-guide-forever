-- Run from the repository root: luajit tests/guide_ui_spec.lua
-- The window's PvP and Completion tabs, Go to entrance, Today's overflow, the session picker, reordering, the step
-- kinds' badges, a town's checklist and a revisited place's ring (docs/design.md §2.9, §2.19, §2.20), through the
-- harness and the real Session, Order, PvP and Providers modules. The map tab, drag feel, menus and pin art
-- still need /reload checks.
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

local function clean(h, label)
	equal(#h.errors, 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
end

local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
}
local SPELL = { name = "Lightning Bolt", level = 18, line = "Elemental", lineID = 375, general = false }

-- ui_spec's level-18 orc shaman in The Barrens, the story chosen unless `extra.charDB` says otherwise.
local function Load(extra)
	local options = { completed = { 844 }, log = LOG, charDB = { journey = "zone:1413" } }
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	return harness.load(options)
end

local function Open(h, tab)
	h.ns.OpenWindow()
	h.flush()
	local window = h.G.AdventureGuideForeverWindow
	if tab then
		h.Click(window.Tabs[tab])
		h.flush()
	end
	return window
end

local function Redraw(h)
	h.ns.Invalidate()
	h.flush()
	h.ns.Window.Refresh()
	h.flush()
end

local function Under(frame, root)
	while frame do
		if frame == root then
			return true
		end
		frame = frame:GetParent()
	end
	return false
end

-- Every text the window shows, from its dump: font strings and button labels.
local function Texts(h, root)
	local texts = {}
	for _, entry in ipairs(h.ns.DumpLayout(root or h.G.AdventureGuideForeverWindow, h.Describe)) do
		if entry.text then
			texts[entry.text] = (texts[entry.text] or 0) + 1
		end
	end
	return texts
end

local function Visible(h, root, test)
	local found = h.Find(function(frame)
		return frame:IsVisible() and Under(frame, root) and test(frame)
	end)
	return found
end

-- The window's step rows, in route order.
local function StepRows(h, root)
	local rows = Visible(h, root, function(frame)
		return frame.Kind ~= nil and frame.index ~= nil and frame.step ~= nil
	end)
	table.sort(rows, function(a, b)
		return a.index < b.index
	end)
	return rows
end

--[[ The PvP tab ]]

do
	local battles = {
		[10] = { { id = 2, name = "Warsong Gulch" } },
		[30] = { { id = 1157, name = "Darkspear Islands" } },
	}
	local h = Load({
		player = { level = 30 },
		battlegrounds = battles,
		rank = {
			info = { renownLevel = 3, renownReputationEarned = 1200, renownLevelThreshold = 3000, maxLevel = 14 },
			rewards = { [4] = { { description = "Tabard" } } },
		},
	})
	local ns, L = h.ns, h.ns.L
	local window = Open(h, 3)
	equal(window.selectedTab, 3, "pvp: the third tab")
	equal(window.Tabs[3]:GetText(), L.TAB_PVP, "pvp: its label")
	local texts = Texts(h)
	equal(texts[L.PVP_RANK:format(3)], 1, "pvp: the rank")
	equal(texts[L.PVP_RANK_POINTS:format(1200, 3000)], 1, "pvp: its points")
	equal(texts[L.PVP_NEXT_REWARD:format(4, "Tabard")], 1, "pvp: the next reward")
	equal(texts["Warsong Gulch"], 1, "pvp: a battleground")
	equal(texts[L.PVP_BATTLEGROUND_LEVEL:format(10)], 1, "pvp: from its level")
	equal(texts[L.PVP_BATTLEGROUND_LEVEL:format(30) .. L.SEPARATOR .. L.PVP_NO_BATTLEMASTER], 1, "pvp: no battlemaster")
	local rows = Visible(h, window, function(frame)
		return frame.battle ~= nil
	end)
	equal(#rows, 2, "pvp: a row a battleground")
	for _, row in ipairs(rows) do
		h.Click(row)
	end
	equal(h.waypoint.uiMapID, ns.PvP.Data().battlegrounds[2].place.map, "pvp: the battlemaster waypoint")
	equal(h.waypoint.position.x, ns.PvP.Data().battlegrounds[2].place.x, "pvp: the real battlemaster")
	h.Hover(rows[1].battle.place and rows[1] or rows[2])
	equal(h.tooltip[#h.tooltip], "instruction: " .. L.PVP_GO_BATTLEMASTER, "pvp: the row's click line")

	h.rank.info.renownLevel = 14
	h.player.level = 1
	Redraw(h)
	texts = Texts(h)
	equal(texts[L.PVP_CAPPED], 1, "capped: says so")
	equal(texts[L.PVP_RANK_POINTS:format(0, 0)], nil, "capped: no points")
	equal(texts[L.PVP_NO_BATTLEGROUNDS], 1, "capped: no battlegrounds at the level")

	h.rank.info = nil
	h.G.C_PvP = nil
	Redraw(h)
	texts = Texts(h)
	equal(texts[L.PVP_UNAVAILABLE], 1, "unavailable: the page says why")
	equal(texts[L.MENU_BATTLEGROUNDS], nil, "unavailable: nothing else")
	equal(window.Tabs[3].normalFont, "GameFontDisableSmall", "unavailable: the label greys")
	clean(h, "pvp")
	ns.Window.Refresh()
end

--[[ The Completion tab ]]

do
	local legacy = { summaries = {}, targets = {} }
	local h = Load({ legacy = legacy })
	local L = h.ns.L
	local addon = h.G.LegacyForever
	h.G.LegacyForever = nil
	local window = Open(h, 4)
	equal(window.selectedTab, 4, "legacy missing: the tab still opens")
	equal(window.Tabs[4].normalFont, "GameFontDisableSmall", "legacy missing: its label greys")
	equal(Texts(h)[L.LEGACY_MISSING], 1, "legacy missing: the page says to install it")
	h.Hover(window.Tabs[4])
	equal(h.tooltip[#h.tooltip], "normal: " .. L.LEGACY_MISSING, "legacy missing: and the tab's tooltip")

	h.G.LegacyForever = addon
	addon.API.version = 0
	Redraw(h)
	equal(Texts(h)[L.LEGACY_OUTDATED], 1, "legacy outdated: says to update it")

	addon.API.version = 1
	h.fire("ADDON_LOADED", "LegacyForever")
	local function Zone(map, name, done)
		return {
			map = map,
			name = name,
			summary = {
				name = name,
				done = done,
				total = 20,
				pending = 1,
				questsStatus = "ready",
				complete = false,
				categories = {
					{ key = "areas", scope = "character", done = 3, total = 5, pending = 0, complete = false },
					{ key = "taxis", scope = "account", done = 2, total = 2, pending = 0, complete = true },
				},
			},
			targets = {
				{
					key = "explore:1",
					text = "Explore the Crossroads",
					kind = "explore",
					place = { map = map, x = 0.5, y = 0.3 },
				},
				{ key = "kill:2", text = "Defeat Kolkar", kind = "kill", quantity = 2, required = 5 },
			},
		}
	end
	for _, zone in ipairs({ Zone(1413, "The Barrens", 7), Zone(1442, "Stonetalon Mountains", 1) }) do
		legacy.summaries[zone.map], legacy.targets[zone.map] = zone.summary, zone.targets
	end
	Redraw(h)
	local texts = Texts(h)
	equal(window.Tabs[4].normalFont, "GameFontNormalSmall", "ready: the label is gold")
	equal(texts["The Barrens"] ~= nil, true, "ready: the player's zone featured")
	equal(texts[L.COMPLETION_COUNTS:format(7, 20)], 1, "ready: its overall count")
	equal(texts[L.COMPLETION_NOT_KNOWN:format(1)] ~= nil, true, "ready: what Legacy can't check, in words")
	equal(texts["Explore the Crossroads"], 1, "ready: a target")
	equal(texts[L.COMPLETION_COUNTS:format(2, 5) .. L.SEPARATOR .. L.COMPLETION_NO_LOCATION], 1, "ready: no place")
	local rows = Visible(h, window, function(frame)
		return frame.target ~= nil
	end)
	for _, row in ipairs(rows) do
		h.Click(row)
	end
	equal(#h.legacy.navigations, 1, "ready: only a target with a place goes")
	equal(h.legacy.navigations[1].map, 1413, "ready: navigation map")
	equal(h.legacy.navigations[1].key, "explore:1", "ready: navigation target")
	local other = Visible(h, window, function(frame)
		return frame.zone ~= nil and frame.zone.map == 1442 and frame.target == nil
	end)[1]
	equal(other ~= nil, true, "ready: the next zone's card")
	h.Click(other)
	h.flush()
	equal(Texts(h)[L.COMPLETION_COUNTS:format(1, 20)], 1, "ready: its click features it")

	-- A fresh character's flight paths: none known yet reads as words and Legacy's hint, never
	-- "0/0 · 1 pending"; a category that knows some adds the rest in words.
	local fresh = legacy.summaries[1442]
	fresh.pending, fresh.categories =
		1, {
			{ key = "areas", scope = "character", done = 1, total = 5, pending = 0, complete = false },
			{ key = "taxis", scope = "character", done = 0, total = 0, pending = 1, complete = false },
		}
	Redraw(h)
	texts = Texts(h)
	equal(texts[L.COMPLETION_NOT_KNOWN_TAXIS:format(1)], 1, "not known: the zone line says how to check them")
	equal(texts[L.COMPLETION_CATEGORY_TAXIS .. "  " .. L.COMPLETION_NOT_KNOWN:format(1)], 1, "not known: no 0/0")
	fresh.pending, fresh.categories[1].done, fresh.categories[1].total, fresh.categories[1].pending = 3, 3, 5, 2
	Redraw(h)
	texts = Texts(h)
	equal(texts[L.COMPLETION_NOT_KNOWN:format(3)], 1, "not known, two categories: no one hint")
	local areas = L.COMPLETION_COUNTS:format(3, 5) .. L.SEPARATOR .. L.COMPLETION_NOT_KNOWN:format(2)
	equal(
		texts[L.COMPLETION_CATEGORY_AREAS .. "  " .. areas],
		1,
		"not known: the counts it has, then the rest in words"
	)

	legacy.summaries[1442].categories = {}
	legacy.targets[1442] = {}
	equal(h.legacy.subscriptions, 1, "shown: subscribed to Legacy")
	h.legacyChanged()
	h.flush()
	equal(Texts(h)[L.COMPLETION_EMPTY] ~= nil, true, "ready, no categories: says so")
	window:Hide()
	equal(h.legacy.subscriptions, 0, "hidden: unsubscribed from Legacy")
	clean(h, "completion")
end

--[[ Go to entrance ]]

do
	local entrances = {}
	local h = Load({ charDB = { journey = "dungeon:389", dungeons = true }, entrances = entrances })
	local L = h.ns.L
	local addon = h.G.TweaksForever
	local window = Open(h)
	local function Entrance()
		return Visible(h, window, function(frame)
			return frame.text == L.GO_TO_ENTRANCE
		end)[1]
	end
	for _, case in ipairs({
		{ "missing", L.TWEAKS_MISSING },
		{ "outdated", L.TWEAKS_OUTDATED },
		{ "unknown", L.ENTRANCE_UNKNOWN },
	}) do
		h.G.TweaksForever = case[1] ~= "missing" and addon or nil
		addon.API.version = case[1] == "outdated" and 0 or 1
		Redraw(h)
		local button = Entrance()
		equal(button ~= nil, true, case[1] .. ": the dungeon card has Go to entrance")
		equal(button:IsEnabled(), false, case[1] .. ": greyed")
		equal(Texts(h)[case[2]], 1, case[1] .. ": the note says why")
	end
	entrances[389] = { map = 1411, x = 0.52, y = 0.49 }
	Redraw(h)
	equal(Entrance():IsEnabled(), true, "ready: enabled")
	equal(Texts(h)[L.TWEAKS_MISSING], nil, "ready: no note")
	h.Click(Entrance())
	equal(h.waypoint.uiMapID, 1411, "ready: entrance map")
	equal(h.waypoint.position.x, 0.52, "ready: entrance point")
	equal(h.ns.Prefs().journey, "dungeon:389", "entrance keeps the journey")
	clean(h, "entrance")

	local story = Load({ charDB = { journey = "zone:1413", dungeons = true } })
	local storyWindow = Open(story)
	local shown = Visible(story, storyWindow, function(frame)
		return frame.text == L.GO_TO_ENTRANCE
			and frame:GetParent().journey ~= nil
			and frame:GetParent().journey.kind ~= "dungeon"
	end)
	equal(#shown, 0, "only a dungeon card has one")
	clean(story, "entrance: others")
end

--[[ Today's overflow ]]

do
	local h = Load({
		tf = { spells = { SPELL } },
		talents = 1,
		setup = function(each)
			for _, extra in ipairs({
				{
					key = "hearth",
					text = "Set your hearth in Crossroads",
					icon = "innkeeper",
					place = { map = 1413, x = 0.51, y = 0.3 },
				},
				{ key = "weapon", text = "Learn Staves", icon = "class" },
				{ key = "mount", text = "Save for a mount", icon = "class", place = { map = 1454, x = 0.6, y = 0.7 } },
			}) do
				each.ns.Asides.Register(function()
					return extra
				end)
			end
		end,
	})
	local L = h.ns.L
	local window = Open(h)
	local all = h.ns.Asides.All()
	equal(#all, 5, "overflow: five asides")
	local texts = Texts(h)
	for index = 1, 3 do
		equal(texts[all[index].text], 1, "overflow: chip " .. index)
	end
	equal(texts[all[4].text], nil, "overflow: the fourth goes in the menu")
	local more = Visible(h, window, function(frame)
		return frame.text == L.TODAY_MORE:format(2)
	end)[1]
	equal(more ~= nil, true, "overflow: +2 more in the last slot")
	equal(more.stockTemplate, "UIPanelButtonTemplate", "overflow: a stock button")
	h.Click(more)
	equal(h.menu.tag, "MENU_ADVENTURE_GUIDE_FOREVER_TODAY", "overflow: its menu")
	equal(#h.menu.entries, 2, "overflow: an entry each")
	equal(h.menu.entries[1]:IsEnabled(), false, "overflow: an aside with no place is greyed")
	h.menu.entries[2].onClick()
	equal(h.waypoint.uiMapID, 1454, "overflow: an entry goes as its chip would")
	h.ns.Asides.Decline(all[5])
	h.ns.Asides.Decline(all[4])
	h.flush()
	h.ns.Window.Refresh()
	equal(more:IsShown(), false, "four fit: no overflow")
	clean(h, "today")
end

--[[ The session picker ]]

do
	local h = Load({
		spf = "v1",
		charDB = { journey = "carry" },
		log = {
			{ id = 5729, title = "Hidden Enemies", level = 15, complete = true, map = 1454, x = 0.4947, y = 0.5059 },
		},
	})
	h.spfSeconds = 1480
	local L = h.ns.L
	local window = Open(h)
	local picker = Visible(h, window, function(frame)
		return frame.stockTemplate == "WowStyle1DropdownTemplate"
	end)[1]
	equal(picker ~= nil, true, "session: a stock dropdown")
	equal(picker.Text:GetText(), L.SESSION_UNLIMITED, "session: No limit to start")
	h.OpenMenu(picker)
	same(h.MenuLines(), {
		"title: " .. L.SESSION_LABEL,
		"radio: " .. L.SESSION_UNLIMITED,
		"radio: " .. L.SESSION_MINUTES:format(15),
		"radio: " .. L.SESSION_MINUTES:format(30),
		"radio: " .. L.SESSION_MINUTES:format(60),
	}, "session: its lengths")
	h.menu.entries[4].onClick()
	equal(h.ns.Session.Get(), 30, "session: a pick persists it")
	Redraw(h)
	equal(picker.Text:GetText(), L.SESSION_MINUTES:format(30), "session: the pick shows")
	equal(h.ns.Session.Info().seconds, 1490, "session: real travel and work estimate")
	equal(Texts(h)[L.SESSION_ABOUT:format(25)], 1, "session: About 25 min")
	h.combat = true
	h.ns.Session.Set(15)
	Redraw(h)
	equal(h.ns.Session.Info().pending, true, "session: combat holds estimates")
	equal(Texts(h)[L.SESSION_PENDING], 1, "session: estimating")
	h.combat = false
	h.fire("PLAYER_REGEN_ENABLED")
	Redraw(h)
	equal(h.ns.Session.Info().empty, true, "session: whole task exceeds 15 minutes")
	equal(Texts(h)[L.SESSION_EMPTY], 1, "session empty: says so")
	equal(#StepRows(h, window), 0, "session empty: no steps")
	h.ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	equal(Texts(h, panel)[L.SESSION_EMPTY], 1, "session empty: the panel says so too")
	clean(h, "session")
end

--[[ Reordering: the menu, the drag, the tag and the way back ]]

-- Fit three real story steps in the window while testing drag targets. Checklist layout has its own case below.
local function Compact(route)
	for _, step in ipairs(route.steps) do
		step.checklist = nil
	end
end

do
	local h = Load({ decorate = Compact })
	local ns, L = h.ns, h.ns.L
	local window = Open(h)
	local rows = StepRows(h, window)
	equal(#rows, 3, "order: three chosen story rows")
	local first, second = ns.Route().steps[1].key, ns.Route().steps[2].key
	equal(ns.Order.CanMove(2, 3), false, "order: pickup cannot follow its objective")
	h.Click(rows[2], "RightButton")
	local entries, lines = h.menu.entries, h.MenuLines()
	local n = #lines
	same({ unpack(lines, n - 3, n) }, {
		"divider",
		"button: " .. L.ORDER_NEXT,
		"button: " .. L.ORDER_SOONER,
		"button: " .. L.ORDER_LATER,
	}, "order: the step menu's moves")
	equal(entries[#entries]:IsEnabled(), false, "order: dependency-breaking move greyed")
	equal(Texts(h)[L.ORDER_RESET], nil, "suggested order: no way back")
	entries[#entries - 1].onClick()
	Redraw(h)
	equal(ns.Route().steps[1].key, second, "order: Do this sooner moves the town")
	equal(ns.Order.IsCustom(), true, "order: the move is persisted")

	rows = StepRows(h, window)
	rows[1]:GetScript("OnDragStart")(rows[1])
	equal(h.cursor, "Interface\\CURSOR\\UI-Cursor-Move", "drag: move cursor")
	equal(rows[3]:GetAlpha(), 0.35, "drag: dependent objective dims")
	equal(rows[2]:GetAlpha(), 1, "drag: independent town stays")
	rows[2].mouseOver = true
	rows[1]:GetScript("OnDragStop")(rows[1])
	rows[2].mouseOver = false
	Redraw(h)
	equal(h.cursor, nil, "drag: cursor reset")
	equal(ns.Route().steps[1].key, first, "drag: exact move applied")
	equal(ns.Route().steps[2].key, second, "drag: town moved to second")
	rows = StepRows(h, window)
	rows[2]:GetScript("OnDragStart")(rows[2])
	rows[3].mouseOver = true
	rows[2]:GetScript("OnDragStop")(rows[2])
	rows[3].mouseOver = false
	equal(ns.Route().steps[2].key, second, "drag: refused drop preserves order")
	equal(Texts(h)[L.ORDER_CUSTOM], 1, "custom order: card tag")
	h.Click(rows[1], "RightButton")
	equal(h.MenuLines()[#h.MenuLines()], "button: " .. L.ORDER_RESET, "custom order: menu reset")
	local reset = Visible(h, window, function(frame)
		return frame.text == L.ORDER_RESET
	end)[1]
	h.Click(reset)
	Redraw(h)
	equal(ns.Order.IsCustom(), false, "window reset clears custom order")
	equal(Texts(h)[L.SUGGESTED], 1, "reset: suggested tag")

	ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	local panelRows = StepRows(h, panel)
	equal(#panelRows >= 3, true, "panel: the rows")
	panelRows[2]:GetScript("OnDragStart")(panelRows[2])
	equal(panelRows[3]:GetAlpha(), 0.35, "panel drag: dependent objective dims")
	panelRows[1].mouseOver = true
	panelRows[2]:GetScript("OnDragStop")(panelRows[2])
	panelRows[1].mouseOver = false
	Redraw(h)
	equal(ns.Route().steps[1].key, second, "panel drag: applied")
	equal(Texts(h, panel)[L.ORDER_CUSTOM], 1, "panel: custom order line")
	h.Hover(panelRows[1])
	equal(h.tooltip[#h.tooltip], "instruction: " .. L.ORDER_DRAG, "panel: drag instruction")
	local reset2 = Visible(h, panel, function(frame)
		return frame.text == L.ORDER_RESET
	end)[1]
	h.Click(reset2)
	Redraw(h)
	equal(ns.Order.IsCustom(), false, "panel reset clears custom order")
	equal(Texts(h, panel)[L.ORDER_CUSTOM], nil, "panel: no custom line after reset")
	clean(h, "order")
end

--[[ The kinds' badges and a town's checklist ]]

do
	local completed = { 844 }
	local h = Load({ completed = completed, db = { showMapPins = true } })
	local ns, L = h.ns, h.ns.L
	local original = ns.Route().steps[1]
	local done = original.checklist[1]
	for _, id in ipairs(done.pickups) do
		h.log[#h.log + 1] = { id = id, title = ns.Data.quests[id].title, complete = false }
	end
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local skipped = ns.Route().steps[1].checklist[2]
	equal(ns.Order.SkipGiver(original.key, skipped.key), true, "checklist: skip a real giver")
	h.flush()
	local window = Open(h)
	local rows = StepRows(h, window)
	local town = ns.Route().steps[1]
	equal(rows[1].Kind:GetAtlas(), "QuestNormal", "badge: town pickup")
	equal(rows[1].Kind:IsShown(), true, "badge: shown")
	local texts = Texts(h)
	for _, giver in ipairs(town.checklist) do
		equal(texts[giver.text], 1, "checklist: " .. giver.name)
	end
	local ticks = Visible(h, window, function(frame)
		return frame.Tick ~= nil
	end)
	local byText = {}
	for _, line in ipairs(ticks) do
		byText[line.Text:GetText()] = line
	end
	equal(byText[done.text].Tick:GetAtlas(), "UI-QuestTracker-Tracker-Check", "checklist: accepted giver ticked")
	equal(byText[skipped.text].Tick:GetAlpha(), 0.4, "checklist: skipped giver fades")
	local open
	for _, giver in ipairs(town.checklist) do
		if not giver.done then
			open = giver
			break
		end
	end
	equal(byText[open.text].Tick:GetAtlas(), "UI-QuestTracker-Objective-Nub", "checklist: open giver nub")
	h.Click(rows[1], "RightButton")
	local skip
	for _, entry in ipairs(h.menu.entries) do
		skip = entry.text == L.TOWN_SKIP_GIVER and entry or skip
	end
	equal(#skip.entries, #town.checklist - 2, "checklist: only remaining givers in menu")
	skip.entries[1].onClick()
	h.flush()
	equal(ns.Order.IsGiverSkipped(town.orderKey, open.key), true, "checklist: menu skips the actual giver")

	ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	local panelRows = StepRows(h, panel)
	local panelChecks = Visible(h, panel, function(frame)
		return frame.Tick ~= nil
	end)
	equal(#panelChecks >= #town.checklist, true, "checklist: panel retains the visit")
	local _, _, _, _, y1 = panelRows[1]:GetPoint(1)
	local _, _, _, _, y2 = panelRows[2]:GetPoint(1)
	equal(y1 - y2 >= 30 + #town.checklist * 14, true, "checklist: next row clears giver lines")
	-- The two visits now target different real givers in Ratchet, but must still share its ring.
	h.MovePlayer(1413, 0.6237, 0.3762)
	ns.Invalidate()
	h.flush()
	h.providers[1]:RefreshAllData()
	local pins = h.pins.AdventureGuideForeverPinTemplate
	local ring = pins[1]
	equal(ring.Badge:GetAtlas(), "QuestNormal", "ring: the kind's badge")
	equal(ring.Badge:GetWidth(), 16, "ring: badge 16 wide, as Shortest Path's")
	local point, _, _, x, y = ring.Badge:GetPoint(1)
	equal(("%s %d %d"):format(point, x, y), "BOTTOMRIGHT 4 -4", "ring: hung past the ring")
	equal(ring.hitRectInsets[4], -4, "ring: the badge takes clicks")
	equal(ring.More:IsShown(), #ring.visits > 1, "ring: only revisits have a count")
	local route = h.ns.Route().steps
	local revisit
	for _, pin in ipairs(pins) do
		revisit = (pin.visits and #pin.visits > 1) and pin or revisit
	end
	equal(revisit ~= nil, true, "ring: Ratchet visited twice")
	equal(revisit.visits[1].step.x ~= revisit.visits[2].step.x, true, "ring: different remaining givers")
	equal(revisit.More:GetText(), L.STOP_MORE:format(1), "ring: +1")
	equal(revisit.Badge:IsShown(), false, "ring: shared stops wear the count instead of a kind")
	equal(#pins, #route - 1, "ring: one ring for both visits")
	equal(revisit.visits[1].step.hub, revisit.visits[2].step.hub, "ring: real town identity")
	h.Hover(revisit)
	local visits = {}
	for _, line in ipairs(h.tooltip) do
		visits[#visits + 1] = line:match("^normal: Stop %d+: .*") and line or nil
	end
	same(visits, {
		"normal: " .. L.STOP_VISIT:format(revisit.visits[1].index, revisit.visits[1].step.title),
		"normal: " .. L.STOP_VISIT:format(revisit.visits[2].index, revisit.visits[2].step.title),
	}, "ring: each visit in the tooltip")
	clean(h, "badges")
end

-- Every verb's icon, including kinds that do not occur together in a single route.
do
	local h = Load()
	local texture = h.G.CreateFrame("Frame"):CreateTexture()
	for _, case in ipairs({
		{ "town", "QuestNormal", { 1 } },
		{ "town", "QuestTurnin", {} },
		{ "pickup", "QuestNormal" },
		{ "turnin", "QuestTurnin" },
		{ "objective", "questobjective" },
		{ "battlemaster", "battlemaster" },
	}) do
		h.ns.Overview.SetVerbIcon(texture, { verb = case[1], pickups = case[3] })
		equal(texture:GetAtlas(), case[2], "badge: " .. case[1])
		equal(texture:IsShown(), true, "badge: visible")
	end
	h.ns.Overview.SetVerbIcon(texture, { verb = "trainer" })
	equal(texture.file, "Interface\\Minimap\\Tracking\\Class", "badge: trainer texture")
	h.ns.Overview.SetVerbIcon(texture, {})
	equal(texture:IsShown(), false, "badge: hidden without a verb")
	clean(h, "badge kinds")
end

print(("guide_ui_spec: %d checks passed"):format(checks))
