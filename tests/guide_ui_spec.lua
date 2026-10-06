-- Run from the repository root: luajit tests/guide_ui_spec.lua
-- The window's PvP and Completion tabs, Go to entrance, Today's overflow, reordering, the step
-- kinds' badges, a town's checklist and a revisited place's ring (docs/design.md §2.9, §2.19, §2.20), through the
-- harness and the real Order, PvP and Providers modules. The map tab, drag feel, menus and pin art
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
	local options = { completed = { 844 }, log = LOG, charDB = { journey = "zone:1413" }, planned = true }
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	return harness.load(options)
end

local function Open(h, tab)
	h.ns.OpenWindow()
	h.flush()
	local window = h.G.AdventureGuideForeverWindow
	if tab == 3 then
		h.ns.Window.SelectActivity("pvp")
	elseif tab == 4 then
		h.ns.Window.Select(3)
	else
		h.ns.Window.Select(1)
	end
	h.flush()
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

local Texts = dofile("tests/ui_helpers.lua").Texts

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
	equal(window.selectedTab, 2, "pvp: the third tab")
	equal(h.G.AdventureGuideForeverActivitypvp:GetText(), L.TAB_PVP, "pvp: its label")
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
	equal(texts[L.PVP_RANK_POINTS:format(1200, 3000)], nil, "capped: no points")
	equal(texts[L.PVP_NO_BATTLEGROUNDS], 1, "capped: no battlegrounds at the level")

	h.rank.info = nil
	h.G.C_PvP = nil
	Redraw(h)
	texts = Texts(h)
	equal(texts[L.PVP_UNAVAILABLE], 1, "unavailable: the page says why")
	equal(texts[L.MENU_BATTLEGROUNDS], nil, "unavailable: nothing else")
	equal(h.G.AdventureGuideForeverActivitypvp.normalFont, "GameFontDisableSmall", "unavailable: the label greys")
	clean(h, "pvp")
end

-- Progress belongs to completed stories, independently of Legacy's installation.
do
	local h = Load()
	local window = Open(h, 4)
	equal(window.Tabs[3].normalFont, "GameFontNormalSmall", "Progress works without Legacy")
	equal(Texts(h)[h.ns.L.JOURNEY_PROGRESS_EMPTY], 1, "no completed stories yet")
	h.ns.Prefs().completedStories["zone:1413"] = { title = "The Barrens story" }
	Redraw(h)
	equal(Texts(h)["The Barrens story"], 1, "completed story appears")
	equal(Texts(h)[h.ns.L.JOURNEY_PROGRESS_EMPTY], nil, "empty hint goes away")
	clean(h, "story progress")
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
	end
	entrances[389] = { map = 1411, x = 0.52, y = 0.49 }
	Redraw(h)
	equal(Entrance():IsEnabled(), true, "ready: enabled")
	for _, note in ipairs({ L.TWEAKS_MISSING, L.TWEAKS_OUTDATED, L.ENTRANCE_UNKNOWN }) do
		equal(Texts(h)[note], nil, "ready: no note")
	end
	h.Click(Entrance())
	equal(h.waypoint.uiMapID, 1411, "ready: entrance map")
	equal(h.waypoint.position.x, 0.52, "ready: entrance point")
	equal(h.ns.Prefs().journey, "dungeon:389", "entrance keeps the journey")
	clean(h, "entrance")
end

