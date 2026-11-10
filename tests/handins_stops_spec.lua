-- Run from the repository root: luajit tests/handins_stops_spec.lua
-- A town step's hand-ins reach Shortest Path as the stop's handins (#475, cjber/shortest-path-forever#484), so the
-- game's own "?" pin steps aside there; a town with none sends no field, and an area step still sends its objective
-- quests and shapes as before.
local harness = dofile("tests/harness.lua")

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local h = harness.load({ spf = "v1" })
h.flush()

-- A town where one quest is handed in and another picked up: only the hand-in reaches Shortest Path, copied, so a
-- later edit to the step changes nothing.
local town = {
	kind = "town",
	key = "town:1413:380",
	title = "Town",
	place = "Goldshire",
	map = 1413,
	x = 0.5,
	y = 0.5,
	z = 96,
	quests = { 843, 845 },
	pickups = { 843 },
	handins = { 845 },
}
assert(h.ns.Integrations.Hand({ town }, true), "a town step is handed over")
local stop = h.spfRoute.stops[1]
equal(stop.z, 96, "a town at one spawn sends its world height")
equal(stop.handins and stop.handins[1], 845, "the town's hand-in reaches Shortest Path")
equal(#stop.handins, 1, "and only the hand-ins it names")
town.handins[1] = 999
equal(stop.handins[1], 845, "the step's later edit changes nothing")
equal(stop.questID, nil, "a town stop names no objective quest")
equal(stop.questIDs, nil, "and no objective area")

-- A town with no hand-ins sends no handins field at all, so a Shortest Path that does not know it keeps working.
local pickup = {
	kind = "town",
	key = "town:1413:381",
	title = "Town",
	map = 1413,
	x = 0.5,
	y = 0.5,
	quests = { 843 },
	pickups = { 843 },
	handins = {},
}
assert(h.ns.Integrations.Hand({ pickup }, false), "a pickup-only town is handed over")
equal(h.spfRoute.stops[1].handins, nil, "an empty hand-in list sends nothing")

-- An area step still sends its objective quests and shapes as before.
local area = {
	kind = "area",
	key = "area:844:12",
	title = "Area",
	map = 1413,
	x = 0.5,
	y = 0.5,
	quests = { 844 },
	shapes = { { map = 1413, x = 0.5, y = 0.5, r = 40 } },
}
assert(h.ns.Integrations.Hand({ area }, true), "an area step is handed over")
local areaStop = h.spfRoute.stops[1]
equal(areaStop.questID, 844, "the area's one quest reaches Shortest Path")
equal(areaStop.questIDs and areaStop.questIDs[1], 844, "and its quest list as before")
equal(areaStop.shapes and areaStop.shapes[1].radius, 40, "and its shape as before")
equal(areaStop.handins, nil, "an area sends no hand-ins")
equal(areaStop.z, nil, "an objective area over many spawns sends no height")

-- A town that moves to another of its givers moves that giver's height with it.
local Travel = h.ns.Planner.Travel
local nearTown = {
	quests = { 1, 2 },
	spots = {
		[1] = { map = 1413, x = 0.2, y = 0.2, z = 11 },
		[2] = { map = 1413, x = 0.8, y = 0.8, z = 22 },
	},
	map = 1413,
	x = 0.5,
	y = 0.5,
}
h.ns.Planner.Steps.TownPoint(h.ns.Data, nearTown, Travel.Position(h.ns.Data, { map = 1413, x = 0.1, y = 0.1 }))
equal(nearTown.z, 11, "a town keeps the height of the giver it points at")

assert(#h.errors == 0, "errors: " .. table.concat(h.errors, "\n"))
print(("handins_stops_spec: %d checks passed"):format(checks))
