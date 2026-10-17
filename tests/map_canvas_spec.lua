-- The world map drawn without writing into it (UI/MapCanvas.lua, docs/design.md §2.6). Forever's gamepad interface
-- walks the map's pin pools and data providers from secure code, so AGF's rings, givers and ping are frames of its
-- own on the canvas: no data provider, no AcquirePin, no field set on the map or its canvas. The harness's
-- WorldMapFrame is a guard that raises on any such write; this spec drives everything the pins do through it and
-- also compares the map's own fields before and after.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual))
end

local h = harness.load({ db = { showMapPins = true, showQuestGivers = true, autoStart = false } })
local ns = h.ns
local map = h.map
local canvas = map.ScrollContainer.Child

-- Every value reachable from the map, three tables deep, by path; a table by identity. The canvas's list of
-- children is left out: the client keeps it, and the one frame AGF parents there is counted below.
local function Snapshot()
	local values, seen = {}, {}
	local function Walk(target, path, depth)
		seen[target] = true
		for key, value in pairs(target) do
			local at = path .. "." .. tostring(key)
			values[at] = value
			if type(value) == "table" and depth > 1 and not seen[value] and value ~= canvas.childFrames then
				Walk(value, at, depth - 1)
			end
		end
	end
	Walk(map, "WorldMapFrame", 3)
	return values
end
local function SameValues(before, after)
	for path, value in pairs(before) do
		equal(after[path], value, path)
	end
	for path in pairs(after) do
		equal(before[path] ~= nil, true, "new value at " .. path)
	end
end
local mapBefore = Snapshot()

-- The map's own pin machinery is not there to call, and the guard raises on it.
for _, name in ipairs({ "AddDataProvider", "AcquirePin", "RemoveAllPinsByTemplate", "SetMapID" }) do
	equal(
		pcall(function()
			return h.G.WorldMapFrame[name]
		end),
		false,
		"WorldMapFrame:" .. name .. " is out of reach"
	)
end
h.counts.mapWrites = 0

