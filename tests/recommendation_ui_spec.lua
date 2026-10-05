-- Run from the repository root: luajit tests/recommendation_ui_spec.lua
-- The window's Next tab (UI/WindowNext.lua) through tests/harness.lua: what it draws from ns.Recommendations.Current,
-- its four-item limit, the focus buttons, the Browse buttons, an empty and a loading page, and a click's trip through
-- the real Recommendations.Act, which refuses an item the route no longer holds. What the harness cannot reach is a
-- /reload check.
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

local Texts = dofile("tests/ui_helpers.lua").Texts

local function Empty(h)
	return h.Find(function(frame)
		return frame.NextEmpty ~= nil
	end)[1].NextEmpty
end

local function Load()
	return harness.load({
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		},
	})
end

-- The window on its Next tab.
local function OpenNext(h)
	h.ns.OpenWindow()
	h.flush()
	for index, tab in ipairs(h.ns.Window.Tabs()) do
		if tab.key == "next" then
			h.ns.Window.Select(index)
		end
	end
	h.flush()
	return h.G.AdventureGuideForeverWindow
end

local function Item(key, extra)
	local item = { key = key, title = "Title " .. key, reason = "Reason " .. key, icon = "adventureguide-ring" }
	for field, value in pairs(extra or {}) do
		item[field] = value
	end
	return item
end

-- `items` as what Current answers, counting its reads.
local function Stub(h, items)
	local state = { reads = 0, items = items }
	h.ns.Recommendations.Current = function()
		state.reads = state.reads + 1
		return state.items
	end
	return state
end

--[[ The page: one lead, three others, never more ]]

do
	for _, case in ipairs({ { false, 6 }, { "journeys", 1 }, { "dungeons", 5 }, { "unknown", 1 } }) do
		local h = harness.load({ db = { window = { tab = case[1] or nil } } })
		h.ns.OpenWindow()
		h.flush()
		equal(h.G.AdventureGuideForeverWindow.selectedTab, case[2], "saved tab " .. tostring(case[1]))
		clean(h, "saved tab")
	end
end

