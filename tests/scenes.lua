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

-- Sync Together (#617): a party of members running the guide, each heard from with a completed set, and the given
-- members ticked under Sync with. `members` is { { name = "Barry Bogwhistle", done = set, synced = true }, ... }.
local function Sync(h, members)
	local G = h.G
	local units = {}
	for index, member in ipairs(members) do
		units["party" .. index] = member.name
	end
	G.LE_PARTY_CATEGORY_HOME = 1
	G.IsInGroup = function(category)
		return category == 1
	end
	G.IsInRaid = function()
		return false
	end
	G.GetNormalizedRealmName = function()
		return "Realm"
	end
	G.UnitExists = function(unit)
		return units[unit] ~= nil
	end
	G.UnitName = function(unit)
		if unit == "player" then
			return "Me"
		end
		return units[unit]
	end
	G.C_QuestLog.IsUnitOnQuest = function()
		return false
	end
	G.C_ChatInfo = {
		RegisterAddonMessagePrefix = function()
			return 0
		end,
		SendAddonMessage = function()
			return 0
		end,
	}
	G.Enum = setmetatable({
		SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 },
	}, { __index = G.Enum })
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	for index, member in ipairs(members) do
		local done = {}
		for id in pairs(member.done) do
			done[#done + 1] = id
		end
		table.sort(done)
		local pages = assert(h.ns.Party.Encode({}, done, false, index))
		for _, text in ipairs(pages) do
			h.fire("CHAT_MSG_ADDON", "AGFParty", text, "PARTY", member.name .. "-Realm")
		end
	end
	h.flush()
	for _, member in ipairs(members) do
		if member.synced then
			h.ns.Party.Toggle(member.name .. "-Realm")
		end
	end
	h.flush()
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
			h.ns.DumpLayout(h.G.ForeverQuestLogQuestsTab, h.Describe),
			h.ns.DumpLayout(h.G.AdventureGuideForeverTab, h.Describe),
		},
	}
end

-- Drawn in this order: the givers and visit spots under the numbered rings.
local PIN_TEMPLATES = {
	"AdventureGuideForeverGiverPinTemplate",
	"AdventureGuideForeverSpotPinTemplate",
	"AdventureGuideForeverPinTemplate",
}

