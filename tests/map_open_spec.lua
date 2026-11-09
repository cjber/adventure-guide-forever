-- Run from the repository root: luajit tests/map_open_spec.lua
-- Every map AGF opens goes through ns.OpenMap, which asks C_Map.OpenWorldMap: the client's own code opens or turns
-- the map, so WorldMapFrame.mapID is never written as the addon (#534). Blizzard's Lua OpenWorldMap
-- (Blizzard_WorldMap.lua:1329) runs as its caller instead, and the client then blocks the quest pins that read the
-- map id (QuestDataProvider.lua:117, Blizzard_MapCanvas.lua:331). A MenuUtil callback refuses C_Map.OpenWorldMap
-- (#411), so the carry card's cleanup menu asks after the menu has closed.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function Carry(ns)
	for _, journey in ipairs(ns.Route().journeys) do
		if journey.kind == "carry" then
			return journey
		end
	end
end

local function Card(h, key)
	for _, frame in
		ipairs(h.Find(function(f)
			return f:IsVisible() and f.IconFrame ~= nil and f.journey ~= nil
		end))
	do
		if frame.journey.key == key then
			return frame
		end
	end
end

---@param menu AGFMenuDescription
---@param text string
---@return AGFMenuDescription?
local function MenuEntry(menu, text)
	for _, entry in ipairs(menu.entries or {}) do
		if entry.text == text then
			return entry
		end
		local found = MenuEntry(entry, text)
		if found then
			return found
		end
	end
end

-- The log cleanup_spec uses: one ready, one grey, one ruled out and one the data cannot place.
local h = harness.load({
	planned = true,
	panelHeight = 1200,
	db = { autoStart = false },
	charDB = { journey = "carry", notInterested = { ["quest:844"] = { title = "Plainstrider Menace" } } },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 5, complete = false },
		{ id = 999999, title = "Mystery", level = 18, complete = false },
		{ id = 844, title = "Plainstrider Menace", level = 12, complete = false, map = 1413 },
	},
	completed = {},
})
h.flush()
local ns = h.ns

-- The client's own opener, counted; Blizzard's Lua opener (h.counts.OpenWorldMap) is what the addon must never run.
local restricted = 0
local cMapOpen = h.G.C_Map.OpenWorldMap
h.G.C_Map.OpenWorldMap = function(...)
	restricted = restricted + 1
	return cMapOpen(...)
end
local function Opened()
	return h.counts.OpenWorldMap
end

-- A closed map opens through the client, which leaves the map's fields secure.
h.G.WorldMapFrame:Hide()
local opened, maps = Opened(), h.counts.SetMapID
equal(ns.OpenMap(0), true, "closed: the map opens on the player's own map")
equal(Opened(), opened, "closed: Blizzard's Lua opener is never run")
equal(restricted, 1, "closed: through C_Map.OpenWorldMap")
equal(h.counts.SetMapID, maps, "closed: no map id keeps the current map")
equal(h.G.WorldMapFrame:IsShown(), true, "closed: the map now shows")

