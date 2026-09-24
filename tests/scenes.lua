-- Run from the repository root: luajit tests/scenes.lua [input.json]
-- What tools/screenshots.py draws, taken from the addon through tests/harness.lua (docs/plan.md §1.3), so no AGF
-- text or layout is retyped in Python. Not a spec: it checks nothing and prints one JSON object.
--
-- input.json comes from screenshots.py's layout pass: `rects` (per scene, a path -> {left, bottom, width, height}
-- map it resolved from the previous run). With no input the panel is exactly tests/golden/layout.json, which
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
-- The character chose the carry card before, as ui_spec's has, or `journey`; `fresh` has chosen nothing yet.
-- `carried` adds a finished quest to the log.
local function Load(spf, optIn, fresh, journey, carried)
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
	}
	log[#log + 1] = carried
	local h = harness.load({
		spf = spf or nil,
		db = optIn and { showMapPins = true, showQuestGivers = true } or nil,
		charDB = not fresh and { journey = journey or "carry" } or nil,
		completed = { 844 },
		log = log,
	})
	loaded[#loaded + 1] = h
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

local function Pins(h)
	local pins = {}
	for _, template in ipairs({ "AdventureGuideForeverGiverPinTemplate", "AdventureGuideForeverPinTemplate" }) do
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

-- The lead image: the story card's towns, with Shortest Path's minutes on step 1 (ui_spec's golden layout).
local STORY = "story:1413"
local h = Load("v1", false, false, STORY)
out.panel = Panel(h, "panel")
h.providers[1]:RefreshAllData()
out.panel.pins = Pins(h)
out.panel.map = h.map:GetMapID()

-- A character with no card chosen: every card whole, no steps and no rings, the hint under the cards. With Shortest
-- Path's minutes on each card, and a finished group quest, Counterattack!, handed in at Regthar Deathgate's camp, so
-- the carry card's hub line has the group tag beside it.
local COUNTERATTACK =
	{ id = 4021, title = "Counterattack!", level = 20, complete = true, map = 1413, x = 0.4534, y = 0.2841 }
h = Load("v1+", false, true, nil, COUNTERATTACK)
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

-- With Shortest Path loaded, on the story card: a town ring's tooltip and the tracker's town lines; then, on the carry
-- card, the tracker's menu and the route handed to Shortest Path.
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
h.ns.Prefs().journey = "carry"
h.ns.Invalidate()
h.flush()
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
h.ns.Integrations.Navigate(h.ns.Route().steps[1])
h.flush()
h.providers[1]:RefreshAllData()
out.map = { stops = stops, pins = Pins(h), player = { map = h.player.map, x = h.player.x, y = h.player.y } }

out.errors = {}
for _, each in ipairs(loaded) do
	for _, err in ipairs(each.errors) do
		out.errors[#out.errors + 1] = err
	end
end
io.write(json.encode(out, "%.10g"))
