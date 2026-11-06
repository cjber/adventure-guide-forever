-- Run from the repository root: luajit tests/map_open_spec.lua
-- Every map AGF opens goes through ns.OpenMap (#411). With the map already showing (the guide's sidebar, the cleanup
-- menu) it turns the map through Blizzard's own opener, whose call from addon code is not restricted; with the map
-- closed it asks C_Map.OpenWorldMap, which has Blizzard open it without tainting the gamepad UI. The restricted call
-- is never made on a shown map, where the carry card's MenuUtil callback raised ADDON_ACTION_BLOCKED.
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

-- The restricted call is the one Blizzard blocks from addon menu callbacks; it must never run while the map shows.
local restricted = 0
local cMapOpen = h.G.C_Map.OpenWorldMap
h.G.C_Map.OpenWorldMap = function(...)
	restricted = restricted + 1
	return cMapOpen(...)
end
local function Opened()
	return h.counts.OpenWorldMap
end

-- A closed map still opens through the client's own entry point, which Blizzard runs without tainting the UI.
h.G.WorldMapFrame:Hide()
local opened, maps = Opened(), h.counts.SetMapID
equal(ns.OpenMap(0), true, "closed: the map opens on the player's own map")
equal(Opened(), opened, "closed: through C_Map.OpenWorldMap")
equal(restricted, 1, "closed: the client's entry point")
equal(h.counts.SetMapID, maps, "closed: no map id keeps the current map")
equal(h.G.WorldMapFrame:IsShown(), true, "closed: the map now shows")

-- The reported path: the carry card's cleanup menu, with the map showing. Its MenuUtil callback opened through
-- Blizzard's own function and did not touch the restricted call.
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
entry.onClick()
equal(h.selectedQuests[#h.selectedQuests], 844, "cleanup: the quest is selected in the log")
equal(Opened(), opened + 1, "cleanup: the map turns through Blizzard's opener")
equal(h.counts.SetMapID, maps + 1, "cleanup: on the quest's zone")
equal(h.map:GetMapID(), 1413, "cleanup: the map's id")
equal(restricted, 1, "cleanup: the restricted call is not made")

-- The guide's panel, a log step's quest and a pin reveal all take the same path while the map shows.
opened = Opened()
ns.OpenPanel()
h.flush()
equal(Opened(), opened + 1, "panel: through Blizzard's opener")
opened = Opened()
local step
for _, each in ipairs(ns.Route().steps) do
	step = step or (ns.InLog(each) and each or nil)
end
assert(step, "the route has a quest in the log")
equal(ns.ShowQuest(step), true, "step: the quest opens")
equal(Opened(), opened + 1, "step: through Blizzard's opener")
opened = Opened()
ns.Pins.Reveal({ map = 1413, x = 0.5, y = 0.5 })
equal(Opened(), opened + 1, "reveal: through Blizzard's opener")
equal(restricted, 1, "shown: the restricted call is still not made")

-- A reveal on a closed map asks the client to open it, untainted, and the compartment button follows the same rule.
h.G.WorldMapFrame:Hide()
opened = Opened()
ns.Pins.Reveal({ map = 1413, x = 0.5, y = 0.5 })
equal(Opened(), opened, "reveal closed: the client opens it")
equal(restricted, 2, "reveal closed: through C_Map.OpenWorldMap")
h.G.WorldMapFrame:Show()
opened = Opened()
h.G.AdventureGuideForever_OnAddonCompartmentClick()
h.flush()
equal(Opened(), opened + 1, "compartment: through Blizzard's opener")

-- In combat nothing opens, either way.
local shown = h.G.WorldMapFrame:IsShown()
opened = Opened()
h.SetCombat(true)
equal(ns.OpenMap(1413), false, "combat: no map")
equal(Opened(), opened, "combat: the opener is not called")
equal(restricted, 2, "combat: nor the client's")
h.SetCombat(false)
equal(h.G.WorldMapFrame:IsShown(), shown, "combat: the map is left as it was")

equal(h.counts.OpenQuestLog, 0, "the quest log's sidebar is never opened")
equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))

print(("map_open_spec: %d checks passed"):format(checks))