--[[ Today's overflow ]]

do
	local h = Load({
		db = { trainingReminders = true },
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
	local window = Open(h, 3)
	local all = h.ns.Asides.All()
	equal(#all, 5, "overflow: five asides")
	local texts = Texts(h)
	for index = 1, 2 do
		equal(texts[all[index].text], 1, "overflow: chip " .. index)
	end
	equal(texts[all[4].text], nil, "overflow: the fourth goes in the menu")
	local more = Visible(h, window, function(frame)
		return frame.text == L.TODAY_MORE:format(3)
	end)[1]
	equal(more ~= nil, true, "overflow: +3 more in the last slot")
	equal(more.normalFont, "GameFontNormalSmall", "overflow: a quiet stock text control")
	h.Click(more)
	equal(#h.menu.entries, 3, "overflow: an entry each")
	equal(h.menu.entries[2]:IsEnabled(), false, "overflow: an aside with no place is greyed")
	h.menu.entries[3].onClick()
	equal(h.waypoint.uiMapID, 1454, "overflow: an entry goes as its chip would")
	h.ns.Asides.Decline(all[5])
	h.ns.Asides.Decline(all[4])
	h.ns.Asides.Decline(all[3])
	h.flush()
	h.ns.Window.Refresh()
	equal(more:IsShown(), false, "two fit: no overflow")
	clean(h, "today")
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
	equal(#rows, math.min(6, #ns.Route().steps), "order: upcoming chosen story rows")
	local second, third = ns.Route().steps[2].key, ns.Route().steps[3].key
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
	h.Click(rows[2], "RightButton")
	entries = h.menu.entries
	entries[#entries - 1].onClick()
	Redraw(h)
	equal(ns.Route().steps[1].key, second, "order: Do this sooner moves the town")
	equal(ns.Order.IsCustom(), true, "order: the move is persisted")

	rows = StepRows(h, window)
	rows[3]:GetScript("OnDragStart")(rows[3])
	equal(h.cursor, "Interface\\CURSOR\\UI-Cursor-Move", "drag: move cursor")
	equal(rows[1]:GetAlpha(), 0.35, "drag: dependent pickup dims")
	equal(rows[2]:GetAlpha(), 1, "drag: independent town stays")
	rows[2].mouseOver = true
	rows[3]:GetScript("OnDragStop")(rows[3])
	rows[2].mouseOver = false
	Redraw(h)
	equal(h.cursor, nil, "drag: cursor reset")
	equal(ns.Route().steps[1].key, second, "drag: the sooner town stays first")
	equal(ns.Route().steps[2].key, third, "drag: the objective moved to second")
	rows = StepRows(h, window)
	rows[1]:GetScript("OnDragStart")(rows[1])
	rows[2].mouseOver = true
	rows[1]:GetScript("OnDragStop")(rows[1])
	rows[2].mouseOver = false
	equal(ns.Route().steps[1].key, second, "drag: refused drop preserves order")
	equal(Texts(h)[L.ORDER_CUSTOM], 1, "custom order: card tag")
	h.Click(rows[1], "RightButton")
	equal(h.MenuLines()[#h.MenuLines()], "button: " .. L.ORDER_RESET, "custom order: menu reset")
	local reset = Visible(h, window, function(frame)
		return frame.text == L.ORDER_RESET
	end)[1]
	h.Click(reset)
	Redraw(h)
	equal(ns.Order.IsCustom(), false, "window reset clears custom order")
	equal(Texts(h)[L.YOUR_CHOICE], 1, "reset: retains the player's choice")

	ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	local panelRows = StepRows(h, panel)
	equal(#panelRows >= 3, true, "panel: the rows")
	panelRows[2]:GetScript("OnDragStart")(panelRows[2])
	equal(panelRows[3]:GetAlpha(), 0.35, "panel drag: dependent objective dims")
	equal(panelRows[1]:GetAlpha(), 1, "panel drag: independent town stays")
	panelRows[1].mouseOver = true
	panelRows[2]:GetScript("OnDragStop")(panelRows[2])
	panelRows[1].mouseOver = false
	Redraw(h)
	equal(ns.Route().steps[1].key, second, "panel drag: applied")
	equal(Texts(h, panel)[L.ORDER_CUSTOM], 1, "panel: custom order line")
	h.Hover(panelRows[1])
	equal(h.tooltip[#h.tooltip - 1], "instruction: " .. L.ORDER_DRAG, "panel: drag instruction")
	equal(h.tooltip[#h.tooltip], "instruction: " .. L.SPF_MISSING, "panel: then the Shortest Path hint")
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
		equal(texts[giver.text], nil, "main page keeps the town checklist in its details")
	end
	local ticks = Visible(h, window, function(frame)
		return frame.Tick ~= nil
	end)
	equal(#ticks, 0, "main page leaves room for upcoming actions")

	local open
	for _, giver in ipairs(town.checklist) do
		if not giver.done then
			open = giver
			break
		end
	end
	h.Click(rows[1], "RightButton")
	local skip
	for _, entry in ipairs(h.menu.entries) do
		skip = entry.text == L.TOWN_SKIP_GIVER and entry or skip
	end
	equal(#skip.entries, #town.checklist - 2, "checklist: only remaining givers in menu")
	skip.entries[1].onClick()
	h.flush()
	equal(ns.Prefs().skipped[ns.Model.GiverSkip(town, open.key)], true, "checklist: menu skips the actual giver")

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
	equal(ring.Badge:GetWidth(), 16, "ring: badge retains its readable size")
	local point, _, _, x, y = ring.Badge:GetPoint(1)
	-- Centred in its square, which hangs 4 past the ring's lower right.
	equal(point, "CENTER", "ring: badge is centred at the corner")
	equal(x, -4, "ring: badge horizontal offset")
	equal(y, 4, "ring: badge vertical offset")
	equal(ring.hitRectInsets[4], -4, "ring: the badge takes clicks")
	equal(ring.More, nil, "ring: icons only in the corner")
	local route = h.ns.Route().steps
	local revisit
	for _, pin in ipairs(pins) do
		revisit = (pin.visits and #pin.visits > 1 and pin.visits[1].step.hub == "1413:392") and pin or revisit
	end
	equal(revisit ~= nil, true, "ring: Ratchet visited twice")
	equal(revisit.visits[1].step.key ~= revisit.visits[2].step.key, true, "ring: two distinct visits share the ring")
	equal(revisit.More, nil, "ring: no +1 text")
	equal(revisit.Badge:IsShown(), true, "ring: shared stops keep their kind")
	local visitsCount = 0
	for _, pin in ipairs(pins) do
		visitsCount = visitsCount + #(pin.visits or {})
	end
	equal(visitsCount, #route, "ring: every visit belongs to one ring")
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
	local frame = h.G.CreateFrame("Frame")
	local texture = h.ns.Overview.CreateBadge(frame, frame, 14, 3)
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
	-- Each objective kind has its own icon; mixed work keeps the objective mark.
	local quests = h.ns.Data.quests
	local saved = { quests[1], quests[2] }
	quests[1] = { kinds = { [0] = "monster", [1] = "item", [2] = "object", [3] = "event" } }
	quests[2] = { kinds = { [0] = "monster" } }
	for _, case in ipairs({
		{ { { id = 1, slot = 0 }, { id = 2, slot = 0 } }, "battlemaster", "kill" },
		{ { { id = 1, slot = 1 } }, "Interface\\Cursor\\Pickup", "collect" },
		{ { { id = 1, slot = 2 } }, "Interface\\Cursor\\Interact", "use" },
	}) do
		h.ns.Overview.SetVerbIcon(texture, { verb = "objective", objectives = case[1] })
		equal(case[3] == "kill" and texture:GetAtlas() or texture.file, case[2], "badge: an objective to " .. case[3])
		equal(texture:IsShown(), true, "badge: visible")
	end
	for _, case in ipairs({
		{ { { id = 1, slot = 0 }, { id = 1, slot = 1 } }, "mixed work" },
		{ { { id = 1, slot = 3 } }, "a place to reach" },
		{ { { id = 1, slot = 9 } }, "an unknown slot" },
	}) do
		h.ns.Overview.SetVerbIcon(texture, { verb = "objective", objectives = case[1] })
		equal(texture:GetAtlas(), "questobjective", "badge: " .. case[2] .. " keeps the objective's mark")
	end
	quests[1], quests[2] = saved[1], saved[2]
	h.ns.Overview.SetVerbIcon(texture, {})
	equal(texture:IsShown(), false, "badge: hidden without a verb")
	clean(h, "badge kinds")
end

print(("guide_ui_spec: %d checks passed"):format(checks))
