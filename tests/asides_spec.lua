-- Run from the repository root: luajit tests/asides_spec.lua
-- The asides channel (Asides.lua, docs/design.md §2.11) through tests/harness.lua: providers, one aside per surface,
-- Skip, Not interested, Go, and the tracker's one line while no journey is chosen.
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

-- ui_spec's level-18 orc shaman in The Barrens, the carry card chosen unless `charDB` says otherwise.
local function Load(spf, charDB)
	return harness.load({
		spf = spf or nil,
		charDB = charDB or { journey = "carry" },
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
		},
	})
end

-- A provider the spec answers for; `calls` counts the asks.
local function Provider(h, aside)
	local provider = { aside = aside, calls = 0 }
	h.ns.Asides.Register(function()
		provider.calls = provider.calls + 1
		return provider.aside
	end)
	return provider
end

-- Step 1's travel frame, where the providers are asked.
local function Settle(h)
	h.ns.Invalidate()
	h.flush()
end

local function Opened(h)
	h.ns.OpenPanel()
	Settle(h)
end

-- The aside's line above the cards, while it shows.
local function Line(h)
	return h.Find(function(frame)
		return frame.Skip ~= nil and frame.Icon ~= nil and frame:IsVisible()
	end)
end

local A = { key = "a", text = "A thing to do", icon = "class" }
local B = { key = "b", text = "Another thing", icon = "profession" }