-- Calls the pins make, recorded instead of run.
local calls = {}
local function Record(owner, name)
	owner[name] = function(...)
		calls[#calls + 1] = { name = name, args = { ... } }
	end
end
Record(ns, "StartRoute")
Record(ns, "TogglePinned")
Record(ns.Guidance, "Navigate")

-- Opening the map draws the rings and givers on the next frame.
h.G.C_Map.OpenWorldMap(1413)
h.flush()
local rings = h.pins.AdventureGuideForeverPinTemplate
equal(#rings > 0, true, "rings on the route's map")
local ring = rings[1]
equal(ring:GetParent():GetParent():GetParent(), h.guards.canvas, "a ring sits on AGF's layer on the canvas")
for _, pin in ipairs(h.AllPins()) do
	equal(pin:GetObjectType(), "Frame", "a pin is no button")
	for _, script in ipairs({ "OnClick", "OnMouseDown", "OnMouseUp" }) do
		equal(pin:GetScript(script), nil, "a pin has no " .. script .. " script")
	end
end
equal(ring.frameLevelType, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", "rings at the user waypoint's level")
equal(ring:GetFrameLevel(), 1200, "the level the map gives it")

-- Placed in canvas units at its map fractions, the size of the map's own quest buttons at every zoom.
local point = ring.points[1]
equal(point[2], h.guards.canvas, "anchored to the canvas")
equal(math.abs(point[4] - 830 * ring.step.x) < 1e-9, true, "x in canvas units")
equal(math.abs(point[5] + 560 * ring.step.y) < 1e-9, true, "y in canvas units")
equal(ring:GetScale(), 1, "a ring at scale 1 unzoomed")
h.ZoomMap(2, 1)
ring = h.pins.AdventureGuideForeverPinTemplate[1]
equal(ring:GetScale(), 0.5, "a ring keeps its size on screen zoomed in")
equal(math.abs(ring.points[1][4] - 830 * ring.step.x / 0.5) < 1e-9, true, "and its place on the zoomed canvas")
-- Stonetalon: no route step, every eligible giver a "!".
h.map:SetMapID(1442)
local givers = h.pins.AdventureGuideForeverGiverPinTemplate
equal(#givers > 0, true, "givers on another map")
local giver
for _, pin in ipairs(givers) do
	if #pin.giver.adds > 0 then
		giver = pin
		break
	end
end
equal(giver ~= nil, true, "a giver the route can take from")
equal(math.abs(giver:GetScale() - 1.2 / 2) < 1e-9, true, "a giver grows to 1.2 zoomed in")
map.pinScale = 1.5
h.frame()
equal(math.abs(giver:GetScale() - 1.2 / 2 * 1.5) < 1e-9, true, "and follows the map's pin scale")
map.pinScale = 1
h.ZoomMap(1, 0)
equal(giver:GetFrameLevel(), 300, "givers at the area POI level")

-- Clicks: a press and release over the hovered pin. A giver passes the right button through to the map (zoom out).
equal(#giver.passThrough, 1, "a giver passes one button through")
equal(giver.passThrough[1], "RightButton", "the right button")
h.ClickPin(giver, "LeftButton")
equal(calls[#calls].name, "Navigate", "a giver's click goes there")
equal(calls[#calls].args[1], giver.giver, "to that giver")
local count = #calls
h.ClickPin(giver, "RightButton")
equal(#calls, count, "a giver's right click is the map's")
h.Shift(function()
	h.ClickPin(giver, "LeftButton")
end)
equal(calls[#calls].name, "TogglePinned", "a shift-click adds the giver's quests")
equal(calls[#calls].args[1], giver.giver.adds, "the ones the route can take")
-- A press on the pin released off it is no click.
count = #calls
giver.mouseOver = true
h.call(giver.scripts.OnEnter, giver)
h.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
giver.mouseOver = false
h.call(giver.scripts.OnLeave, giver)
h.fire("GLOBAL_MOUSE_UP", "LeftButton")
equal(#calls, count, "a press dragged off the pin does nothing")

-- A ring keeps the right button: it goes back to the story's start.
h.map:SetMapID(1413)
ring = h.pins.AdventureGuideForeverPinTemplate[1]
equal(#ring.passThrough, 0, "a ring passes no button through")
h.ClickPin(ring, "LeftButton")
equal(calls[#calls].name, "StartRoute", "a ring's click starts the route there")
equal(calls[#calls].args[1], ring.step, "at its step")
h.ClickPin(ring, "RightButton")
equal(calls[#calls].name, "StartRoute", "a right click starts it again")
equal(calls[#calls].args[1], nil, "from the story's start")

-- Hovering shows the tooltip, and closing the map takes it, though the client sends no OnLeave.
ring.mouseOver = true
h.call(ring.scripts.OnEnter, ring)
equal(h.G.GameTooltip:IsShown(), true, "a hovered ring's tooltip")
equal(ring.Glow:IsShown(), true, "and its glow")
map:Hide()
equal(h.G.GameTooltip:IsShown(), false, "closing the map takes the tooltip")
equal(ring.Glow:IsShown(), false, "and the glow")
ring.mouseOver = false
-- Closed, nothing of AGF's runs per frame (WFA-13).
local busy = 0
for _, frame in ipairs(h.frames) do
	busy = busy + (frame.scripts.OnUpdate and 1 or 0)
end
equal(busy, 0, "no OnUpdate with the map closed")
equal(#h.G.ForeverMapMarkers.AdventureGuideForever(h.guards.map), 0, "no markers with the map closed")
h.G.C_Map.OpenWorldMap(1413)
h.flush()

-- The other Forever addons see AGF's rings and givers through ForeverMapMarkers.
local markers = h.G.ForeverMapMarkers.AdventureGuideForever(h.guards.map)
local kinds = {}
for _, marker in ipairs(markers) do
	kinds[marker.kind] = (kinds[marker.kind] or 0) + 1
end
equal(kinds.stop, #h.pins.AdventureGuideForeverPinTemplate, "a stop marker per ring")
equal(kinds.giver or 0, #h.pins.AdventureGuideForeverGiverPinTemplate, "a giver marker per giver")
equal(markers[1].x ~= nil and markers[1].y ~= nil, true, "markers carry their place")

-- The reveal ping: the map turned by the client, the ping played twice on AGF's own frame, then gone.
local step = ring.step
ns.Pins.Reveal({ map = 1442, x = 0.4, y = 0.6 })
h.flush()
local ping = h.pins.AdventureGuideForeverPingPinTemplate[1]
equal(ping ~= nil, true, "a ping on the revealed map")
equal(ping.mapX, 0.4, "at the place")
equal(ping:GetFrameLevel(), 1500, "at the quest ping's level")
equal(ping.Fade.plays, 1, "its first pulse")
h.FinishAnimations()
equal(ping.Fade.plays, 2, "its second pulse")
h.FinishAnimations()
equal(ping:IsShown(), false, "then it is gone")
ns.Pins.Reveal({ map = 1413, x = step.x, y = step.y })
h.flush()
ping = h.pins.AdventureGuideForeverPingPinTemplate[1]
equal(ping.mapID, 1413, "a new ping on the map turned to")
h.map:SetMapID(1442)
equal(#h.pins.AdventureGuideForeverPingPinTemplate, 0, "a ping goes with the map it was on")

-- Under the gamepad interface, the pin nearest the map cursor shows its tooltip, as the map's own pins do.
h.G.Enum.InputDeviceInterfaceType = { Gamepad = 2 }
h.G.C_InputInterfaceStyle = {
	GetCurrentStyle = function()
		return 2
	end,
}
map:Hide()
h.G.C_Map.OpenWorldMap(1413)
h.flush()
ring = h.pins.AdventureGuideForeverPinTemplate[1]
ring.rect = { 100, 100, 20, 20 }
local cursor = { shown = true }
function cursor.IsShown()
	return true
end
function cursor.GetRect()
	return 105, 105, 4, 4
end
function cursor.GetEffectiveScale()
	return 1
end
h.G.SoftCursor = cursor
h.G.GameTooltip:Hide()
h.frame()
equal(h.G.GameTooltip:IsShown(), true, "the map cursor on a ring shows its tooltip")
equal(ring.Glow:IsShown(), true, "and lights it")
function cursor.GetRect()
	return 400, 400, 4, 4
end
h.frame()
equal(ring.Glow:IsShown(), false, "moving away leaves it")
h.G.SoftCursor = nil

-- Combat hides every pin at once and draws nothing until it ends.
h.SetCombat(true)
ns.Pins.Refresh()
for _, pin in ipairs(h.AllPins()) do
	equal(pin:IsVisible(), false, "no pin shows in combat")
end
h.SetCombat(false)
equal(h.pins.AdventureGuideForeverPinTemplate[1]:IsVisible(), true, "back after combat")
map:Hide()

-- Through all of it, nothing was written into the map or its canvas.
equal(h.counts.mapWrites, 0, "no write reached the map's guard")
-- The harness's own state, as the client's code would set it: the map ID, zoom and shown state the spec drove.
local after = Snapshot()
for _, key in ipairs({ "mapID", "canvasScale", "zoom", "pinScale", "hidden" }) do
	mapBefore["WorldMapFrame." .. key], after["WorldMapFrame." .. key] = nil, nil
end
SameValues(mapBefore, after)
-- The harness's canvas has no children of its own: AGF's view is its one child, from load on.
equal(#canvas.childFrames, 1, "one frame of AGF's on the canvas")
equal(canvas.childFrames[#canvas.childFrames]:GetObjectType(), "Frame", "the view's own frame")
for _, frame in ipairs(h.frames) do
	if frame.createdParent then
		equal(
			frame.createdParent ~= h.guards.canvas and frame.createdParent ~= canvas,
			true,
			"nothing made on the canvas"
		)
	end
end
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("map_canvas_spec: " .. checks .. " checks passed")