-- The reported path: the carry card's cleanup menu, with the map showing. Its MenuUtil callback refuses the client
-- opener, so the open is asked for after the menu has closed and still never runs Blizzard's Lua opener.
ns.OpenPanel()
h.flush()
local carry = Carry(ns)
local card = Card(h, carry.key)
assert(card, "the carry card is drawn")
h.selectedQuests = {}
h.Click(card, "RightButton")
local entry = h.menu and MenuEntry(h.menu, "Plainstrider Menace")
assert(entry, "the cleanup menu offers the quest")
opened, maps = Opened(), h.counts.SetMapID
local before = restricted
entry.onClick()
equal(h.selectedQuests[#h.selectedQuests], 844, "cleanup: the quest is selected in the log")
equal(restricted, before, "cleanup: the open waits for the menu to close")
h.flush()
equal(restricted, before + 1, "cleanup: through C_Map.OpenWorldMap")
equal(Opened(), opened, "cleanup: Blizzard's Lua opener is never run")
equal(h.counts.SetMapID, maps + 1, "cleanup: on the quest's zone")
equal(h.map:GetMapID(), 1413, "cleanup: the map's id")

-- The guide's panel, a log step's quest and a pin reveal all take the same path while the map shows.
opened, maps = Opened(), restricted
ns.OpenPanel()
h.flush()
equal(restricted, maps + 1, "panel: through C_Map.OpenWorldMap")
equal(Opened(), opened, "panel: Blizzard's Lua opener is never run")
opened, maps = Opened(), restricted
local step
for _, each in ipairs(ns.Route().steps) do
	step = step or (ns.InLog(each) and each or nil)
end
assert(step, "the route has a quest in the log")
equal(ns.ShowQuest(step), true, "step: the quest opens")
equal(restricted, maps + 1, "step: through C_Map.OpenWorldMap")
equal(Opened(), opened, "step: Blizzard's Lua opener is never run")
opened, maps = Opened(), restricted
ns.Pins.Reveal({ map = 1413, x = 0.5, y = 0.5 })
equal(restricted, maps + 1, "reveal: through C_Map.OpenWorldMap")
equal(Opened(), opened, "reveal: Blizzard's Lua opener is never run")

-- MenuUtil runs a responder inside its securecall, where the client refuses C_Map.OpenWorldMap (#411): the step
-- menu's map entries wait for the menu to close.
local function Recorder()
	local root = { buttons = {} }
	function root:CreateTitle() end
	function root:SetScrollMode() end
	function root:CreateButton(text, onClick)
		local button = { text = text, onClick = onClick, buttons = {} }
		button.CreateTitle = function() end
		button.SetScrollMode = function() end
		button.SetTooltip = function() end
		button.CreateButton = function(_, text2, onClick2)
			local nested = { text = text2, onClick = onClick2 }
			button.buttons[#button.buttons + 1] = nested
			return nested
		end
		root.buttons[#root.buttons + 1] = button
		return button
	end
	return root
end
local function MenuButton(root, text)
	for _, button in ipairs(root.buttons) do
		if button.text == text then
			return button
		end
	end
end
local recorder = Recorder()
ns.Menu.Step(recorder, step)
local showQuest = MenuButton(recorder, ns.L.SHOW_QUEST)
assert(showQuest, "the step menu offers Show quest")
local select = MenuButton(recorder, ns.L.CHOOSE_JOURNEY)
assert(select, "the step menu offers Choose another journey")
opened, maps = Opened(), restricted
showQuest.onClick()
equal(restricted, maps, "menu: Show quest waits for the menu to close")
h.flush()
equal(restricted, maps + 1, "menu: Show quest through C_Map.OpenWorldMap")
equal(Opened(), opened, "menu: Show quest never runs Blizzard's Lua opener")
opened, maps = Opened(), restricted
select.onClick()
equal(restricted, maps, "menu: Choose another journey waits for the menu to close")
h.flush()
equal(restricted, maps + 1, "menu: Choose another journey through C_Map.OpenWorldMap")
equal(Opened(), opened, "menu: Choose another journey never runs Blizzard's Lua opener")

-- A reveal on a closed map asks the client to open it, untainted, and the compartment button follows the same rule.
h.G.WorldMapFrame:Hide()
opened, maps = Opened(), restricted
ns.Pins.Reveal({ map = 1413, x = 0.5, y = 0.5 })
equal(restricted, maps + 1, "reveal closed: through C_Map.OpenWorldMap")
equal(Opened(), opened, "reveal closed: Blizzard's Lua opener is never run")
h.G.WorldMapFrame:Show()
opened, maps = Opened(), restricted
h.G.AdventureGuideForever_OnAddonCompartmentClick()
h.flush()
equal(restricted, maps + 1, "compartment: through C_Map.OpenWorldMap")
equal(Opened(), opened, "compartment: Blizzard's Lua opener is never run")

-- In combat nothing opens, either way.
local shown = h.G.WorldMapFrame:IsShown()
opened, maps = Opened(), restricted
h.SetCombat(true)
equal(ns.OpenMap(1413), false, "combat: no map")
equal(restricted, maps, "combat: the opener is not called")
equal(Opened(), opened, "combat: nor Blizzard's Lua opener")
h.SetCombat(false)
equal(h.G.WorldMapFrame:IsShown(), shown, "combat: the map is left as it was")

equal(h.counts.OpenQuestLog, 0, "the quest log's sidebar is never opened")
equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))

print(("map_open_spec: %d checks passed"):format(checks))
