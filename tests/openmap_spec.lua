-- Run from the repository root: luajit tests/openmap_spec.lua
-- OpenMap stitches the world map's neighbouring zones onto one canvas (#514). While it does, the guide draws route
-- stops from those zones at their place on that canvas; without OpenMap, with another major version, or while it is
-- not stitching, it draws the shown map's own stops exactly as before.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local A, B = 1413, 1414

-- Two neighbouring zones side by side: A covers the stitched world's left half and B its right half. A point on B at
-- 0.2 is a fifth of the way past A's right edge, at 1.2 in A's fractions.
local function FakeOpenMap(major)
	local fake = { major = major or 1, version = 1, callbacks = {} }
	local stitched = true
	fake.IsStitched = function()
		return stitched
	end
	fake.WorldFromMap = function(mapID, x, y)
		if mapID == A then
			return x * 0.5, y
		elseif mapID == B then
			return 0.5 + x * 0.5, y
		end
	end
	fake.MapFromWorld = function(mapID, u, v)
		if mapID == A then
			return u / 0.5, v
		elseif mapID == B then
			return (u - 0.5) / 0.5, v
		end
	end
	function fake.RegisterCallback(owner, event, method)
		fake.callbacks[#fake.callbacks + 1] = { owner = owner, event = event, method = method }
	end
	---@param h table
	function fake.Fire(h, value)
		stitched = value
		for _, entry in ipairs(fake.callbacks) do
			h.call(entry.method, entry.event, value)
		end
	end
	return fake
end

local function Step(key, map, x, y, here)
	return {
		key = key,
		kind = "area",
		title = key,
		detail = "",
		reason = "",
		quests = {},
		map = map,
		x = x,
		y = y,
		here = here,
	}
end

local h = harness.load({
	db = { showMapPins = true, showQuestGivers = false },
	player = { map = A, x = 0.5, y = 0.5 },
})
h.flush()

local fake = FakeOpenMap(1)
h.G.OpenMapAPI = fake
-- OpenMap may load after us: the guide registers when its add-on loads, then redraws from its callback.
h.fire("ADDON_LOADED", "OpenMap")
equal(#fake.callbacks, 1, "registers once with OpenMap")
equal(fake.callbacks[1].event, "OpenMap_StitchedChanged", "registers for stitching changes")

local route = {
	steps = {},
	journeys = {},
	chosen = true,
	journey = "test",
}
h.ns.Route = function()
	return route
end

local host = Step("host", A, 0.2, 0.4)
local neighbour = Step("neighbour", B, 0.2, 0.4)
local here = Step("here", B, 0.6, 0.4, true)
route.steps = { host, neighbour, here }

h.G.C_Map.OpenWorldMap(A)
h.flush()

local function RoutePins()
	return h.Pins("AdventureGuideForeverPinTemplate")
end

local function PinFor(step)
	for _, pin in ipairs(RoutePins()) do
		if pin.step == step then
			return pin
		end
	end
end

-- Not stitching: only the shown map's own stop draws, as before.
fake.Fire(h, false)
equal(#RoutePins(), 1, "not stitched: only the host map's stop")
equal(PinFor(host) ~= nil, true, "not stitched: the host map's stop draws")

-- Stitched: the neighbouring zone's stop draws at its place on the canvas, with its own number, and the player's own
-- spot draws nothing.
fake.Fire(h, true)
equal(#RoutePins(), 2, "stitched: the neighbouring stop draws too")
local neighbourPin = PinFor(neighbour)
equal(neighbourPin ~= nil, true, "stitched: the neighbouring stop has a pin")
equal(neighbourPin and neighbourPin.mapX, 1.2, "stitched: placed in the host map's fractions")
equal(neighbourPin and neighbourPin.mapY, 0.4, "stitched: placed in the host map's fractions")
equal(neighbourPin and neighbourPin.index, 2, "stitched: keeps its own route number")
equal(PinFor(here), nil, "stitched: the player's own spot draws nothing")

-- Two stops that meet on the stitched canvas group into one pin, though they are on different maps.
local edgeHost = Step("edge-host", A, 1.0, 0.4)
local edgeNeighbour = Step("edge-neighbour", B, 0.0, 0.4)
route.steps = { edgeHost, edgeNeighbour }
fake.Fire(h, true)
local pins = RoutePins()
equal(#pins, 1, "stitched: stops meeting on the canvas share one pin")
equal(pins[1].step, edgeHost, "stitched: the pin keeps the first visit")
equal(pins[1].index, 1, "stitched: numbered for its first visit")
equal(#(pins[1].visits or {}), 2, "stitched: both visits are on the pin")

-- Stitching stopping redraws with the shown map's stops only.
route.steps = { host, neighbour, here }
fake.Fire(h, true)
equal(#RoutePins(), 2, "stitched again: the neighbouring stop returns")
fake.Fire(h, false)
equal(#RoutePins(), 1, "stitching stopped: the neighbouring stop goes")

-- No OpenMap, or another major version: draw as before.
h.G.OpenMapAPI = nil
h.ns.Pins.Refresh()
equal(#RoutePins(), 1, "absent OpenMap: only the host map's stop")
fake.major = 2
h.G.OpenMapAPI = fake
h.ns.Pins.Refresh()
equal(#RoutePins(), 1, "another major version: only the host map's stop")

-- A failing OpenMap read is reported through ns.core.SafeCall, and the host map's stops stay drawn.
fake.major = 1
h.G.OpenMapAPI = fake
fake.Fire(h, true)
local read = fake.WorldFromMap
fake.WorldFromMap = function()
	error("openmap boom", 0)
end
local before = #h.errors
h.ns.Pins.Refresh()
equal(#RoutePins(), 1, "a failing read leaves the host map's stop drawn")
equal(PinFor(neighbour), nil, "a failing read draws no neighbouring stop")
equal(#h.errors, before + 1, "a failing read is reported, not raised")
equal(h.errors[#h.errors]:find("openmap boom", 1, true) ~= nil, true, "the report names the failure")
fake.WorldFromMap = read

assert(#h.errors == before + 1, "errors: " .. table.concat(h.errors, "\n"))
print(("openmap_spec: %d checks passed"):format(checks))