local function Pins(h)
	local pins = {}
	for _, template in ipairs(PIN_TEMPLATES) do
		for _, pin in ipairs(h.Pins(template) or {}) do
			pins[#pins + 1] =
				{ template = template, x = pin.mapX, y = pin.mapY, layout = h.ns.DumpLayout(pin, h.Describe) }
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

-- The guide's tracker section: its header, the grey count of quests a journey hides when it shows one, then each
-- block's header and its lines (a dash unless the line hides it, OBJECTIVE_DASH_STYLE_HIDE and _HIDE_AND_COLLAPSE).
-- Shortest Path's own section is drawn from its planner.
local function Tracker(h)
	local module = h.tracker
	local blocks = {}
	for index, id in ipairs(module.layoutOrder) do
		local block = module.liveBlocks[id]
		local lines = {}
		for position, key in ipairs(block.order) do
			lines[position] = { text = block.lines[key], dash = (block.dashes[key] or 1) == 1 }
		end
		blocks[index] = { header = block.header, lines = lines }
	end
	local notice = module.hiddenText
	local hidden = notice and notice:IsShown() and notice:GetText() or nil
	return { header = module.Header.Text:GetText(), hidden = hidden, blocks = blocks }
end

local out = {}

-- Match ui_spec's explicit paused, planned-order fixture for its golden layout. Other scenes use nearest-first.
local STORY = "zone:1413"
local h = Load("v1", false, false, STORY, nil, { planned = true })
out.panel = Panel(h, "panel")
h.ns.Pins.Refresh()
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
h.ns.Pins.Refresh()
out.journeys.pins = Pins(h)

-- Four choices with dungeons enabled, then the same overview in a shorter map sidebar.
h.ns.Prefs().dungeons = true
h.ns.NotInterested("zone:1421", h.ns.State.MapName(1421))
h.ns.Invalidate()
h.flush()
out.journeys_four = Panel(h, "journeys_four")
out.journeys_overflow = Panel(h, "journeys_overflow", 330)

-- The Library books section on its own: a fresh character, every other card turned down, so the overview's card, its
-- book mark, its goal gate and its stops are all in the panel.
h = Load("v1", false, true)
h.flush()
for _, journey in ipairs(h.ns.Route().journeys) do
	if journey.kind ~= "library" then
		h.ns.NotInterested(journey.key, journey.title)
	end
end
h.ns.Invalidate()
h.flush()
out.library_card = Panel(h, "library_card")

-- The library's own journey, Horde territory first: smaller zones first, the hand-in last.
h = Load("v1", false, false, "library")
h.flush()
out.library_stops = Panel(h, "library_stops")
local library
for _, journey in ipairs(h.ns.Route().journeys) do
	library = journey.kind == "library" and journey or library
end
local libraryOwner = h.G.CreateFrame("Button", nil, h.G.UIParent)
h.ns.Menu.Journey(libraryOwner, library)
out.library_territory = Panel(h, "library_territory")
out.library_territory.menu = {}
for index, entry in ipairs(h.menu.entries) do
	out.library_territory.menu[index] = {
		kind = entry.kind,
		text = entry.text,
		selected = entry.isSelected and entry.isSelected() or nil,
	}
end

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
h.ns.Pins.Refresh()
-- Ring 2, Regthar Deathgate's two quests: ring 1, Crossroads, sits under the player's arrow at the fixture's position.
local HOVERED = 2
local ring = h.Pins("AdventureGuideForeverPinTemplate")[HOVERED]
h.Hover(ring)
out.tooltip = {
	lines = Tooltip(h),
	pins = Pins(h),
	hovered = #(h.Pins("AdventureGuideForeverGiverPinTemplate") or {}) + HOVERED,
}
ring:OnMouseLeave()

local module = h.tracker
out.tracker = Tracker(h)
-- The step block is laid out last, under the journey's title, the asides and the fanfares.
h.OpenTrackerMenu(module)
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
h.ns.Pins.Refresh()
out.map = {
	stops = stops,
	pins = Pins(h),
	player = { map = h.player.map, x = h.player.x, y = h.player.y },
	zone = h.ns.State.MapName(h.player.map),
	tracker = Tracker(h),
}
-- The panel as that route leaves it: the same order the stops were handed in, the first step lit.
out.map_panel = Panel(h, "map_panel")

-- The guide on a journey across the sea, its tracker beside Shortest Path's own: the boat and the flight are Shortest
-- Path's lines, read from its planner by tools/screenshots.py. The legs below are that plan's, so the card's minutes
-- and the tracker's travel line (while it is held, not guided) say the same thing as the steps.
h = Load("v1+", false, false, "zone:1436")
h.spfLegs = {
	{ mode = "walk", to = "Ratchet dock", seconds = 25 },
	{ mode = "boat", to = "Stranglethorn Vale", seconds = 283, wait = 176 },
	{ mode = "walk", to = "Booty Bay dock", seconds = 65 },
	{ mode = "flight", to = "Grom'gol, Stranglethorn", seconds = 105 },
	{ mode = "walk", to = "Westfall", seconds = 467 },
}
h.MovePlayer(1413, 0.6237, 0.3762)
h.ns.Invalidate()
h.flush()
local guideAPI, guidedStops = h.G.ShortestPathForever.API, nil
local GuideRoute = guideAPI.NavigateRoute
guideAPI.NavigateRoute = function(owner, route)
	guidedStops = route
	return GuideRoute(owner, route)
end
h.ns.Choose("zone:1436", true)
h.flush()
local guided = h.ns.Route().steps[1]
out.steps = {
	tracker = Tracker(h),
	stops = guidedStops,
	zone = guided.zone,
	player = { map = h.player.map, x = h.player.x, y = h.player.y },
}

-- The tracker on a journey that hides two of the player's own tracked quests: the grey count beside the header.
-- Only tracker.png draws this one; the menu and the minimap button keep the tracker scene above. The two quests are
-- not in the catalogue, so they change nothing else the tracker shows.
h = Load("v1", true, false, STORY, {
	{ id = 900010, title = "Player's first quest", level = 12, complete = false },
	{ id = 900011, title = "Player's second quest", level = 12, complete = false },
}, {
	setup = function(each)
		each.watched = { 900010, 900011 }
	end,
})
out.tracker_watch = Tracker(h)

h = Load("v1", false, true)
h.flush()
h.ns.StoryCompletion.Record(849)
local toast = assert(h.alerts[1], "story completion toast missing")
if input.rects.story_complete then
	h.SetRects(toast, input.rects.story_complete)
end
out.story_complete = { layout = h.ns.DumpLayout(toast, h.Describe) }

-- AtlasLoot Classic's Deadmines record: Edwin VanCleef (639), Cruel Barb (5191).
h = harness.load({ items = { [5191] = { name = "Cruel Barb" } } })
loaded[#loaded + 1] = h
h.ns.DungeonLoot.Bosses = function()
	return { { name = "Edwin VanCleef", npcID = 639, items = { 5191 } } }
end
local owner = h.G.CreateFrame("Button", nil, h.G.UIParent)
h.ns.Menu.Journey(owner, { title = "Deadmines", key = "dungeon:36", instance = 36 })
local lootPopup = h.G.ForeverCoreContextMenu
h.Click(lootPopup.rows[2])
h.Click(lootPopup.rows[2])
out.loot_menu = {}
for _, row in ipairs(lootPopup.rows) do
	if row:IsShown() then
		out.loot_menu[#out.loot_menu + 1] = { kind = row:IsEnabled() and "button" or "title", text = row:GetText() }
	end
end

h = Load("v1", false, true)
dofile("tests/rxp_fixture.lua")(h, 10)
local example = assert(h.ns.RestedXP.Journey())
h.ns.Choose(example.key, true)
h.flush()
out.restedxp = Panel(h, "restedxp")
h.ns.Pins.Refresh()
out.restedxp.pins = Pins(h)

h = Load("v1", false, true, nil, nil, { skillup = { professions = {} } })
dofile("tests/rxp_fixture.lua")(h, nil, true)
local setup = assert(h.G.AdventureGuideForeverGuideSetup)
h.SetRects(setup, input.rects.guide_setup or {})
out.guide_setup = { layout = h.ns.DumpLayout(setup, h.Describe) }

-- Sync Together (#617): the cog's Sync with checklist, and the stops a synced journey labels. The party's completed
-- sets are invented for the scene; the route is the fixture's. The player has done the Dry Hills stops, so those are
-- one member's alone, while the Crossroads and Forgotten Pools stops are shared by two and three of the party.
h = Load("v1", false, false, STORY)
local sharedRoute = h.ns.Route()
local routeQuests = {}
for _, step in ipairs(sharedRoute.steps) do
	for _, id in ipairs(step.quests or {}) do
		routeQuests[id] = true
	end
end
local DRY_HILLS = { 95494, 95495, 95507, 95508, 95621 }
local dryHills = {}
for _, id in ipairs(DRY_HILLS) do
	dryHills[id] = true
	h.ns.State.Completed()[id] = true
end
h.ns.Invalidate()
h.flush()
local bogwhistle, puddingfoot, puddingstone = {}, {}, {}
for id in pairs(routeQuests) do
	-- Bogwhistle has done everything but the Crossroads hand-in, the second Forgotten Pools quest and the Dry Hills
	-- stops; Puddingfoot still needs the fungus and Kolkar work; Puddingstone still needs the Crossroads errand. The
	-- Forgotten Pools label then names both members besides Puddingstone and wraps onto a second line, which the
	-- scene shows is not cut.
	bogwhistle[id] = id ~= 845 and id ~= 855 and not dryHills[id] or nil
	puddingfoot[id] = id ~= 848 and id ~= 850 or nil
	puddingstone[id] = id ~= 869 or nil
end
Sync(h, {
	{ name = "Barry Bogwhistle", done = bogwhistle, synced = true },
	{ name = "Barry Puddingfoot", done = puddingfoot, synced = true },
	{ name = "Barry Puddingstone", done = puddingstone, synced = true },
})
out.sync = Panel(h, "sync")
out.sync_stops = Panel(h, "sync_stops")

-- The cog menu the picker draws: its own entries, the Sync with row and the checklist under it.
local menuOwner = h.G.CreateFrame("Button", nil, h.G.UIParent)
h.G.ForeverCore.ContextMenu(menuOwner, h.ns.Menu.Settings)
local function MenuEntries(description)
	local list = {}
	for _, entry in ipairs(description.entries) do
		local selected
		if type(entry.isSelected) == "function" then
			selected = entry.isSelected()
		end
		list[#list + 1] = { kind = entry.kind, text = entry.text, selected = selected }
	end
	return list
end
out.sync_menu = { entries = MenuEntries(h.menu), syncRow = 0 }
for index, entry in ipairs(h.menu.entries) do
	if entry.text == h.ns.L.SYNC_WITH then
		out.sync_menu.syncRow = index
		out.sync_menu.entries[index].submenu = true
		out.sync_submenu = MenuEntries(entry)
	end
end

out.errors = {}
for _, each in ipairs(loaded) do
	for _, err in ipairs(each.errors) do
		out.errors[#out.errors + 1] = err
	end
end
io.write(json.encode(out, "%.10g"))
