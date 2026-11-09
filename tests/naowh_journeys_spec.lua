-- Run from the repository root: luajit tests/naowh_journeys_spec.lua
-- Naowh's Journeys (NaowhForever_Utilities' Journeys module) turns a new native waypoint that is not its own into a
-- journey, when its "Map Pins" option is on. The guide yields its waypoint to that journey (#304): Go still puts the
-- native waypoint down, Naowh moves it to the journey's first leg, and while the journey heads for Go's place the
-- guide counts its guidance as running. Stop then clears the native waypoint, which ends the journey.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end
local function near(actual, expected, label)
	checks = checks + 1
	if math.abs(actual - expected) >= 1e-4 then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
}

-- A stand-in for Naowh's Journeys module (Journeys/Pins.lua). The real module hears USER_WAYPOINT_UPDATED and starts,
-- a frame on, a journey to a new native waypoint that is not its own: the journey's last stop is that point in
-- percent, and the native waypoint moves to the journey's first leg, another point. Each call is recorded.
---@param h table
---@param options? {on?: boolean, mapPins?: boolean, legMap?: integer}
local function Naowh(h, options)
	options = options or {}
	local state = {
		on = options.on ~= false,
		mapPins = options.mapPins ~= false,
		leg = { map = options.legMap or 1413, x = 0.10, y = 0.20 },
		started = 0,
		-- The journey's last stop: map, and x and y in percent, as Guide.Destination answers it.
		destination = nil,
	}
	-- A point the module made itself: a new waypoint there starts no journey, as Ours does in the real module.
	local function ours(point)
		return point.uiMapID == state.leg.map
			and math.abs(point.position.x - state.leg.x) < 1e-4
			and math.abs(point.position.y - state.leg.y) < 1e-4
	end
	local function start(point)
		if not (state.on and state.mapPins) or ours(point) then
			return
		end
		state.destination = { map = point.uiMapID, x = point.position.x * 100, y = point.position.y * 100 }
		state.started = state.started + 1
		-- Its first leg moves the native waypoint, so it no longer sits where Go put it.
		h.waypoint = h.G.UiMapPoint.CreateFromCoordinates(state.leg.map, state.leg.x, state.leg.y)
	end
	local set = h.G.C_Map.SetUserWaypoint
	h.G.C_Map.SetUserWaypoint = function(point)
		local result = set(point)
		-- USER_WAYPOINT_UPDATED, then C_Timer.After(0, Start), as the real module runs.
		h.G.C_Timer.After(0, function()
			start(point)
		end)
		return result
	end
	h.G.NaowhForever = {
		Journeys = {
			On = function()
				return state.on
			end,
			Settings = {
				Get = function(key)
					return key == "mapPins" and state.mapPins or nil
				end,
			},
			Guide = {
				Destination = function()
					local destination = state.destination
					return destination and destination.map, destination and destination.x, destination and destination.y
				end,
			},
		},
	}
	return state
end

-- A chosen zone story, auto-start off so each case starts the route itself. `naowh` is Naowh's options, or false to
-- leave the addon absent.
local function load(extra, naowh)
	local options = {
		planned = true,
		db = { autoStart = false },
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = LOG,
	}
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	local log = {}
	for index, entry in ipairs(options.log) do
		local copy = {}
		for key, value in pairs(entry) do
			copy[key] = value
		end
		log[index] = copy
	end
	options.log = log
	options.setup = function(h)
		if naowh ~= false then
			h.naowh = Naowh(h, naowh)
		end
	end
	local h = harness.load(options)
	h.flush()
	return h
end

