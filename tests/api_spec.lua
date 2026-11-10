-- Run from the repository root: luajit tests/api_spec.lua
-- AdventureGuideForever.API answers from the settled route with fresh tables, and never builds one for its caller.
-- Minor 5 adds each stop's kind and quest IDs, and Status, Pause and Resume. Minor 6 adds each read's not-ready
-- reason and builds Subscribe on ForeverCore.APIKit.Hub.
local harness = dofile("tests/harness.lua")

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function same(actual, expected, label)
	equal(#actual, #expected, label .. ": length")
	for index = 1, #expected do
		equal(actual[index], expected[index], label .. ": item " .. index)
	end
end

-- A fresh ascending copy of `ids`, as every stop's quest list is.
local function sorted(ids)
	local copy = {}
	for index, id in ipairs(ids) do
		copy[index] = id
	end
	table.sort(copy)
	return copy
end

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
equal(API.version, 1, "still version 1")
equal(API.minor, 6, "minor 6 is the not-ready reasons and the shared subscription hub")
h.ns.Invalidate()
local loadingStop, loadingStopReason = API.CurrentStop()
local loadingNext, loadingNextReason = API.NextStops()
local loadingStatus, loadingStatusReason = API.Status()
local loadingSuggestions, loadingSuggestionsReason = API.Suggestions()
equal(loadingStop, nil, "a route due a rebuild has no current stop")
equal(loadingStopReason, "loading", "and says to ask again later")
equal(loadingNext, nil, "nor any stop after it")
equal(loadingNextReason, "loading", "and says to ask again later")
equal(loadingStatus, nil, "a route due a rebuild has no status")
equal(loadingStatusReason, "loading", "and says to ask again later")
equal(loadingSuggestions, nil, "nor suggestions")
equal(loadingSuggestionsReason, "loading", "and says to ask again later")
equal(API.Pause(), false, "nor can it pause")
equal(API.Resume(), false, "nor resume")
h.flush()

local step = assert(h.ns.Guidance.CurrentStep())
local steps = h.ns.Route().steps
local stop = assert(API.CurrentStop(), "a settled route answers")
equal(stop.map, step.map, "the tracker's stop: map")
equal(stop.x, step.x, "the tracker's stop: x")
equal(stop.y, step.y, "the tracker's stop: y")
equal(stop.name, step.place or step.zone or step.title, "the tracker's stop: name")
equal(stop.isTown, step.kind == "town", "the tracker's stop: town")
equal(stop.kind, step.verb or step.kind, "the tracker's stop: kind")
same(stop.pickupQuests, sorted(step.pickups or {}), "the current stop's pickups")
same(stop.turninQuests, sorted(h.ns.Model.Handins(step)), "the current stop's hand-ins")
same(stop.objectiveQuests, sorted(h.ns.Model.Objectives(step)), "the current stop's objectives")
equal(stop.pickups, #stop.pickupQuests, "the pickup count agrees with its quests")
equal(stop.handins, #stop.turninQuests, "the hand-in count agrees with its quests")
local firstPickup = stop.pickupQuests[1]
assert(firstPickup, "the fixture's first stop picks a quest up")
stop.pickupQuests[1] = -1
equal(API.CurrentStop().pickupQuests[1], firstPickup, "every call copies every list")
assert(API.CurrentStop() ~= API.CurrentStop(), "every call is fresh")

local towns = 0
for _, candidate in ipairs(steps) do
	towns = towns + (candidate.kind == "town" and 1 or 0)
end
assert(#steps >= 3 and towns > 0, "the fixture route needs stops ahead and a town")
local following = API.NextStops()
equal(#following, 2, "two stops ahead by default")
equal(following[1].x, steps[2].x, "the first stop ahead")
equal(following[2].x, steps[3].x, "and the next")
for index, ahead in ipairs(following) do
	local candidate = steps[index + 1]
	equal(ahead.kind, candidate.verb or candidate.kind, "ahead " .. index .. ": kind")
	same(ahead.pickupQuests, sorted(candidate.pickups or {}), "ahead " .. index .. ": pickups")
	same(ahead.turninQuests, sorted(h.ns.Model.Handins(candidate)), "ahead " .. index .. ": hand-ins")
	same(ahead.objectiveQuests, sorted(h.ns.Model.Objectives(candidate)), "ahead " .. index .. ": objectives")
end
equal(#API.NextStops(1), 1, "one stop ahead is honoured")
equal(#API.NextStops(0), 0, "none ahead is honoured")
equal(#API.NextStops(100) <= 8, true, "the limit is capped")
local invalidLimit, invalidReason = API.NextStops(-1)
equal(invalidLimit, nil, "a negative limit is invalid")
equal(invalidReason, nil, "an invalid argument is no not-ready reason")
equal(API.NextStops(1.5), nil, "a fractional limit is invalid")
equal(API.NextStops("2"), nil, "a string limit is invalid")

local navigations = h.spf.NavigateRoute
h.combat = true
equal(API.CurrentStop().x, step.x, "combat still reads the committed route")
h.combat = false
equal(h.spf.NavigateRoute, navigations, "reads never start guidance")

-- Status, Pause and Resume: a running route pauses without losing the choice, and resumes as the card does.
equal(API.Status(), "running", "the started route reports running")
local journey = h.ns.Prefs().journey
equal(API.Pause(), true, "pause accepts a chosen journey")
h.flush()
equal(API.Status(), "paused", "pause leaves the route paused")
equal(h.ns.Prefs().journey, journey, "pause keeps the choice")
equal(h.ns.Route().chosen, true, "pause keeps the journey chosen")
equal(API.Resume(), true, "resume accepts a paused journey")
h.flush()
equal(API.Status(), "running", "resume runs the route again")
h.SetCombat(true)
equal(h.ns.StartRoute(), true, "a start in combat waits")
equal(API.Status(), "queued", "a waiting start is queued")
h.SetCombat(false)
h.flush()
equal(API.Status(), "running", "and then runs")
h.ns.Choose(nil)
h.flush()
local noChoice, noChoiceReason = API.Status()
equal(noChoice, nil, "no chosen journey, no status")
equal(noChoiceReason, "none", "no chosen journey, nothing to answer")
equal(API.Pause(), false, "pause needs a choice")
equal(API.Resume(), false, "resume needs a choice")

-- A settled route with no stop to read says "none", as the kit's convention asks.
local realRoute, realSettled = h.ns.Route, h.ns.RouteSettled
h.ns.RouteSettled = function()
	return true
end
h.ns.Route = function()
	return { chosen = false, journeys = {}, steps = {} }
end
local noStop, noStopReason = API.CurrentStop()
local noNext, noNextReason = API.NextStops()
equal(noStop, nil, "a settled route with no steps has no current stop")
equal(noStopReason, "none", "and nothing to answer")
equal(noNext, nil, "nor any stop after it")
equal(noNextReason, "none", "and nothing to answer")
h.ns.Route = function()
	return {
		chosen = true,
		journey = "test",
		journeys = {},
		steps = { { kind = "objective", key = "test", title = "Nowhere" } },
	}
end
local unplaced, unplacedReason = API.CurrentStop()
equal(unplaced, nil, "a stop with no known place answers nothing")
equal(unplacedReason, "none", "and says there is nothing to answer")
h.ns.Route, h.ns.RouteSettled = realRoute, realSettled

-- Wanderer mode turns travel off: Status says so, rather than reading as an ordinary change.
h.ns.Choose("zone:1413")
h.flush()
h.ns.SetSetting("wanderer", true)
h.flush()
local noTravel, noTravelReason = API.Status()
equal(noTravel, nil, "wanderer: no guidance status")
equal(noTravelReason, "disabled", "wanderer: the player turned travel off")
h.ns.SetSetting("wanderer", false)
h.flush()

-- Subscribe is ForeverCore.APIKit's hub: the frame after a burst, one call per burst, the same change names.
local kit = h.G.ForeverCore.APIKit
equal(type(kit), "table", "the shared API kit is loaded")
equal(type(kit.Hub), "function", "with the hub")
local ok, message = pcall(API.Subscribe, "not a function")
equal(ok, false, "a non-function callback is an error")
equal(message, "AdventureGuideForever.API.Subscribe: callback must be a function", "the kit's own message")
local calls, seen = 0, {}
local unsubscribe = API.Subscribe(function(changes)
	calls = calls + 1
	seen[#seen + 1] = changes
end)
h.flush()
equal(calls, 0, "a new subscriber hears only what changes after it joins")
local otherJourney
for _, candidate in ipairs(h.ns.Route().journeys) do
	if candidate.key ~= h.ns.Route().journey then
		otherJourney = otherJourney or candidate.key
	end
end
h.ns.Choose(assert(otherJourney, "another journey"))
equal(calls, 0, "the change waits for a later frame, never the same call")
h.flush()
equal(calls, 1, "one call once the burst settles")
equal(seen[1].journey, true, "the journey is named")
equal(seen[1].stop, true, "and so is the stop")
local base = calls
h.ns.Choose("zone:1413")
h.ns.Invalidate()
h.ns.Invalidate()
h.flush()
equal(calls, base + 1, "one call however many rebuilds share the burst")
-- The kit's queue rides the harness's C_Timer: the callback waits for the timer, never the call that queued it.
local beforePause = calls
equal(API.Pause(), true, "a chosen journey pauses")
equal(calls, beforePause, "the pause's change waits for a later frame")
h.tick()
equal(calls, beforePause + 1, "and the harness's timer delivers it")
unsubscribe()
unsubscribe()
local silent = calls
h.ns.Choose(nil)
h.flush()
equal(calls, silent, "an unsubscribed callback hears nothing")

-- A lone pickup step, not a town, carries its quests: the pickup count read 0 before minor 5.
local lone = {
	kind = "pickup",
	key = "pickup:9001",
	title = "Pick up: a test",
	map = step.map,
	x = step.x,
	y = step.y,
	quests = { 9001 },
}
local objective = {
	kind = "objective",
	key = "objective:9002",
	title = "Work: a test",
	map = step.map,
	x = step.x,
	y = step.y,
	quests = { 9003, 9002 },
}
local area = {
	kind = "area",
	key = "area:test",
	title = "An area",
	map = step.map,
	x = step.x,
	y = step.y,
	verb = "objective",
	quests = { 9004 },
	objectives = { { id = 9005 }, { id = 9004 }, { id = 9005 } },
}
local savedRoute, savedSettled = h.ns.Route, h.ns.RouteSettled
h.ns.RouteSettled = function()
	return true
end
h.ns.Route = function()
	return { chosen = true, journey = "test", journeys = {}, steps = { lone, objective, area } }
end
local loneStop = assert(API.CurrentStop(), "a lone pickup step answers")
equal(loneStop.kind, "pickup", "a lone pickup step: kind")
equal(loneStop.isTown, false, "a lone pickup step: not a town")
equal(loneStop.pickups, 1, "a lone pickup step counts its pickup")
same(loneStop.pickupQuests, { 9001 }, "a lone pickup step names its pickup")
same(loneStop.turninQuests, {}, "a lone pickup step hands in nothing")
same(loneStop.objectiveQuests, {}, "a lone pickup step works on nothing")
local ahead = assert(API.NextStops(2), "the route's other steps answer")
equal(ahead[1].kind, "objective", "an objective step: kind")
same(ahead[1].objectiveQuests, { 9002, 9003 }, "an objective step names its quests, ascending")
same(ahead[2].objectiveQuests, { 9004, 9005 }, "an area step names its distinct objectives, ascending")
same(ahead[2].pickupQuests, {}, "an area step picks nothing up")
same(ahead[2].turninQuests, {}, "an area step hands nothing in")
h.ns.Route, h.ns.RouteSettled = savedRoute, savedSettled

equal(#h.errors, 0, table.concat(h.errors, "\n"))
print(("api_spec: %d checks on stops, status and navigation"):format(checks))
