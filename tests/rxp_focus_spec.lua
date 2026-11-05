-- Run from the repository root: luajit tests/rxp_focus_spec.lua
-- A RestedXP step's objective area (#352): standing in it while AGF steers the guide is "you're here", as for a
-- planned area, so the quest is selected (the game draws its own quest area, gold on the minimap) and Shortest Path is
-- handed the area's shapes and quest, so it shows the client's quest area too.
local harness = dofile("tests/harness.lua")

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- Deathknell: Scavenging Deathknell (3902) under way at 0/6, the player standing on its objective node.
local h = harness.load({
	spf = "v1",
	planned = true,
	db = { autoStart = false, followQuest = true, restedxpChoiceMade = true, restedxpGuide = true },
	completed = { 376 },
	player = { level = 4, raceID = 5, classID = 1, map = 1420, x = 0.330, y = 0.635 },
	log = { { id = 3902, title = "Scavenging Deathknell", level = 3, complete = false } },
})
h.flush()

local current = {
	index = 1,
	active = true,
	title = "Scavenging Deathknell",
	elements = {
		{
			text = "Collect Scavenged Goods",
			tag = "complete",
			questId = 3902,
			arrow = true,
			zone = 1420,
			x = 33,
			y = 63.5,
		},
	},
}
current.elements[1].step = current
local guide = { name = "Example: Tirisfal", group = "Example guides", steps = { current } }
local frame = h.G.CreateFrame("Frame", nil, h.G.UIParent)
frame.activeSteps = { current }
local arrow = h.G.CreateFrame("Frame", nil, h.G.UIParent)
arrow.element = current.elements[1]
h.G.RXP = {
	RXPFrame = frame,
	currentGuide = guide,
	arrowFrame = arrow,
	activeWaypoints = { true },
	GetGuideProgress = function()
		return 1
	end,
	SetStep = function() end,
	UpdateMap = function() end,
	settings = { profile = { showEnabled = true } },
}
h.fire("ADDON_LOADED", "RXPGuides")
h.flush()
local key = "guide:14:Example guides:17:Example: Tirisfal"
assert(h.ns.StartJourney(key), "the guide's card starts")
h.flush()
h.ns.Invalidate()
h.flush()

local route = h.ns.Route()
local step = route.steps[1]
equal(route.journey, key, "the guide is the route")
equal(step.rxpIndex, 1, "its step leads")
equal(#step.shapes > 0, true, "the step has its quest's objective area")
equal(step.here, true, "standing in the step's objective area is you're here")
equal(h.superTrackedQuest, 3902, "the step's quest is selected, so the game draws its quest area")
equal(h.ns.Prefs().focus, 3902, "kept as AGF's selection")

local handed = h.spfRoute and h.spfRoute.stops[1]
equal(handed ~= nil, true, "Shortest Path holds the guide's stop")
equal(handed.questID, 3902, "Shortest Path is told the area's quest")
equal(handed.shapes ~= nil and #handed.shapes > 0, true, "and its shapes")

-- Walking out of the area clears AGF's selection again.
h.MovePlayer(1420, 0.60, 0.20)
h.ns.Invalidate()
h.flush()
equal(h.ns.Route().steps[1].here, nil, "out of the area: not here")
equal(h.ns.Prefs().focus, nil, "out of the area: AGF's selection goes")

equal(#h.errors, 0, table.concat(h.errors, "\n"))
print(("rxp_focus_spec: %d checks passed"):format(checks))
