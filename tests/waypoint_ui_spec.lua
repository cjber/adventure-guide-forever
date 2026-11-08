-- Run from the repository root: luajit tests/waypoint_ui_spec.lua
-- Waypoint UI (github.com/Adaptvx/Waypoint-UI) drives the client's own user waypoint. Without Shortest Path, the guide
-- hands its next stop to Waypoint UI's navigation, so its arrow and pin steer; with Shortest Path loaded its journey is
-- the one Waypoint UI follows, and the guide keeps to the native waypoint.
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

-- A chosen zone story, auto-start off so each case starts the route itself. Each case gets its own log, since one
-- moves it on.
local function load(extra, withoutWaypointUI)
	local options = {
		planned = true,
		db = { autoStart = false },
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = LOG,
	}
	if not withoutWaypointUI then
		options.waypointui = true
	end
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
	local h = harness.load(options)
	h.flush()
	return h
end

local function errorFree(h, label)
	assert(#h.errors == 0, label .. ": " .. table.concat(h.errors, "\n"))
end

-- Go hands the stop over with the name, map and percent point Waypoint UI's API takes, and never writes the client's
-- waypoint itself.
do
	local h = load()
	local step = h.ns.Route().steps[1]
	equal(h.ns.Guidance.Navigate(step), true, "Go guides the step")
	equal(#h.waypointUI.newCalls, 1, "one handover")
	local call = h.waypointUI.newCalls[1]
	equal(call.name, step.place or step.zone or step.title, "the handover names the stop")
	equal(call.mapID, step.map, "the handover carries the stop's map")
	near(call.x, step.x * 100, "x reaches Waypoint UI as percent")
	near(call.y, step.y * 100, "y reaches Waypoint UI as percent")
	equal(h.counts.SetUserWaypoint, 0, "the guide never writes the waypoint Waypoint UI tracks")
	equal(h.waypoint and h.waypoint.uiMapID, step.map, "Waypoint UI put the client's waypoint on the stop's map")
	near(h.waypoint.position.x, step.x, "the native waypoint sits on the stop")
	near(h.waypoint.position.y, step.y, "the native waypoint sits on the stop")
	equal(h.superTracked, true, "Waypoint UI tracks the stop")
	equal(h.ns.Guidance.Owns(), true, "the guide knows the navigation is its own")
	errorFree(h, "handover")
end

-- Stop clears the navigation through Waypoint UI's own call, leaving no guessed native clear behind it.
do
	local h = load()
	h.ns.Guidance.Navigate(h.ns.Route().steps[1])
	h.ns.Stop()
	equal(h.waypointUI.cleared, 1, "Stop clears the navigation through Waypoint UI")
	equal(h.waypointUI.navigation, nil, "no navigation is left")
	equal(h.counts.ClearUserWaypoint, 0, "the guide never clears the client's waypoint over Waypoint UI")
	equal(h.waypoint, nil, "the waypoint goes")
	equal(h.superTracked, false, "and its tracking")
	equal(h.ns.Prefs().waypoint, nil, "nothing records the waypoint as ours")
	errorFree(h, "stop")
end

-- A step leaves the route: the next one is handed over, replacing the navigation rather than clearing it first.
do
	local h = load()
	local first = h.ns.Route().steps[1]
	equal(h.ns.StartRoute(), true, "the chosen journey starts")
	h.flush()
	equal(#h.waypointUI.newCalls, 1, "the first stop is handed over")
	h.ns.Skip(first.key, first.title)
	h.flush()
	local nextStep = h.ns.Route().steps[1]
	assert(nextStep.key ~= first.key, "the skipped stop left the route")
	equal(#h.waypointUI.newCalls, 2, "the new first stop is handed over")
	local call = h.waypointUI.newCalls[2]
	equal(call.mapID, nextStep.map, "the new handover carries its map")
	near(call.x, nextStep.x * 100, "and its point")
	near(call.y, nextStep.y * 100, "and its point")
	equal(h.counts.SetUserWaypoint, 0, "the guide still never writes the waypoint directly")
	equal(h.ns.Guidance.Owns(), true, "the new navigation is still the guide's")
	equal(h.waypointUI.cleared, 0, "a step change replaces the navigation instead of clearing it first")
	errorFree(h, "next step")
end

-- With Shortest Path loaded its journey is the one Waypoint UI follows: the guide hands over nothing, so the two
-- addons never steer one waypoint against each other.
do
	local h = load({ spf = "v1" })
	local step = h.ns.Route().steps[1]
	equal(h.ns.Guidance.Navigate(step), true, "Shortest Path guides")
	equal(h.spf.NavigateRoute, 1, "the route goes to Shortest Path")
	equal(#h.waypointUI.newCalls, 0, "the guide hands nothing to Waypoint UI while Shortest Path runs")
	equal(h.counts.SetUserWaypoint, 0, "and writes no waypoint of its own")
	errorFree(h, "with Shortest Path")
end

-- Without Waypoint UI the client's own waypoint still guides, as it did before.
do
	local h = load(nil, true)
	local step = h.ns.Route().steps[1]
	equal(h.ns.Guidance.Navigate(step), true, "the native waypoint guides")
	equal(h.counts.SetUserWaypoint, 1, "the native waypoint is written")
	near(h.waypoint.position.x, step.x, "on the stop")
	equal(h.superTracked, true, "and tracked")
	errorFree(h, "without Waypoint UI")
end

-- Waypoint UI's addon says it is loaded, not just its global table: an API left behind by a disabled addon is no
-- navigation the guide can steer.
do
	local h = load()
	h.metadata.WaypointUI = nil
	equal(h.ns.Guidance.Navigate(h.ns.Route().steps[1]), true, "the native waypoint guides")
	equal(#h.waypointUI.newCalls, 0, "an addon that is not loaded is not handed anything")
	equal(h.counts.SetUserWaypoint, 1, "the native waypoint is written")
	errorFree(h, "Waypoint UI not loaded")
end

-- An API the guide cannot clear is not used either: a navigation it left behind would outlive the step.
do
	local h = load()
	h.G.WaypointUIAPI.Navigation.ClearUserNavigation = nil
	equal(h.ns.Guidance.Navigate(h.ns.Route().steps[1]), true, "the native waypoint guides")
	equal(#h.waypointUI.newCalls, 0, "an API that cannot clear is not handed anything")
	equal(h.counts.SetUserWaypoint, 1, "the native waypoint is written")
	errorFree(h, "no ClearUserNavigation")
end

-- A handover that raises is contained, and the native waypoint keeps Go working.
do
	local h = load()
	h.G.WaypointUIAPI.Navigation.NewUserNavigation = function()
		error("renamed member")
	end
	equal(h.ns.Guidance.Navigate(h.ns.Route().steps[1]), true, "guidance continues")
	equal(h.counts.SetUserWaypoint, 1, "a raised handover falls back to the native waypoint")
	assert(#h.errors >= 1, "the contained failure is reported")
end

-- A navigation the player moved elsewhere is theirs: Stop clears only the client's waypoint the guide set.
do
	local h = load()
	h.ns.Guidance.Navigate(h.ns.Route().steps[1])
	h.waypointUI.navigation = { mapID = 1413, x = 20, y = 10 }
	h.ns.Stop()
	equal(h.waypointUI.cleared, 0, "a navigation moved elsewhere is not cleared")
	equal(h.counts.ClearUserWaypoint, 1, "the guide clears only its own client waypoint")
	errorFree(h, "player navigation")
end

print(("waypoint_ui_spec: %d checks passed"):format(checks))
