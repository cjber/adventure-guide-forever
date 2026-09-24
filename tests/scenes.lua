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
local function Load(spf)
	local h = harness.load({
		spf = spf or nil,
		-- The map scenes show the marks a player opts into (both are off by default).
		db = { showMapPins = true, showQuestGivers = true },
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
		},
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
		lines[index] = { kind = kind, text = text }
	end
	return lines
end

local out = {}

local h = Load(false)
out.panel = Panel(h, "panel")
h.providers[1]:RefreshAllData()
out.panel.pins = Pins(h)
out.panel.map = h.map:GetMapID()

-- The search: the Call of quests a level-18 orc shaman sees, the locked ones saying why.
h = Load(false)
h.ns.Prefs().journey = "story:1413"
h.ns.Invalidate()
h.flush()
local search = h.Find(function(frame)
	return frame.stockTemplate == "SearchBoxTemplate"
end)[1]
h.Type(search, QUERY)
out.search = Panel(h, "search")

-- With Shortest Path loaded: the ring's tooltip, the tracker and its menu, then the route handed to Shortest Path.
h = Load("v1")
h.G.OpenQuestLog()
h.flush()
h.providers[1]:RefreshAllData()
-- Ring 2, the carried objective: ring 1, the turn-in, sits under the player's arrow at the fixture's position.
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
