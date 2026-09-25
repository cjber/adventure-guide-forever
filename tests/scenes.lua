-- Run from the repository root: luajit tests/scenes.lua [input.json]
-- What tools/screenshots.py draws, taken from the addon through tests/harness.lua (docs/plan.md §1.3), so no AGF
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
		db = optIn and { showMapPins = true, showQuestGivers = true } or nil,
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
local function Panel(h, scene)
	h.ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
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

-- The chosen view: the story card's towns, with Shortest Path's minutes on step 1 (ui_spec's golden layout).
local STORY = "zone:1413"
local h = Load("v1", false, false, STORY)
out.panel = Panel(h, "panel")
h.providers[1]:RefreshAllData()
out.panel.pins = Pins(h)
out.panel.map = h.map:GetMapID()

-- The lead image, a character with no card chosen: the overview (docs/design.md §2.2), the story featured over its
-- first steps and the others two across, both asides above them, and the first card's rings, which the guide previews
-- on its own (§2.6). Two finished quests: Counterattack!, handed in at Regthar Deathgate's camp, so the story card
-- counts two ready, and Hidden Enemies, handed in at Orgrimmar, so Loose ends has one. Tweaks Forever has three spells
-- to train and a talent point waits, so both asides show.
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
h.G.OpenQuestLog()
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
module:OnBlockHeaderClick(module.liveBlocks[module.layoutOrder[1]], "RightButton")
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
-- Just out of the Crossroads, so Shortest Path is handed every step, not the town the player stands in alone.
h.MovePlayer(1413, 0.52, 0.36)
h.ns.Invalidate()
h.flush()
h.ns.Integrations.Navigate(h.ns.Route().steps[1])
h.flush()
h.providers[1]:RefreshAllData()
out.map = { stops = stops, pins = Pins(h), player = { map = h.player.map, x = h.player.x, y = h.player.y } }

-- The Adventure Guide window (docs/design.md §2.19) after the layout pass, as Panel() does for the panel: rects in,
-- then the refresh its next show would do.
local function Window(each, scene, tab)
	each.ns.OpenWindow()
	each.flush()
	local window = each.G.AdventureGuideForeverWindow
	if tab then
		each.Click(window.Tabs[tab])
		each.flush()
	end
	each.SetRects(window, input.rects[scene] or {})
	window:Hide()
	window:Show()
	each.flush()
	return { layout = each.ns.DumpLayout(window, each.Describe) }
end

-- The Journeys tab for the lead image's character: nothing chosen, the story featured, both asides in Today.
h = Load("v1", false, true, nil, { COUNTERATTACK, HIDDEN_ENEMIES }, {
	tf = { spells = { SPELL, SPELL, SPELL } },
	talents = 1,
})
out.window = Window(h, "window")

-- The Professions tab, SkillUp Forever loaded: the leatherworker's card, steps and reagents, the picker for two;
-- the same asides above.
local skillup = dofile("tests/fixtures/skillup.lua")
h = Load("v1", false, false, STORY, nil, {
	tf = { spells = { SPELL, SPELL, SPELL } },
	talents = 1,
	skillup = { professions = { skillup.LEATHERWORKING, skillup.TAILORING } },
	items = skillup.ITEMS,
})
out.window_professions = Window(h, "window_professions", 2)

local ASIDES = {
	tf = { spells = { SPELL, SPELL, SPELL } },
	talents = 1,
}

-- The PvP tab: client rank progress and every unlocked battleground; Darkspear Islands has no known battlemaster.
h = Load("v1", false, false, STORY, nil, {
	player = { level = 30 },
	battlegrounds = {
		[10] = { { id = 2, name = "Warsong Gulch" } },
		[30] = { { id = 1157, name = "Darkspear Islands" } },
	},
	rank = {
		info = { renownLevel = 2, renownReputationEarned = 1450, renownLevelThreshold = 2500, maxLevel = 14 },
		rewards = { [3] = { { description = "The Horde Tabard" } } },
	},
})
out.window_pvp = Window(h, "window_pvp", 3)

-- The Completion tab, Legacy Forever loaded: The Barrens featured with its categories, its next three objectives, and
-- the next zones as cards.
local function Zone(map, name, done, total, categories, targets)
	return {
		map = map,
		name = name,
		summary = {
			name = name,
			done = done,
			total = total,
			pending = 0,
			questsStatus = "ready",
			complete = false,
			categories = categories,
		},
		targets = targets or {},
	}
end
local function Category(key, done, total, scope)
	return { key = key, scope = scope or "character", done = done, total = total, pending = 0, complete = done == total }
end
local legacy = { summaries = {}, targets = {} }
for _, zone in ipairs({
	Zone(1413, "The Barrens", 41, 96, {
		Category("areas", 14, 22),
		Category("taxis", 2, 2, "account"),
		Category("dungeons", 0, 1),
		Category("reputations", 1, 2),
		Category("quests", 24, 69),
	}, {
		{
			key = "explore:Lushwater Oasis",
			text = "Explore Lushwater Oasis",
			kind = "explore",
			place = { map = 1413, x = 0.47, y = 0.38 },
		},
		{
			key = "instance:43",
			text = "Wailing Caverns",
			kind = "instance",
			place = { map = 1413, x = 0.46, y = 0.36 },
		},
		{ key = "kill:Kolkar", text = "Kolkar Centaur", kind = "kill", quantity = 6, required = 10 },
	}),
	Zone(1442, "Stonetalon Mountains", 3, 58, { Category("areas", 1, 15), Category("quests", 2, 43) }),
	Zone(1411, "Durotar", 52, 60, { Category("areas", 12, 12), Category("quests", 40, 48) }),
}) do
	legacy.summaries[zone.map], legacy.targets[zone.map] = zone.summary, zone.targets
end
h = Load("v1", false, false, STORY, nil, { legacy = legacy })
out.window_completion = Window(h, "window_completion", 4)

-- Neither Tweaks Forever nor Legacy Forever loaded: Ragefire Chasm chosen, its Go to entrance greyed with the note,
-- and the Completion tab's label grey.
h = Load("v1", false, false, "dungeon:389", nil, { charDB = { journey = "dungeon:389", dungeons = true } })
out.window_missing = Window(h, "window_missing")

-- Today with more than fits: three chips and "+2 more", the hearth among them.
h = Load("v1", false, true, nil, { COUNTERATTACK, HIDDEN_ENEMIES }, {
	tf = ASIDES.tf,
	talents = ASIDES.talents,
	setup = function(each)
		for _, aside in ipairs({
			{
				key = "hearth",
				text = each.ns.L.SET_HEARTH:format("Crossroads"),
				icon = "innkeeper",
				place = { map = 1413, x = 0.5145, y = 0.2975 },
			},
			{
				key = "firstaid",
				text = "Learn First Aid in Orgrimmar",
				icon = "profession",
				place = { map = 1454, x = 0.34, y = 0.84 },
			},
			{
				key = "fishing",
				text = "Learn Fishing in Orgrimmar",
				icon = "profession",
				place = { map = 1454, x = 0.69, y = 0.3 },
			},
		}) do
			each.ns.Asides.Register(function()
				return aside
			end)
		end
	end,
})
out.window_today = Window(h, "window_today")

-- A real off-zone hand-in fits 30 minutes, including the provider's travel estimate.
h = Load("v1", false, false, "carry", { HIDDEN_ENEMIES }, ASIDES)
h.spfSeconds = 1480
h.ns.Session.Set(30)
h.flush()
out.window_session = Window(h, "window_session")

-- The same whole task does not fit 15 minutes.
h = Load("v1", false, false, "carry", { HIDDEN_ENEMIES }, ASIDES)
h.spfSeconds = 1480
h.ns.Session.Set(15)
h.flush()
out.window_empty = Window(h, "window_empty")

-- The player's actual custom order and retained giver checklist after accepting one giver's quests.
h = Load("v1", false, false, STORY, nil, ASIDES)
assert(h.ns.Order.Move(2, 1))
h.flush()
local giver = h.ns.Route().steps[1].checklist[1]
for _, id in ipairs(giver.pickups) do
	h.log[#h.log + 1] = { id = id, title = h.ns.Data.quests[id].title, complete = false }
end
h.fire("QUEST_LOG_UPDATE")
h.flush()
out.window_order = Window(h, "window_order")

out.errors = {}
for _, each in ipairs(loaded) do
	for _, err in ipairs(each.errors) do
		out.errors[#out.errors + 1] = err
	end
end
io.write(json.encode(out, "%.10g"))
