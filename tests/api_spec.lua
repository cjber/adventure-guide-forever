-- Run from the repository root: luajit tests/api_spec.lua
-- AdventureGuideForever.API answers from the settled route with fresh tables, and never builds one for its caller.
local harness = dofile("tests/harness.lua")
local h = harness.load({
	spf = "ended",
	charDB = { journey = "zone:1413" },
	completed = { 844 },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	},
})
local API = h.G.AdventureGuideForever.API
assert(API.version == 1)
h.ns.Invalidate()
assert(API.CurrentStop() == nil and API.NextStops() == nil, "a route due a rebuild says ask again later")
h.flush()

local step = assert(h.ns.Integrations.CurrentStep())
local steps = h.ns.Route().steps
local stop = assert(API.CurrentStop(), "a settled route answers")
assert(stop.map == step.map and stop.x == step.x and stop.y == step.y, "the tracker's stop")
assert(stop.name == (step.place or step.zone or step.title) and stop.isTown == (step.kind == "town"))
assert(stop.handins == #h.ns.Model.Handins(step) and stop.pickups == #(step.pickups or {}))
stop.map = -1
assert(API.CurrentStop().map == step.map and API.CurrentStop() ~= API.CurrentStop(), "every call copies")

local towns = 0
for _, candidate in ipairs(steps) do
	towns = towns + (candidate.kind == "town" and 1 or 0)
end
assert(#steps >= 3 and towns > 0, "the fixture route needs stops ahead and a town")
local following = API.NextStops()
assert(#following == 2 and following[1].x == steps[2].x and following[2].x == steps[3].x, "two stops ahead by default")
assert(#API.NextStops(1) == 1 and #API.NextStops(0) == 0 and #API.NextStops(100) <= 8, "limit is honoured and capped")
assert(API.NextStops(-1) == nil and API.NextStops(1.5) == nil and API.NextStops("2") == nil, "invalid limits")

local navigations = h.spf.NavigateRoute
h.combat = true
assert(API.CurrentStop().x == step.x, "combat still reads the committed route")
h.combat = false
assert(h.spf.NavigateRoute == navigations, "reads never start guidance")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("api_spec: CurrentStop and NextStops copy the settled route's stops")
