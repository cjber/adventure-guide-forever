-- Run from the repository root: luajit tests/window_spec.lua
-- The Adventure Guide window (Window.lua, WindowJourneys.lua, WindowProfessions.lua) through tests/harness.lua: its
-- tabs, how it opens, the key it offers once, what the Journeys tab draws from the route, and SkillUp Forever's
-- adapter present, missing and too old. What the harness cannot reach is a /reload check.
local harness = dofile("tests/ui_stubs.lua") -- TEMPORARY: tests/harness.lua once guide batch 4 merges
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

-- ui_spec's level-18 orc shaman in The Barrens, a fresh character with no card chosen unless `charDB` says so, and
-- whatever else `extra` adds (SkillUp Forever, key bindings, talents).
local function Load(extra)
	local options = {
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
	}
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	return harness.load(options)
end

-- Every text the window shows, from its dump: font strings and button labels.
local function Texts(h)
	local texts = {}
	for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverWindow, h.Describe)) do
		if entry.text then
			texts[entry.text] = (texts[entry.text] or 0) + 1
		end
	end
	return texts
end

local function Open(h)
	h.ns.OpenWindow()
	h.flush()
	return h.G.AdventureGuideForeverWindow
end

--[[ The tab registry and the frame ]]

do
	local h = Load()
	local L = h.ns.L
	clean(h, "load")
	equal(h.G.AdventureGuideForeverWindow, nil, "built on first open, not at load")
	local keys = {}
	for index, tab in ipairs(h.ns.Window.Tabs()) do
		keys[index] = tab.key
	end
	equal(table.concat(keys, ","), "journeys,professions,pvp,completion", "registry: one entry a tab, in TOC order")
	local window = Open(h)
	clean(h, "open")
	equal(window:IsShown(), true, "open: shown")
	equal(window.stockTemplate, "PortraitFrameTemplate", "a portrait frame")
	equal(window.TitleText:GetText(), h.ns.TITLE, "its title")
	equal(h.G.UISpecialFrames[1], "AdventureGuideForeverWindow", "Escape closes it")
	equal(#window.Tabs, 4, "a tab button a registered tab")
	equal(window.Tabs[1]:GetText(), L.TAB_JOURNEYS, "tab 1 label")
	equal(window.Tabs[2]:GetText(), L.TAB_PROFESSIONS, "tab 2 label")
	local point, relativeTo, relativePoint, x, y = window.Tabs[1]:GetPoint(1)
	equal(
		("%s %s %s %d %d"):format(point, relativeTo:GetName(), relativePoint, x, y),
		"TOPLEFT AdventureGuideForeverWindow BOTTOMLEFT 11 2",
		"tab 1 under the frame's bottom-left"
	)
	equal(select(2, window.Tabs[2]:GetPoint(1)), window.Tabs[1], "tab 2 follows tab 1")
	equal(window.selectedTab, 1, "Journeys first")
	equal(window.Tabs[1]:IsEnabled(), false, "the selected tab is disabled, as PanelTemplates_SelectTab does")
	h.Click(window.Tabs[2])
	equal(window.selectedTab, 2, "a click selects Professions")
	equal(h.G.AdventureGuideForeverDB.window.tab, "professions", "the tab is saved")
	clean(h, "tabs")

	-- The window remembers where it was left, and its tab, after a reload.
	h.G.AdventureGuideForeverDB.window.position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 40, y = -60 }
	local again = Load({ db = h.G.AdventureGuideForeverDB })
	local reopened = Open(again)
	equal(reopened.selectedTab, 2, "reload: the saved tab")
	local p, _, rp, px, py = reopened:GetPoint(1)
	equal(("%s %s %d %d"):format(p, rp, px, py), "TOPLEFT TOPLEFT 40 -60", "reload: the saved position")
	clean(again, "reload")
end