do
	local h = Load()
	local L = h.ns.L
	local state = Stub(h, {
		Item("lead", { journey = "one" }),
		Item("a", { aside = { place = { map = 1413, x = 0.5, y = 0.5 } } }),
		Item("b", { aside = {} }),
		Item("c", { journey = "two" }),
		Item("d", { journey = "three" }),
		Item("e", { journey = "four" }),
	})
	local window = OpenNext(h)
	clean(h, "open")
	equal(window.selectedTab, #h.ns.Window.Tabs(), "Next is the last tab")
	equal(window.Tabs[#window.Tabs]:GetText(), L.TAB_NEXT, "its label")
	local texts = Texts(h)
	equal(texts[L.NEXT_TITLE], 1, "the question")
	equal(texts[L.NEXT_WHY], 1, "Why this?")
	equal(texts[L.NEXT_ALTERNATIVES], 1, "the other things")
	equal(texts["Title lead"], 1, "the lead's task")
	equal(texts["Reason lead"], 1, "the lead's reason")
	equal(texts["Title c"], 1, "the third alternative")
	equal(texts["Title d"], nil, "no fourth alternative")
	equal(texts["Title e"], nil, "no fifth")
	equal(texts[L.NEXT_ADVICE], 1, "a text-only hint is advice")
	equal(texts[L.NEXT_BROWSE_JOURNEYS], 1, "Browse journeys")
	equal(texts[L.NEXT_BROWSE_DUNGEONS], 1, "Browse dungeons")
	for _, name in ipairs({ "AdventureGuideForeverNextAction", "AdventureGuideForeverNextRowAction1" }) do
		equal(h.G[name]:IsShown(), true, name .. " shown")
	end
	equal(h.G.AdventureGuideForeverNextRowAction2:IsShown(), false, "advice has no button")
	equal(Empty(h):IsShown(), false, "no empty line with suggestions")
	-- Every top-left anchored control ends inside the page (the harness lays nothing out, so by anchor and size).
	local Window = h.ns.Window
	for _, name in ipairs({
		"AdventureGuideForeverNextFocusbalanced",
		"AdventureGuideForeverNextRowAction1",
		"AdventureGuideForeverNextBrowsejourneys",
		"AdventureGuideForeverNextBrowsedungeons",
		"AdventureGuideForeverNextFocusdungeons",
	}) do
		local frame = h.G[name]
		if frame then
			local _, _, _, x, y = frame:GetPoint(1)
			local width, height = frame:GetSize()
			if frame:GetPoint(1) == "TOPLEFT" then
				equal(x + width <= Window.INSET_WIDTH - Window.RIGHT + 0.01, true, name .. " inside, x")
				equal(-y + height <= Window.INSET_HEIGHT - 12, true, name .. " inside, y")
			end
		end
	end
	equal(state.reads > 0, true, "drawn from Current")
	clean(h, "page")
end

--[[ Focus and Browse ]]

do
	local h = Load()
	Stub(h, { Item("lead") })
	local window = OpenNext(h)
	local R = h.ns.Recommendations
	equal(R.Focus(), "balanced", "balanced first")
	equal(h.G.AdventureGuideForeverNextFocusbalanced:IsEnabled(), false, "the focus in force is the pressed one")
	h.Click(h.G.AdventureGuideForeverNextFocusquests)
	equal(R.Focus(), "quests", "a focus button sets it")
	equal(h.G.AdventureGuideForeverNextFocusquests:IsEnabled(), false, "and becomes the pressed one")
	equal(h.G.AdventureGuideForeverNextFocusbalanced:IsEnabled(), true, "the old one is free")
	h.Click(h.G.AdventureGuideForeverNextBrowsedungeons)
	equal(h.G.AdventureGuideForeverDB.window.tab, "dungeons", "Browse dungeons jumps to the Dungeons tab")
	equal(window.selectedTab, 5, "the Dungeons tab is shown")
	h.ns.Window.Select(#h.ns.Window.Tabs())
	h.Click(h.G.AdventureGuideForeverNextBrowsejourneys)
	equal(window.selectedTab, 1, "Browse journeys jumps to the Journeys tab")
	clean(h, "focus and browse")
end

--[[ Empty and loading ]]

do
	local h = Load()
	local L = h.ns.L
	local state = Stub(h, {})
	h.ns.RouteSettled = function()
		return true
	end
	OpenNext(h)
	equal(Empty(h):GetText(), L.NEXT_EMPTY, "settled and nothing: the empty line")
	equal(h.G.AdventureGuideForeverNextCardInner:GetParent():IsShown(), false, "no card without a lead")
	h.ns.RouteSettled = function()
		return false
	end
	h.ns.Window.Refresh()
	equal(Empty(h):GetText(), L.NEXT_LOADING, "unsettled: the loading line")
	equal(state.reads > 1, true, "each refresh reads Current again")
	clean(h, "empty")
end

--[[ A click goes through the real Act, which refuses what the route no longer holds ]]

do
	local h = Load()
	local acted = 0
	local R = h.ns.Recommendations
	local act = R.Act
	R.Act = function(item)
		acted = acted + 1
		return act(item)
	end
	local state = Stub(h, { Item("gone", { journey = "no-such-journey" }) })
	h.ns.RouteSettled = function()
		return true
	end
	OpenNext(h)
	local before = h.ns.Prefs().guided
	local reads = state.reads
	h.Click(h.G.AdventureGuideForeverNextAction)
	equal(acted, 1, "the button acts through Recommendations.Act")
	equal(R.Act({ key = "gone", title = "x", reason = "y", icon = 1 }), false, "a stale item is refused")
	equal(h.ns.Prefs().guided, before, "and starts no guidance")
	equal(state.reads > reads, true, "the window redraws after the click")
	clean(h, "stale click")
end

do
	local h = Load()
	h.flush()
	local refreshes, settled = 0, true
	h.ns.RouteSettled = function()
		return settled
	end
	h.ns.Asides.Refresh = function()
		refreshes = refreshes + 1
	end
	h.ns.Window.Refresh = function() end
	h.fire("ZONE_CHANGED")
	h.fire("ZONE_CHANGED_INDOORS")
	equal(refreshes, 0, "district position is read after the events")
	h.flush()
	equal(refreshes, 1, "district events coalesce")
	settled = false
	h.fire("ZONE_CHANGED")
	h.flush()
	equal(refreshes, 1, "district changes never force a pending route")
	settled = true
	h.fire("PLAYER_REGEN_ENABLED")
	h.flush()
	equal(refreshes, 2, "leaving combat refreshes actions")
	clean(h, "district events")
end

print(("recommendation_ui_spec: %d checks passed"):format(checks))
