-- Run from the repository root: luajit tests/objective_area_spec.lua
-- Objective areas (docs/design.md §4.2): standing inside the area step 1 leads to is "you're here", even when the
-- same merged visit also holds a quest the route has yet to pick up elsewhere; the in-progress quest is selected, no
-- travel line or numbered pin points back into the area, and the route does not advance to the next objective area
-- (Night Web's Hollow) while the current objective is unfinished. The point the step marks is an objective node, not
-- a spot on the shape's ring.
local harness = dofile("tests/harness.lua")

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- Deathknell: Scavenging Deathknell (3902) is under way at 0/6; Marla's Last Wish (6395) is offered at the same town
-- and its objective node sits beside 3902's, so the planner merges them into one area visit. Night Web's Hollow (380)
-- is the next objective area the route holds.
local h = harness.load({
	spf = "v1",
	planned = true,
	db = { autoStart = false, showMapPins = true, showQuestGivers = true },
	charDB = { journey = "zone:1420" },
	completed = { 376 },
	player = { level = 4, raceID = 5, classID = 1, map = 1420, x = 0.3161, y = 0.656 },
	log = { { id = 3902, title = "Scavenging Deathknell", level = 3, complete = false } },
})
h.flush()

h.MovePlayer(1420, 0.330, 0.635) -- 3902's objective node
h.ns.Invalidate()
h.flush()

local route = h.ns.Route()
local step = route.steps[1]
equal(step.key, "area:3902:4", "here: the area the player stands in leads")
equal(step.here, true, "here: recognised as the area they are in")
equal(table.concat(step.quests, " "), "3902", "here: the leading visit keeps only the work in progress")
equal(h.superTrackedQuest, 3902, "focus: the in-progress quest is selected")
equal(h.ns.Prefs().focus, 3902, "focus: kept as AGF's")
equal(h.ns.Integrations.Travel(step), nil, "here: no travel line inside the area")

-- The route's numbered pin is not drawn for the area the player stands in, but later stops keep theirs.
h.G.OpenQuestLog()
h.map:SetMapID(1420)
h.flush()
h.providers[1]:RefreshAllData()
local numbered, laterPinned = false, false
for _, pin in ipairs(h.pins.AdventureGuideForeverPinTemplate or {}) do
	numbered = numbered or pin.step == step
	laterPinned = laterPinned or pin.step == route.steps[2]
end
equal(numbered, false, "here: no numbered pin where the player is")
equal(laterPinned, true, "here: the stops after it keep theirs")

-- Only the area they stand in is "here": the route did not advance to the next objective area while 3902 is 0/6.
for index = 2, #route.steps do
	equal(route.steps[index].here, nil, ("here: step %d is not 'here'"):format(index))
end
local nightWeb = false
for _, later in ipairs(route.steps) do
	nightWeb = nightWeb or (later.key == "area:380:0" or later.key == "area:380:1")
end
equal(nightWeb, true, "here: the next objective area stays on the route")

-- Standing in the next area (Night Web's Hollow) does not advance the route while 3902 is unfinished.
h.MovePlayer(1420, 0.287, 0.575)
h.ns.Invalidate()
h.flush()
equal(h.ns.Route().steps[1].key, "area:3902:4", "state: a later area does not advance an unfinished step")
h.MovePlayer(1420, 0.330, 0.635)
h.ns.Invalidate()
h.flush()

-- The pickup the merged visit also held is still made at its town, not lost to the leading visit.
local picked
for _, later in ipairs(route.steps) do
	for _, id in ipairs(later.pickups or {}) do
		picked = picked or (id == 6395 and later.key or nil)
	end
end
equal(picked, "town:221", "here: the planned pickup keeps its town visit")

-- The step's point is an objective node inside one of its shapes, not a spot on the ring's border.
local onNode = false
for _, shape in ipairs(step.shapes or {}) do
	local yards = h.ns.Model.Yards(h.ns.Data, step, shape)
	onNode = onNode or (yards ~= nil and yards <= shape.r)
end
equal(onNode, true, "area point: on an objective node, inside its shape")

-- Shortest Path advancing its own stop index does not move the tracker off the area the player is in.
h.ns.StartRoute()
h.flush()
h.spfAdvance()
equal(h.ns.Integrations.CurrentStep().key, "area:3902:4", "state: the tracker holds the unfinished step")

-- Walking out with the objective unfinished still holds the step: the route does not end it early.
h.MovePlayer(1420, 0.36, 0.70)
h.ns.Invalidate()
h.flush()
equal(h.ns.Route().steps[1].key, "area:3902:4", "state: an unfinished objective keeps its step")
equal(h.ns.Route().steps[1].here, nil, "state: and is no longer 'here' outside it")
assert(#h.errors == 0, "errors: " .. table.concat(h.errors, "\n"))
print(("objective_area_spec: %d checks passed"):format(checks))
