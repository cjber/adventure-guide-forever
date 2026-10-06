-- Run from the repository root: luajit tests/scenes.lua [input.json]
-- What tools/screenshots.py draws, taken from the addon through tests/harness.lua, so no AGF
-- text or layout is retyped in Python. Not a spec: it checks nothing and prints one JSON object.
--
-- input.json comes from screenshots.py's layout pass: `rects` (per scene, a path -> {left, bottom, width, height}
-- map it resolved from the previous run) and `mapArt` (each zone's base tiles, as C_Map.GetMapArtLayerTextures gives
-- them in game). With no input the panel is exactly tests/golden/layout.json, which
-- screenshots.py checks.
local harness, json = dofile("tests/harness.lua"), dofile("tests/json.lua")
local QUERY = "Call of"

local input = { rects = {} }
if arg[1] then
	local handle = assert(io.open(arg[1]))
	input = json.decode(handle:read("*a"))
	handle:close()
end

-- Every harness, for its errors.
local loaded = {}

-- ui_spec's level-18 orc shaman in The Barrens: one quest ready to hand in, one under way.
-- `optIn` turns on the marks a player opts into (both are off by default); the panel and search scenes, the store
-- page's lead images, keep the defaults, so they show only the rings the open guide previews.
-- The character chose the Barrens story before, as ui_spec's has, or `journey`; `fresh` has chosen nothing yet.
-- `carried` adds finished quests to the log; `extra` adds harness options (Tweaks Forever, talent points).
local function Load(spf, optIn, fresh, journey, carried, extra)
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	for _, quest in ipairs(carried or {}) do
		log[#log + 1] = quest
	end
	local options = {
		spf = spf or nil,
		db = { autoStart = false, showMapPins = optIn or false, showQuestGivers = optIn or false },
		charDB = not fresh and { journey = journey or "zone:1413" } or nil,
		completed = { 844 },
		log = log,
	}
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	local h = harness.load(options)
	loaded[#loaded + 1] = h
	if input.mapArt then
		h.mapArt = {}
		for map, tiles in pairs(input.mapArt) do
			h.mapArt[tonumber(map)] = tiles
		end
	end
	return h
end

-- The guide's panel after the layout pass: rects in, OnSizeChanged run, then the refresh the client's next frame
-- would do with the laid-out sizes.
local function Panel(h, scene, height)
	h.ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	if height then
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", h.G.QuestMapFrame.ContentsAnchor)
		panel:SetPoint("TOPRIGHT", h.G.QuestMapFrame.ContentsAnchor, -22, 0)
		panel:SetHeight(height)
	end
	h.SetRects(panel, input.rects[scene] or {})
	h.ns.OpenPanel()
	h.flush()
	return {
		layout = h.ns.DumpLayout(panel, h.Describe),
		tabs = {
			h.ns.DumpLayout(h.G.AdventureGuideForeverQuestsTab, h.Describe),
			h.ns.DumpLayout(h.G.AdventureGuideForeverTab, h.Describe),
		},
	}
end

-- Drawn in this order: the givers under the numbered rings.
local PIN_TEMPLATES = {
	"AdventureGuideForeverGiverPinTemplate",
	"AdventureGuideForeverPinTemplate",
}

local function Pins(h)
	local pins = {}
	for _, template in ipairs(PIN_TEMPLATES) do
		for _, pin in ipairs(h.pins[template] or {}) do
			pins[#pins + 1] = { template = template, x = pin.x, y = pin.y, layout = h.ns.DumpLayout(pin, h.Describe) }
		end
	end
	return pins
end

local function Tooltip(h)
	local lines = {}
	for index, line in ipairs(h.tooltip) do
		local kind, text = line:match("^(%a+): (.*)$")
		local color = h.tooltipColors[index]
		lines[index] = { kind = kind, text = text, color = color }
	end
	return lines
end

local out = {}

-- Match ui_spec's explicit paused, planned-order fixture for its golden layout. Other scenes use nearest-first.
local STORY = "zone:1413"
local h = Load("v1", false, false, STORY, nil, { planned = true })
out.panel = Panel(h, "panel")
h.providers[1]:RefreshAllData()
out.panel.pins = Pins(h)
out.panel.map = h.map:GetMapID()

-- The lead image, a character with no card chosen: compact journey rows (docs/design.md §2.2),
-- both asides above them, and the first card's rings, which the guide previews
-- on its own (§2.6). Two finished quests: Counterattack!, handed in at Regthar Deathgate's camp, so the story card
-- counts two ready, and Hidden Enemies, handed in at Orgrimmar, so Quests in your log has one. Tweaks Forever
-- has three optional spells to train and a talent point waits; spell reminders stay off.
local COUNTERATTACK =
	{ id = 4021, title = "Counterattack!", level = 20, complete = true, map = 1413, x = 0.4534, y = 0.2841 }
local HIDDEN_ENEMIES =
	{ id = 5729, title = "Hidden Enemies", level = 15, complete = true, map = 1454, x = 0.4947, y = 0.5059 }
local SPELL = { name = "Lightning Bolt", level = 18, line = "Elemental", lineID = 375, general = false }
h = Load("v1+", false, true, nil, { COUNTERATTACK, HIDDEN_ENEMIES }, {
	tf = { spells = { SPELL, SPELL, SPELL } },
	talents = 1,
})
-- The stub's one flight leg takes longer the farther the stop, so each card reads its own minutes.
local detail = h.G.ShortestPathForever.API.EstimateDetail
h.G.ShortestPathForever.API.EstimateDetail = function(fromMap, fromX, fromY, toMap, toX, toY)
	local far = toMap == fromMap and math.sqrt((toX - fromX) ^ 2 + (toY - fromY) ^ 2) or 0.4
	h.spfSeconds = math.floor(far * 1500) + 60
	return detail(fromMap, fromX, fromY, toMap, toX, toY) -- multi-value: the stub's detail and its reason
end
out.journeys = Panel(h, "journeys")
h.providers[1]:RefreshAllData()
out.journeys.pins = Pins(h)

-- Four choices with dungeons enabled, then the same overview in a shorter map sidebar.
h.ns.Prefs().dungeons = true
h.ns.NotInterested("zone:1421", h.ns.State.MapName(1421))
h.ns.Invalidate()
h.flush()
out.journeys_four = Panel(h, "journeys_four")
out.journeys_overflow = Panel(h, "journeys_overflow", 330)

-- The search: the Call of quests a level-18 orc shaman sees, the locked ones saying why.
h = Load(false, false, false, STORY)
local search = h.Find(function(frame)
	return frame.stockTemplate == "SearchBoxTemplate"
end)[1]
h.Type(search, QUERY)
out.search = Panel(h, "search")

-- With Shortest Path loaded, on the story card: a town ring's tooltip, the tracker's town lines and menu, and the
-- route handed to Shortest Path.
h = Load("v1", true, false, STORY)
h.G.C_Map.OpenWorldMap()
h.flush()
h.providers[1]:RefreshAllData()
-- Ring 2, Regthar Deathgate's two quests: ring 1, Crossroads, sits under the player's arrow at the fixture's position.
local HOVERED = 2
local ring = h.pins.AdventureGuideForeverPinTemplate[HOVERED]
h.Hover(ring)
out.tooltip = {
	lines = Tooltip(h),
	pins = Pins(h),
	hovered = #(h.pins.AdventureGuideForeverGiverPinTemplate or {}) + HOVERED,
}
ring:OnMouseLeave()

local module = h.tracker
local blocks = {}
for index, id in ipairs(module.layoutOrder) do
	local block = module.liveBlocks[id]
	local lines = {}
	for position, key in ipairs(block.order) do
		-- A dash unless the line hides it (OBJECTIVE_DASH_STYLE_HIDE and _HIDE_AND_COLLAPSE).
		lines[position] = { text = block.lines[key], dash = (block.dashes[key] or 1) == 1 }
	end
	blocks[index] = { header = block.header, lines = lines }
end
out.tracker = { header = module.Header.Text:GetText(), blocks = blocks }
-- The step block is laid out last, under the journey's title, the asides and the fanfares.
module:OnBlockHeaderClick(module.liveBlocks[module.layoutOrder[#module.layoutOrder]], "RightButton")
local entries = {}
for index, entry in ipairs(h.menu.entries) do
	entries[index] = { kind = entry.kind, text = entry.text }
end
out.menu = entries

local api, stops = h.G.ShortestPathForever.API, nil
local NavigateRoute = api.NavigateRoute
api.NavigateRoute = function(owner, route)
	stops = route
	return NavigateRoute(owner, route)
end
-- At Camp Taurajo, so Shortest Path walks the road north to the first stop and is handed every step after it.
h.MovePlayer(1413, 0.45, 0.6)
h.ns.Invalidate()
h.flush()
h.ns.Guidance.Navigate(h.ns.Route().steps[1])
h.flush()
h.providers[1]:RefreshAllData()
out.map = { stops = stops, pins = Pins(h), player = { map = h.player.map, x = h.player.x, y = h.player.y } }

h = Load("v1", false, true)
h.flush()
h.ns.StoryCompletion.Record(849)
local popup = h.Find(function(frame)
	return frame.Fill and frame:GetWidth() == 360 and frame:GetHeight() == 82
end)
assert(popup[1], "story completion popup missing")
if input.rects.story_complete then
	h.SetRects(popup[1], input.rects.story_complete)
end
out.story_complete = { layout = h.ns.DumpLayout(popup[1], h.Describe) }

-- AtlasLoot Classic's Deadmines record: Edwin VanCleef (639), Cruel Barb (5191).
h = harness.load({ items = { [5191] = { name = "Cruel Barb" } } })
loaded[#loaded + 1] = h
h.ns.DungeonLoot.Bosses = function()
	return { { name = "Edwin VanCleef", npcID = 639, items = { 5191 } } }
end
local owner = h.G.CreateFrame("Button", nil, h.G.UIParent)
h.ns.Menu.Journey(owner, { title = "Deadmines", key = "dungeon:36", instance = 36 })
local lootPopup = h.G.AdventureGuideForeverContextMenu
h.Click(lootPopup.rows[2])
h.Click(lootPopup.rows[2])
out.loot_menu = {}
for _, row in ipairs(lootPopup.rows) do
	if row:IsShown() then
		out.loot_menu[#out.loot_menu + 1] = { kind = row:IsEnabled() and "button" or "title", text = row:GetText() }
	end
end

out.errors = {}
for _, each in ipairs(loaded) do
	for _, err in ipairs(each.errors) do
		out.errors[#out.errors + 1] = err
	end
end
io.write(json.encode(out, "%.10g"))