-- One aside for each surface, the first provider's; the harness has no Tweaks Forever, so the trainer gives none.
do
	local h = Load(false)
	Provider(h, A)
	Provider(h, B)
	Opened(h)
	local lines = Line(h)
	equal(#lines, 1, "one line in the guide")
	equal(lines[1].Text:GetText(), A.text, "the first provider's")
	equal(lines[1].Icon:GetAtlas(), A.icon, "with its icon")
	local _, _, _, _, y = lines[1]:GetPoint(1)
	equal(y, 0, "above the cards")
	local step = h.ns.Route().steps[1]
	same(h.tracker.layoutOrder, { "aside", step.key }, "one line in the tracker, above the chosen journey's step")
	equal(h.tracker.liveBlocks.aside.header, A.text, "the same aside")
	equal(#h.tracker.liveBlocks.aside.order, 0, "one line: the header alone")

	-- Skip for now, from the line's own button: the next provider's shows, and the next session has it again.
	h.Click(lines[1].Skip)
	h.flush()
	equal(Line(h)[1].Text:GetText(), B.text, "skip: the next aside")
	equal(h.tracker.liveBlocks.aside.header, B.text, "skip: in the tracker too")
	local again = Load(false, h.G.AdventureGuideForeverCharDB)
	Provider(again, A)
	Settle(again)
	equal(again.ns.Asides.Current().key, "a", "skip: for this session only")
	clean(again, "skip, next session")

	-- Not interested, from the tracker's menu: kept for this character.
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks.aside, "RightButton")
	same(
		h.MenuLines(),
		{ "title: " .. B.text, "button: Skip for now", "button: Not interested" },
		"menu: no Go without a place"
	)
	equal(h.menu.tag, "MENU_ADVENTURE_GUIDE_FOREVER_ASIDE", "menu: its tag")
	h.menu.entries[3].onClick()
	h.flush()
	equal(#Line(h), 0, "declined: no line in the guide")
	same(h.tracker.layoutOrder, { step.key }, "declined: nor in the tracker")
	equal(h.G.AdventureGuideForeverCharDB.asides.b, B.text, "declined: saved per character with its text")

	-- The cog brings it back, by the text its provider gives now (a trainer's count moves on).
	local later = Load(false, h.G.AdventureGuideForeverCharDB)
	local B2 = { key = "b", text = "Another thing, since", icon = B.icon }
	Provider(later, B2)
	Opened(later)
	equal(later.ns.Asides.Current(), nil, "declined: still after a reload")
	local cog = later.Find(function(frame)
		return frame.stockTemplate == "UIPanelIconDropdownButtonTemplate"
	end)[1]
	local menu = later.OpenMenu(cog)
	local submenu = menu.entries[#menu.entries - 1]
	same(later.MenuLines(submenu), { "button: Show again: " .. B2.text }, "cog: " .. submenu.text)
	equal(submenu.text, "Not interested (1)", "cog: counted")
	submenu.entries[1].onClick()
	later.flush()
	equal(later.ns.Asides.Current().key, "b", "cog: shown again")
	equal(later.G.AdventureGuideForeverCharDB.asides.b, nil, "cog: forgotten")
	menu = later.OpenMenu(cog)
	equal(menu.entries[#menu.entries - 1].text, later.ns.L.MENU_TRACKER, "cog: no submenu with none turned down")
	clean(later, "declined, next session")

	-- A search holds the guide: no line over its results.
	local search = h.Find(function(frame)
		return frame.stockTemplate == "SearchBoxTemplate"
	end)[1]
	h.ns.Asides.Restore("b")
	h.flush()
	equal(#Line(h), 1, "restored")
	h.Type(search, "Call of")
	h.flush()
	equal(#Line(h), 0, "search: no line")
	clean(h, "asides")
end

-- Providers are asked out of combat only, and the views redraw only when what is shown changes.
do
	local h = Load(false)
	local provider = Provider(h, A)
	local heard = 0
	h.ns.Asides.OnChange(function()
		heard = heard + 1
	end)
	Settle(h)
	equal(heard, 1, "change: the first answer")
	Settle(h)
	equal(heard, 1, "change: the same answer is not news")
	h.SetCombat(true)
	local calls = provider.calls
	provider.aside = B
	h.ns.Asides.Refresh()
	equal(provider.calls, calls, "combat: nothing asked")
	equal(h.ns.Asides.Current().key, "a", "combat: the last answer stands")
	h.SetCombat(false)
	h.ns.Asides.Refresh()
	equal(h.ns.Asides.Current().key, "b", "combat over: asked again")
	equal(heard, 2, "change: a new answer is")
	provider.aside = nil
	h.ns.Asides.Refresh()
	equal(h.ns.Asides.Current(), nil, "change: none")
	equal(heard, 3, "change: and its going")
	clean(h, "change")
end

-- A place from the data: Go takes the player there, as a step's Go does; without one a click goes nowhere.
for _, spf in ipairs({ false, "v1" }) do
	local label = "place, " .. (spf or "no Shortest Path")
	local h = Load(spf)
	local finish = h.ns.Data.quests[845].finish
	local provider = Provider(h, { key = "p", text = "Somewhere to be", icon = "class" })
	Opened(h)
	local starts = function()
		return (h.spf and h.spf.NavigateRoute or 0) + h.counts.SetUserWaypoint
	end
	local before = starts()
	h.Click(Line(h)[1])
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks.aside, "LeftButton")
	h.flush()
	equal(starts(), before, label .. ": no place, nowhere to go")
	provider.aside = { key = "p", text = "Somewhere to be", icon = "class", place = finish }
	Settle(h)
	h.Click(Line(h)[1], "RightButton")
	equal(h.MenuLines()[2], "button: Go", label .. ": the menu has Go")
	h.Click(Line(h)[1])
	h.flush()
	equal(starts(), before + 1, label .. ": a click goes there")
	if spf then
		equal(#h.spfRoute.stops, 1, label .. ": one stop")
		equal(h.spfRoute.stops[1].title, finish.name, label .. ": named for the place")
	else
		equal(h.waypoint.position.x .. " " .. h.waypoint.position.y, finish.x .. " " .. finish.y, label .. ": there")
	end
	equal(h.ns.Prefs().guided, nil, label .. ": not the chosen journey's route")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks.aside, "LeftButton")
	h.flush()
	equal(starts(), before + 2, label .. ": so does the tracker's")
	clean(h, label)
end

-- No journey chosen (design §2.5): the tracker's one line is the aside, else the top story's hook; no step shows.
do
	local h = Load(false, {})
	local provider = Provider(h, A)
	Settle(h)
	equal(h.ns.Route().chosen, false, "ambient: none chosen")
	same(h.tracker.layoutOrder, { "aside" }, "ambient: the aside alone")
	provider.aside = nil
	Settle(h)
	same(h.tracker.layoutOrder, { "hook" }, "ambient: else the hook")
	local story
	for _, journey in ipairs(h.ns.Route().journeys) do
		story = story or (journey.kind == "story" and journey)
	end
	equal(
		h.tracker.liveBlocks.hook.header,
		story.title .. " · " .. (story.reason or story.subline),
		"ambient: its hook"
	)
	-- Its menu is the tracker's, with no step.
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks.hook, "RightButton")
	equal(h.MenuLines()[1], "title: " .. h.ns.TITLE, "ambient: the tracker's menu")
	h.ns.Choose(story.key)
	h.flush()
	same(h.tracker.layoutOrder, { h.ns.Route().steps[1].key }, "ambient: a choice brings the step")
	h.ns.Choose(nil)
	h.flush()
	same(h.tracker.layoutOrder, { "hook" }, "ambient: none again, the hook again")
	clean(h, "ambient")
end

print(("asides_spec: %d checks passed"):format(checks))