local function errorFree(h, label)
	assert(#h.errors == 0, label .. ": " .. table.concat(h.errors, "\n"))
end

-- The player or another addon moves the native waypoint elsewhere, as Naowh's first leg does.
local function moveAway(h, map, x, y)
	h.waypoint = h.G.UiMapPoint.CreateFromCoordinates(map or 1413, x or 0.10, y or 0.20)
end

-- Naowh Journeys on with map pins: Go puts the waypoint down, Naowh starts its journey and moves the waypoint to the
-- first leg, and the guide still owns its guidance. Stop clears the native waypoint, ending the journey.
do
	local h = load()
	local state = h.naowh
	local first = h.ns.Route().steps[1]
	equal(h.ns.StartRoute(), true, "the chosen journey starts")
	h.flush()
	equal(h.counts.SetUserWaypoint, 1, "Go puts the native waypoint down")
	equal(state.started, 1, "Naowh starts a journey to that place")
	equal(state.destination.map, first.map, "the journey heads for the stop's map")
	near(state.destination.x, first.x * 100, "and its x in percent")
	near(state.destination.y, first.y * 100, "and its y in percent")
	near(h.waypoint.position.x, state.leg.x, "Naowh moved the waypoint to its first leg")
	near(h.waypoint.position.y, state.leg.y, "on a different point")
	equal(h.ns.Guidance.Owns(), true, "the journey counts as the guide's guidance")
	equal(h.ns.Guidance.Status(), nil, "so the guide is not paused")
	h.ns.Stop()
	equal(h.counts.ClearUserWaypoint, 1, "Stop clears the native waypoint")
	equal(h.waypoint, nil, "which ends Naowh's journey on a non-arrival clear")
	equal(h.ns.Prefs().waypoint, nil, "nothing records the waypoint as ours")
	errorFree(h, "yielded guidance")
end

-- The chosen journey's step 1 moves: Follow sets the waypoint at the new step, which ends Naowh's old journey and
-- starts a new one to that place.
do
	local h = load()
	local state = h.naowh
	local first = h.ns.Route().steps[1]
	equal(h.ns.StartRoute(), true, "the chosen journey starts")
	h.flush()
	equal(state.started, 1, "Naowh guides the first stop")
	h.ns.Skip(first.key, first.title)
	h.flush()
	local nextStep = h.ns.Route().steps[1]
	assert(nextStep.key ~= first.key, "the skipped stop left the route")
	equal(h.counts.SetUserWaypoint, 2, "Follow moves the waypoint to the new step")
	equal(state.started, 2, "which starts Naowh's journey to it")
	equal(state.destination.map, nextStep.map, "the new journey heads for its map")
	near(state.destination.x, nextStep.x * 100, "and its x in percent")
	near(state.destination.y, nextStep.y * 100, "and its y in percent")
	near(h.waypoint.position.x, state.leg.x, "Naowh moved the waypoint to the new leg")
	equal(h.ns.Guidance.Owns(), true, "the new journey is the guide's guidance")
	errorFree(h, "follow")
end

-- Naowh Journeys off: a moved waypoint is not ours, as before.
do
	local h = load(nil, { on = false })
	local state = h.naowh
	equal(h.ns.StartRoute(), true, "the chosen journey starts")
	h.flush()
	equal(state.started, 0, "a stopped module starts no journey")
	moveAway(h)
	equal(h.ns.Guidance.Owns(), false, "a waypoint moved elsewhere is not ours")
	equal(h.ns.Guidance.Status(), "paused", "so the guide is paused")
	errorFree(h, "Naowh off")
end

-- Map pins off: its journeys are off too, so a moved waypoint is not ours.
do
	local h = load(nil, { mapPins = false })
	local state = h.naowh
	equal(h.ns.StartRoute(), true, "the chosen journey starts")
	h.flush()
	equal(state.started, 0, "map pins off starts no journey")
	moveAway(h)
	equal(h.ns.Guidance.Owns(), false, "a waypoint moved elsewhere is not ours")
	equal(h.ns.Guidance.Status(), "paused", "so the guide is paused")
	errorFree(h, "map pins off")
end

-- NaowhForever absent: a moved waypoint is not ours, as before.
do
	local h = load(nil, false)
	equal(h.ns.StartRoute(), true, "the chosen journey starts")
	h.flush()
	moveAway(h)
	equal(h.ns.Guidance.Owns(), false, "a waypoint moved elsewhere is not ours")
	equal(h.ns.Guidance.Status(), "paused", "so the guide is paused")
	errorFree(h, "Naowh absent")
end

-- A Naowh journey to some other place (the player's own pin) is not ours.
do
	local h = load()
	local state = h.naowh
	equal(h.ns.StartRoute(), true, "the chosen journey starts")
	h.flush()
	equal(h.ns.Guidance.Owns(), true, "Naowh guides our place")
	state.destination = { map = 1413, x = 15, y = 25 }
	moveAway(h, 1413, 0.15, 0.25)
	equal(h.ns.Guidance.Owns(), false, "a journey to the player's own pin is not ours")
	equal(h.ns.Guidance.Status(), "paused", "so the guide is paused")
	errorFree(h, "player pin")
end

print(("naowh_journeys_spec: %d checks passed"):format(checks))