--[[ Opening: /agf, the addon compartment, the panel's header, the key ]]

do
	local h = Load()
	local L = h.ns.L
	h.Slash("")
	equal(h.G.AdventureGuideForeverWindow:IsShown(), true, "/agf opens the window")
	h.G.AdventureGuideForeverWindow:Hide()
	h.Slash("window")
	equal(h.G.AdventureGuideForeverWindow:IsShown(), true, "/agf window opens it")
	h.prints = {}
	h.Slash("help")
	equal(#h.prints, 3, "help: three lines")
	equal(h.prints[1]:find(L.HELP_OPEN, 1, true) ~= nil, true, "help: /agf opens the window")
	h.G.AdventureGuideForever_OnAddonCompartmentClick("AdventureGuideForever", "LeftButton")
	equal(h.G.AdventureGuideForeverWindow:IsShown(), false, "compartment left-click toggles it closed")
	h.G.AdventureGuideForever_OnAddonCompartmentClick("AdventureGuideForever", "LeftButton")
	equal(h.G.AdventureGuideForeverWindow:IsShown(), true, "and open")
	equal(h.map:IsShown(), false, "the map stays closed")
	h.G.AdventureGuideForever_OnAddonCompartmentClick("AdventureGuideForever", "RightButton")
	equal(h.map:IsShown() and h.G.AdventureGuideForeverPanel:IsShown(), true, "right-click opens the map panel")
	h.G.AdventureGuideForeverWindow:Hide()
	h.G.AdventureGuideForever_ToggleWindow()
	equal(h.G.AdventureGuideForeverWindow:IsShown(), true, "the binding's function toggles it")
	h.G.AdventureGuideForeverWindow:Hide()
	-- The panel's header: RedButton-Expand, "Open in window".
	local expand = h.Find(function(frame)
		return frame.normalAtlas == "RedButton-Expand"
	end)[1]
	equal(expand ~= nil, true, "the panel header's expand button")
	h.Hover(expand)
	equal(h.tooltip[1], "title: " .. L.OPEN_IN_WINDOW, "its tooltip")
	h.Click(expand)
	equal(h.G.AdventureGuideForeverWindow:IsShown(), true, "it opens the window")
	equal(h.G.BINDING_NAME_ADVENTUREGUIDEFOREVER_WINDOW, L.BINDING_TOGGLE_WINDOW, "the binding's name from ns.L")
	equal(h.G.BINDING_HEADER_ADVENTUREGUIDEFOREVER, h.ns.TITLE, "its header")
	clean(h, "openers")
end

--[[ The key: Shift-J once per account, only when free ]]

do
	local h = Load()
	equal(h.bindings["SHIFT-J"], "ADVENTUREGUIDEFOREVER_WINDOW", "free: Shift-J set")
	equal(h.savedBindings[1], 1, "saved to the current binding set")
	equal(h.G.AdventureGuideForeverDB.window.keyOffered, true, "offered once")
	-- The player clears it: the next login leaves it cleared.
	h.bindings["SHIFT-J"] = nil
	local again = Load({ db = h.G.AdventureGuideForeverDB })
	equal(again.bindings["SHIFT-J"], nil, "offered already: never set again")
	equal(#again.savedBindings, 0, "nothing saved")

	local taken = Load({ bindings = { ["SHIFT-J"] = "TOGGLEPETJOURNAL" } })
	equal(taken.bindings["SHIFT-J"], "TOGGLEPETJOURNAL", "taken: the player's binding stays")
	equal(#taken.savedBindings, 0, "taken: nothing saved")
	equal(taken.G.AdventureGuideForeverDB.window.keyOffered, true, "taken: offered all the same")

	local own = Load({ bindings = { ["CTRL-J"] = "ADVENTUREGUIDEFOREVER_WINDOW" } })
	equal(own.bindings["SHIFT-J"], nil, "a key of its own already: no second")

	local fighting = Load({
		setup = function(each)
			each.combat = true
		end,
	})
	equal(fighting.bindings["SHIFT-J"], nil, "combat: waits")
	equal(fighting.G.AdventureGuideForeverDB.window.keyOffered, nil, "combat: not yet offered")
	fighting.SetCombat(false)
	equal(fighting.bindings["SHIFT-J"], "ADVENTUREGUIDEFOREVER_WINDOW", "after combat: set")
	clean(fighting, "binding")
end

--[[ The Journeys tab: the route's cards and steps, the asides, and the panel kept in step ]]

do
	local spell = { name = "Lightning Bolt", level = 18, line = "Elemental", lineID = 375, general = false }
	local h = Load({ spf = "v1", tf = { spells = { spell } }, talents = 1 })
	local ns, L = h.ns, h.ns.L
	local window = Open(h)
	clean(h, "journeys")
	local route = ns.Route()
	local first, others = ns.Overview.Split(route)
	local texts = Texts(h)
	equal(texts[first.title], 1, "the featured card: the first journey")
	equal(texts[L.SUGGESTED], 1, "its Suggested tag")
	equal(texts[L.SHOW_ON_MAP], 1, "its Show on Map")
	for index = 1, math.min(#others, 4) do
		equal(texts[others[index].title], 1, "grid card " .. index)
	end
	for index = 1, math.min(#route.steps, 3) do
		equal(texts[route.steps[index].title] ~= nil, true, "step row " .. index)
	end
	for _, aside in ipairs(ns.Asides.All()) do
		equal(texts[aside.text], 1, "Today: " .. aside.key)
	end
	equal(#ns.Asides.All() >= 2, true, "Today: the trainer and the talents")
	local player = ns.State.Player()
	equal(window.Subtitle:GetText(), L.OVERVIEW_WHERE:format("The Barrens", player.level), "where and what level")

	-- A grid card chooses its journey as the panel's does, and both redraw from the same route.
	local card = h.Find(function(frame)
		return frame:IsVisible() and frame.journey == others[1] and frame:GetParent() ~= nil and frame.Art ~= nil
	end)[1]
	equal(card ~= nil, true, "the first grid card")
	h.Click(card)
	h.flush()
	equal(ns.Prefs().journey, others[1].key, "the click chooses it")
	equal(ns.Route().journey, others[1].key, "the route follows it")
	equal(Texts(h)[others[1].title], 1, "the window redraws with it")
	ns.OpenPanel()
	h.flush()
	local chosen = h.Find(function(frame)
		return frame:IsVisible() and frame.state == "chosen"
	end)[1]
	equal(chosen and chosen.journey.key, others[1].key, "the panel shows the same choice")

	-- Show on Map opens the world map to the featured card's first step.
	h.map:Hide()
	local button = h.Find(function(frame)
		return frame:IsVisible() and frame.text == L.SHOW_ON_MAP
	end)[1]
	local turns = h.counts.SetMapID
	h.Click(button)
	h.flush()
	equal(h.map:IsShown(), true, "Show on Map: the map opens")
	equal(h.counts.SetMapID > turns, true, "Show on Map: turned to the step")
	clean(h, "journeys: clicks")

	-- Hidden, the window draws nothing and listens to nothing; shown, it catches up.
	local featuredTitle = ns.Overview.Split(ns.Route()).title
	window:Hide()
	equal(next(window.events or {}), nil, "hidden: no events")
	ns.Choose(nil)
	h.flush()
	local stale = Texts(h)[featuredTitle]
	equal(stale, 1, "hidden: not redrawn")
	window:Show()
	h.flush()
	equal(Texts(h)[ns.Overview.Split(ns.Route()).title], 1, "shown: redrawn")
	equal(window.events.BAG_UPDATE_DELAYED, true, "shown: listens")
	clean(h, "journeys: hidden")
end

--[[ SkillUp Forever: present, missing, too old, nothing to level ]]

local fixture = dofile("tests/fixtures/skillup.lua")
local LEATHERWORKING, TAILORING, ITEMS = fixture.LEATHERWORKING, fixture.TAILORING, fixture.ITEMS

-- A snapshot of a table's keys and values, to prove the adapter never writes SkillUp's shared table.
local function Snapshot(value, out, prefix)
	out, prefix = out or {}, prefix or ""
	if type(value) ~= "table" then
		out[#out + 1] = prefix .. "=" .. tostring(value)
		return out
	end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		Snapshot(value[tonumber(key) or key], out, prefix .. "." .. key)
	end
	return out
end

local function ProfessionsTab(h)
	local window = Open(h)
	h.Click(window.Tabs[2])
	return window
end

for _, case in ipairs({
	{ label = "missing", options = {}, state = "missing", line = "SKILLUP_MISSING" },
	{ label = "version 0", options = { skillup = { version = 0 } }, state = "outdated", line = "SKILLUP_OUTDATED" },
	{ label = "no API", options = { skillup = { noAPI = true } }, state = "outdated", line = "SKILLUP_OUTDATED" },
	{
		label = "nothing to level",
		options = { skillup = { professions = {} } },
		state = "ready",
		line = "SKILLUP_NONE",
	},
}) do
	local h = Load(case.options)
	local L = h.ns.L
	equal(h.ns.Integrations.SkillUpState(), case.state, case.label .. ": state")
	equal(#h.ns.Integrations.Professions(), 0, case.label .. ": no professions")
	local window = Open(h)
	local tab = window.Tabs[2]
	equal(tab.normalFont, "GameFontDisableSmall", case.label .. ": the label greyed")
	equal(tab:IsEnabled(), true, case.label .. ": still clickable")
	h.Hover(tab)
	equal(h.tooltip[2], "normal: " .. L[case.line], case.label .. ": the tab's tooltip says why")
	ProfessionsTab(h)
	equal(window.selectedTab, 2, case.label .. ": the tab opens")
	local texts = Texts(h)
	equal(texts[L[case.line]], 1, case.label .. ": the calm line")
	equal(texts[L.FROM_SKILLUP], nil, case.label .. ": no card")
	clean(h, case.label)
end

do
	local skillup = { professions = { LEATHERWORKING, TAILORING } }
	local before = table.concat(Snapshot(skillup.professions), "\n")
	local h = Load({ skillup = skillup, items = ITEMS })
	local ns, L = h.ns, h.ns.L
	equal(ns.Integrations.SkillUpState(), "ready", "present: ready")
	equal(#ns.Integrations.Professions(), 2, "present: both professions")
	local window = ProfessionsTab(h)
	clean(h, "present: open")
	equal(window.Tabs[2].normalFont, "GameFontNormalSmall", "present: the label gold")
	local texts = Texts(h)
	equal(texts.Leatherworking, 1, "present: the most actionable first")
	equal(texts[L.PROFESSION_RANGE_TITLE:format(142, 150, "Journeyman")], 1, "present: rank to cap and title")
	equal(texts[L.PROFESSION_BAR:format(142, 150)], 1, "present: the bar's label")
	equal(texts[L.FROM_SKILLUP], 1, "present: where it comes from")
	equal(texts[L.RECIPE_COUNT:format("Toughened Leather Gloves", 3)], 1, "present: recipe 1")
	equal(texts[L.PROFESSION_RANGE:format(142, 145) .. L.SEPARATOR .. L.RECIPE_LEARNED], 1, "present: learned")
	equal(
		texts[L.PROFESSION_RANGE:format(145, 150) .. L.SEPARATOR .. L.RECIPE_TRAIN_AT:format(145) .. L.SEPARATOR .. "18s"],
		1,
		"present: to train, with its fee"
	)
	equal(texts["Buy 26 Fine Thread"], 1, "present: step 1")
	equal(texts[L.REAGENT_NEED:format(26, "Fine Thread")], 1, "present: reagent 1")
	equal(texts[L.REAGENT_VENDOR], 1, "present: bought from a vendor")
	equal(texts[L.REAGENT_HAVE:format(40)], 1, "present: what the bags hold")
	equal(texts[L.REAGENT_NEED:format(6, "Cured Medium Hide")], 1, "present: a reagent with no source")
	local orange = h.Find(function(frame)
		return frame:IsVisible()
			and frame.Name
			and frame.Name.text == L.RECIPE_COUNT:format("Hillman's Leather Gloves", 5)
	end)[1]
	equal(orange and table.concat(orange.Name.textColor, ","), "1,0.5,0.25", "present: coloured by difficulty")

	-- The steps: one SkillUp can route to sets its waypoint; one it can't does nothing.
	local rows = h.Find(function(frame)
		return frame:IsVisible() and frame.profession ~= nil and frame.step ~= nil
	end)
	equal(#rows, 3, "present: three steps")
	h.Click(rows[1])
	h.Click(rows[2])
	equal(#h.skillup.navigate, 1, "present: only the step with a waypoint")
	equal(table.concat(h.skillup.navigate[1], ","), "165,1", "present: its skill line and index")
	h.Hover(rows[1])
	equal(h.tooltip[#h.tooltip], "instruction: " .. L.CLICK_WAYPOINT_STEP, "present: the step says so")
	-- Closing the window fires no OnLeave: the row's tooltip goes with it.
	h.G.AdventureGuideForeverWindow:Hide()
	equal(h.G.GameTooltip:IsShown(), false, "present: closing the window takes the row's tooltip")
	h.G.AdventureGuideForeverWindow:Show()
	local open = h.Find(function(frame)
		return frame:IsVisible() and frame.text == L.OPEN_RECIPES
	end)[1]
	h.Click(open)
	equal(h.skillup.open[1], 165, "present: Open Recipes")

	-- The picker: a ring a profession while there are two; the other one's card on a click, remembered.
	local picks = h.Find(function(frame)
		return frame:IsVisible()
			and frame.profession ~= nil
			and frame.Icon ~= nil
			and frame.step == nil
			and frame.Name == nil
			and frame.Title == nil
	end)
	equal(#picks, 2, "present: the picker")
	h.Click(picks[2])
	equal(Texts(h).Tailoring, 1, "present: the picked profession")
	equal(h.G.AdventureGuideForeverDB.window.profession, 197, "present: remembered")
	equal(Texts(h)[L.NEXT_STEPS], nil, "present: no steps heading with no steps")
	equal(table.concat(Snapshot(skillup.professions), "\n"), before, "present: SkillUp's table never written")
	clean(h, "present")

	local one = Load({ skillup = { professions = { LEATHERWORKING } }, items = ITEMS })
	ProfessionsTab(one)
	local shown = one.Find(function(frame)
		return frame:IsVisible()
			and frame.profession ~= nil
			and frame.Icon ~= nil
			and frame.step == nil
			and frame.Name == nil
			and frame.Title == nil
	end)
	equal(#shown, 0, "one profession: no picker")
	clean(one, "one profession")
end

print(("window_spec: %d checks passed"):format(checks))
