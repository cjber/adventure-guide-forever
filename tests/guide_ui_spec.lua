-- Run from the repository root: luajit tests/guide_ui_spec.lua
-- The window's PvP and Completion tabs, Go to entrance, Today's overflow, the session picker, reordering, the step
-- kinds' badges, a town's checklist and a revisited place's ring (docs/design.md §2.9, §2.19, §2.20), through the
-- harness. Each case sets the model slice's answers on ns itself (Session, Order, PvP, Providers), so it reads the
-- same before and after that slice merges. The map tab, drag feel, the menus' look and the pins' art are /reload
-- checks.
local harness = dofile("tests/ui_stubs.lua") -- TEMPORARY: tests/harness.lua once guide batch 4 merges
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

-- The model slice's answers, set by each case: `fake.custom`, `fake.refuse[to]`, `fake.info`, `fake.minutes`,
-- `fake.pvp`, `fake.legacy`, `fake.completion`, `fake.entrance`; every call the UI makes is recorded in `fake.calls`.
local function Fake(h)
	local ns = h.ns
	local fake = { calls = {}, refuse = {}, info = { minutes = 0, pending = false, empty = false, trimmed = false } }
	local function Record(...)
		fake.calls[#fake.calls + 1] = table.concat({ ... }, " ")
	end
	ns.Order.CanMove = function(from, to)
		return ns.Route().chosen and from ~= to and to >= 1 and to <= #ns.Route().steps and not fake.refuse[to]
	end
	ns.Order.Move = function(from, to)
		Record("Move", from, to)
	end
	ns.Order.IsCustom = function()
		return fake.custom == true
	end
	ns.Order.Reset = function()
		Record("Reset")
	end
	ns.Order.SkipGiver = function(step, giver)
		Record("SkipGiver", step, giver)
	end
	ns.Session.Get = function()
		return fake.minutes or 0
	end
	ns.Session.Set = function(minutes)
		Record("Session", minutes)
	end
	ns.Session.Info = function()
		return fake.info
	end
	ns.PvP.Data = function()
		return fake.pvp or { rank = { state = "unavailable" }, battlegrounds = {}, available = false }
	end
	ns.PvP.Go = function(id)
		Record("PvP", id)
	end
	ns.Providers.LegacyState = function()
		return fake.legacy or "missing"
	end
	ns.Providers.Completion = function()
		return fake.completion or { state = fake.legacy or "missing", zones = {} }
	end
	ns.Providers.NavigateCompletion = function(map, key)
		Record("Completion", map, key)
	end
	ns.Providers.DungeonEntrance = function()
		local entrance = fake.entrance or "missing"
		if type(entrance) == "table" then
			return entrance
		end
		return nil, entrance
	end
	ns.Providers.GoToEntrance = function(instance)
		Record("Entrance", instance)
	end
	ns.Asides.Go = function(aside)
		Record("Aside", aside.key)
	end
	return fake
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
	local h = Load()
	local ns, L = h.ns, h.ns.L
	local fake = Fake(h)
	fake.pvp = {
		available = true,
		rank = { state = "ranked", level = 3, earned = 1200, threshold = 3000, reward = { level = 4, text = "Tabard" } },
		battlegrounds = {
			{ id = 1, name = "Warsong Gulch", level = 10, npc = 7, place = { map = 1454, x = 0.5, y = 0.5 } },
			{ id = 2, name = "Arathi Basin", level = 20 },
		},
	}
	local window = Open(h, 3)
	equal(window.selectedTab, 3, "pvp: the third tab")
	equal(window.Tabs[3]:GetText(), L.TAB_PVP, "pvp: its label")
	local texts = Texts(h)
	equal(texts[L.PVP_RANK:format(3)], 1, "pvp: the rank")
	equal(texts[L.PVP_RANK_POINTS:format(1200, 3000)], 1, "pvp: its points")
	equal(texts[L.PVP_NEXT_REWARD:format(4, "Tabard")], 1, "pvp: the next reward")
	equal(texts["Warsong Gulch"], 1, "pvp: a battleground")
	equal(texts[L.PVP_BATTLEGROUND_LEVEL:format(10)], 1, "pvp: from its level")
	equal(texts[L.PVP_BATTLEGROUND_LEVEL:format(20) .. L.SEPARATOR .. L.PVP_NO_BATTLEMASTER], 1, "pvp: no battlemaster")
	local rows = Visible(h, window, function(frame)
		return frame.battle ~= nil
	end)
	equal(#rows, 2, "pvp: a row a battleground")
	for _, row in ipairs(rows) do
		h.Click(row)
	end
	same(fake.calls, { "PvP 1" }, "pvp: only the battleground with a battlemaster goes")
	h.Hover(rows[1].battle.place and rows[1] or rows[2])
	equal(h.tooltip[#h.tooltip], "instruction: " .. L.PVP_GO_BATTLEMASTER, "pvp: the row's click line")

	fake.pvp = { available = true, rank = { state = "capped", level = 14 }, battlegrounds = {} }
	Redraw(h)
	texts = Texts(h)
	equal(texts[L.PVP_CAPPED], 1, "capped: says so")
	equal(texts[L.PVP_RANK_POINTS:format(0, 0)], nil, "capped: no points")
	equal(texts[L.PVP_NO_BATTLEGROUNDS], 1, "capped: no battlegrounds at the level")

	fake.pvp = nil
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
	local h = Load()
	local L = h.ns.L
	local fake = Fake(h)
	local window = Open(h, 4)
	equal(window.selectedTab, 4, "legacy missing: the tab still opens")
	equal(window.Tabs[4].normalFont, "GameFontDisableSmall", "legacy missing: its label greys")
	equal(Texts(h)[L.LEGACY_MISSING], 1, "legacy missing: the page says to install it")
	h.Hover(window.Tabs[4])
	equal(h.tooltip[#h.tooltip], "normal: " .. L.LEGACY_MISSING, "legacy missing: and the tab's tooltip")

	fake.legacy = "outdated"
	Redraw(h)
	equal(Texts(h)[L.LEGACY_OUTDATED], 1, "legacy outdated: says to update it")

	fake.legacy = "ready"
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
	fake.completion =
		{ state = "ready", zones = { Zone(1413, "The Barrens", 7), Zone(1442, "Stonetalon Mountains", 1) } }
	Redraw(h)
	local texts = Texts(h)
	equal(window.Tabs[4].normalFont, "GameFontNormalSmall", "ready: the label is gold")
	equal(texts["The Barrens"] ~= nil, true, "ready: the player's zone featured")
	equal(texts[L.COMPLETION_COUNTS:format(7, 20)], 1, "ready: its overall count")
	equal(texts[L.COMPLETION_PENDING:format(1)] ~= nil, true, "ready: pending counted apart")
	equal(texts["Explore the Crossroads"], 1, "ready: a target")
	equal(texts[L.COMPLETION_COUNTS:format(2, 5) .. L.SEPARATOR .. L.COMPLETION_NO_LOCATION], 1, "ready: no place")
	local rows = Visible(h, window, function(frame)
		return frame.target ~= nil
	end)
	for _, row in ipairs(rows) do
		h.Click(row)
	end
	same(fake.calls, { "Completion 1413 explore:1" }, "ready: only a target with a place goes")
	local other = Visible(h, window, function(frame)
		return frame.zone ~= nil and frame.zone.map == 1442 and frame.target == nil
	end)[1]
	equal(other ~= nil, true, "ready: the next zone's card")
	h.Click(other)
	h.flush()
	equal(Texts(h)[L.COMPLETION_COUNTS:format(1, 20)], 1, "ready: its click features it")

	fake.completion = { state = "ready", zones = {} }
	Redraw(h)
	equal(Texts(h)[L.COMPLETION_EMPTY], 1, "ready, no zones: says so")
	clean(h, "completion")
end

--[[ Go to entrance ]]

do
	local h = Load({ charDB = { journey = "dungeon:389", dungeons = true } })
	local L = h.ns.L
	local fake = Fake(h)
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
		fake.entrance = case[1]
		Redraw(h)
		local button = Entrance()
		equal(button ~= nil, true, case[1] .. ": the dungeon card has Go to entrance")
		equal(button:IsEnabled(), false, case[1] .. ": greyed")
		equal(Texts(h)[case[2]], 1, case[1] .. ": the note says why")
	end
	fake.entrance = { map = 1411, x = 0.52, y = 0.49 }
	Redraw(h)
	equal(Entrance():IsEnabled(), true, "ready: enabled")
	equal(Texts(h)[L.TWEAKS_MISSING], nil, "ready: no note")
	h.Click(Entrance())
	same(fake.calls, { "Entrance 389" }, "ready: a click goes to the entrance")
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
				{ key = "mount", text = "Save for a mount", icon = "class" },
			}) do
				each.ns.Asides.Register(function()
					return extra
				end)
			end
		end,
	})
	local L = h.ns.L
	local fake = Fake(h)
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
	same(fake.calls, { "Aside mount" }, "overflow: an entry goes as its chip would")
	h.ns.Asides.Decline(all[5])
	h.ns.Asides.Decline(all[4])
	h.flush()
	h.ns.Window.Refresh()
	equal(more:IsShown(), false, "four fit: no overflow")
	clean(h, "today")
end

--[[ The session picker ]]

do
	local h = Load()
	local L = h.ns.L
	local fake = Fake(h)
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
	same(fake.calls, { "Session 30" }, "session: a pick sets it")
	fake.minutes = 30
	fake.info = { minutes = 30, seconds = 1490, pending = false, empty = false, trimmed = true }
	Redraw(h)
	equal(picker.Text:GetText(), L.SESSION_MINUTES:format(30), "session: the pick shows")
	equal(Texts(h)[L.SESSION_ABOUT:format(25)], 1, "session: About 25 min")
	fake.info = { minutes = 30, pending = true, empty = false, trimmed = false }
	Redraw(h)
	equal(Texts(h)[L.SESSION_PENDING], 1, "session: estimating")
	fake.info = { minutes = 15, pending = false, empty = true, trimmed = true }
	Redraw(h)
	equal(Texts(h)[L.SESSION_EMPTY], 1, "session empty: says so")
	equal(#StepRows(h, window), 0, "session empty: no steps")
	h.ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	equal(Texts(h, panel)[L.SESSION_EMPTY], 1, "session empty: the panel says so too")
	clean(h, "session")
end

--[[ Reordering: the menu, the drag, the tag and the way back ]]

do
	local h = Load()
	local ns, L = h.ns, h.ns.L
	local fake = Fake(h)
	local window = Open(h)
	local rows = StepRows(h, window)
	equal(#rows >= 3, true, "order: the chosen story's rows")
	h.Click(rows[2], "RightButton")
	local lines = h.MenuLines()
	local n = #lines
	same({ unpack(lines, n - 3, n) }, {
		"divider",
		"button: " .. L.ORDER_NEXT,
		"button: " .. L.ORDER_SOONER,
		"button: " .. L.ORDER_LATER,
	}, "order: the step menu's moves")
	local entries
	fake.refuse[3] = true
	h.Click(rows[2], "RightButton")
	entries = h.menu.entries
	equal(entries[#entries]:IsEnabled(), false, "order: a move the order refuses is greyed")
	entries[#entries - 1].onClick()
	same(fake.calls, { "Move 2 1" }, "order: Do this sooner")
	h.Click(rows[1], "RightButton")
	entries = h.menu.entries
	equal(entries[#entries - 1]:IsEnabled(), false, "order: step 1 goes no sooner")
	equal(Texts(h)[L.ORDER_RESET], nil, "suggested order: no way back")
	equal(Texts(h)[L.SUGGESTED], 1, "suggested order: the card's tag")

	-- The drag: the stock move cursor, rows it can't land on dimmed, and the move on release.
	fake.calls = {}
	rows[1]:GetScript("OnDragStart")(rows[1])
	equal(h.cursor, "Interface\\CURSOR\\UI-Cursor-Move", "drag: the move cursor")
	equal(rows[3]:GetAlpha(), 0.35, "drag: a refused row dims")
	equal(rows[2]:GetAlpha(), 1, "drag: a row it can land on stays")
	rows[2].mouseOver = true
	rows[1]:GetScript("OnDragStop")(rows[1])
	rows[2].mouseOver = false
	equal(h.cursor, nil, "drag: the cursor back")
	same(fake.calls, { "Move 1 2" }, "drag: dropped on row 2")
	equal(rows[3]:GetAlpha(), 1, "drag: the dim gone")
	fake.calls = {}
	rows[1]:GetScript("OnDragStart")(rows[1])
	rows[3].mouseOver = true
	rows[1]:GetScript("OnDragStop")(rows[1])
	rows[3].mouseOver = false
	same(fake.calls, {}, "drag: a refused row takes nothing")

	fake.custom = true
	Redraw(h)
	local texts = Texts(h)
	equal(texts[L.ORDER_CUSTOM], 1, "custom order: the card's tag")
	local reset = Visible(h, window, function(frame)
		return frame.text == L.ORDER_RESET
	end)[1]
	equal(reset ~= nil, true, "custom order: the way back")
	h.Click(reset)
	same(fake.calls, { "Reset" }, "custom order: back to suggested")
	h.Click(rows[1], "RightButton")
	equal(h.MenuLines()[#h.MenuLines()], "button: " .. L.ORDER_RESET, "custom order: the menu's way back")

	-- The panel's rows the same.
	ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	local panelRows = StepRows(h, panel)
	equal(#panelRows >= 3, true, "panel: the rows")
	equal(Texts(h, panel)[L.ORDER_CUSTOM], 1, "panel: the order line")
	fake.calls = {}
	panelRows[1]:GetScript("OnDragStart")(panelRows[1])
	equal(panelRows[3]:GetAlpha(), 0.35, "panel drag: a refused row dims")
	panelRows[2].mouseOver = true
	panelRows[1]:GetScript("OnDragStop")(panelRows[1])
	same(fake.calls, { "Move 1 2" }, "panel drag: dropped on row 2")
	h.Hover(panelRows[1])
	equal(h.tooltip[#h.tooltip], "instruction: " .. L.ORDER_DRAG, "panel: the row says it drags")
	local reset2 = Visible(h, panel, function(frame)
		return frame.text == L.ORDER_RESET
	end)[1]
	fake.calls = {}
	h.Click(reset2)
	same(fake.calls, { "Reset" }, "panel: the way back")
	fake.custom = false
	Redraw(h)
	equal(Texts(h, panel)[L.ORDER_CUSTOM], nil, "panel: no order line once suggested")
	clean(h, "order")
end

--[[ The kinds' badges and a town's checklist ]]

local VERBS = { "town", "pickup", "objective", "turnin", "trainer", "battlemaster" }
local CHECKLIST = {
	{ key = "sergra", name = "Sergra Darkthorn", text = "Sergra Darkthorn: pick up 1, turn in 1", done = true },
	{ key = "thork", name = "Thork", text = "Thork: pick up 2, turn in 0", done = false },
	{ key = "kargal", name = "Kargal Battlescar", text = "Kargal Battlescar: pick up 1, turn in 0", skipped = true },
}

local function Decorate(route)
	for index, step in ipairs(route.steps) do
		step.verb = VERBS[index] or "objective"
		if index == 1 then
			step.pickups, step.checklist = { 870 }, CHECKLIST
		end
	end
end

do
	local h = Load({ decorate = Decorate, db = { showMapPins = true } })
	local L = h.ns.L
	local fake = Fake(h)
	local window = Open(h)
	local rows = StepRows(h, window)
	local expected = { "QuestNormal", "QuestNormal", "questobjective" }
	for index, row in ipairs(rows) do
		if expected[index] then
			equal(row.Kind:GetAtlas(), expected[index], "badge: window row " .. index)
			equal(row.Kind:IsShown(), true, "badge: shown " .. index)
		end
	end
	local texts = Texts(h)
	for _, giver in ipairs(CHECKLIST) do
		equal(texts[giver.text], 1, "checklist: " .. giver.key .. " under the town")
	end
	local ticks = Visible(h, window, function(frame)
		return frame.Tick ~= nil
	end)
	table.sort(ticks, function(a, b)
		return a.Text.text < b.Text.text
	end)
	equal(ticks[2].Tick:GetAtlas(), "UI-QuestTracker-Tracker-Check", "checklist: done ticked")
	equal(ticks[3].Tick:GetAtlas(), "UI-QuestTracker-Objective-Nub", "checklist: open has the nub")
	equal(ticks[1].Tick:GetAlpha(), 0.4, "checklist: skipped fades")
	h.Click(rows[1], "RightButton")
	local skip
	for _, entry in ipairs(h.menu.entries) do
		skip = entry.text == L.TOWN_SKIP_GIVER and entry or skip
	end
	equal(skip ~= nil, true, "checklist: the town's Skip this giver")
	equal(#skip.entries, 1, "checklist: only the giver still open")
	skip.entries[1].onClick()
	same(fake.calls, { "SkipGiver town:349 thork" }, "checklist: a skip names the giver")

	h.ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	local panelRows = StepRows(h, panel)
	for index, verb in ipairs(VERBS) do
		local row = panelRows[index]
		if row then
			local atlas = row.Kind:GetAtlas()
			if verb == "trainer" then
				equal(row.Kind.file, "Interface\\Minimap\\Tracking\\Class", "badge: the trainer's")
			else
				local want = ({
					town = "QuestNormal",
					pickup = "QuestNormal",
					objective = "questobjective",
					turnin = "QuestTurnin",
					battlemaster = "battlemaster",
				})[verb]
				equal(atlas, want, "badge: panel row " .. index)
			end
		end
	end
	local panelChecks = Visible(h, panel, function(frame)
		return frame.Tick ~= nil
	end)
	equal(#panelChecks, 3, "checklist: the panel's")
	local _, _, _, _, y1 = panelRows[1]:GetPoint(1)
	local _, _, _, _, y2 = panelRows[2]:GetPoint(1)
	equal(y1 - y2 > 30 + 3 * 14 - 1, true, "checklist: row 2 below the town's lines")

	-- The rings: the same badge, and a place the route comes back to keeps one ring listing its visits.
	h.providers[1]:RefreshAllData()
	local pins = h.pins.AdventureGuideForeverPinTemplate
	local ring = pins[1]
	equal(ring.Badge:GetAtlas(), "QuestNormal", "ring: the kind's badge")
	equal(ring.Badge:GetWidth(), 16, "ring: badge 16 wide, as Shortest Path's")
	local point, _, _, x, y = ring.Badge:GetPoint(1)
	equal(("%s %d %d"):format(point, x, y), "BOTTOMRIGHT 4 -4", "ring: hung past the ring")
	equal(ring.hitRectInsets[4], -4, "ring: the badge takes clicks")
	equal(ring.More:IsShown(), false, "ring: a single visit has no count")
	local route = h.ns.Route().steps
	local revisit
	for _, pin in ipairs(pins) do
		revisit = (pin.visits and #pin.visits > 1) and pin or revisit
	end
	equal(revisit ~= nil, true, "ring: Ratchet visited twice")
	equal(revisit.More:GetText(), L.STOP_MORE:format(1), "ring: +1")
	equal(#pins, #route - 1, "ring: one ring for both visits")
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

print(("guide_ui_spec: %d checks passed"):format(checks))
