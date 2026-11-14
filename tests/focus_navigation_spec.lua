-- Run from the repository root: luajit tests/focus_navigation_spec.lua
-- Focusing the route's quest must not take native navigation from whoever holds it (#531): selecting the quest for
-- its objective area leaves a super-tracked waypoint super-tracked afterwards, whether Adventure Guide, Shortest Path
-- or the player placed it, while no waypoint means nothing is turned on.
local ns = {}
assert(loadfile("Planning/Focus.lua"))("AdventureGuideForever", ns)

-- The client's super-tracking: selecting a quest makes it the tracked destination; tracking the user waypoint
-- again raises the waypoint back above it.
local tracked, quest, kind, selections = false, 0, nil, 0
_G.C_SuperTrack = {
	IsSuperTrackingUserWaypoint = function()
		return tracked
	end,
	GetSuperTrackedQuestID = function()
		return quest
	end,
	GetHighestPrioritySuperTrackingType = function()
		return kind
	end,
	SetSuperTrackedQuestID = function(id)
		selections = selections + 1
		quest = id
		if id ~= 0 then
			tracked, kind = false, "quest"
		end
	end,
	SetSuperTrackedUserWaypoint = function(on)
		tracked = on
		if on then
			kind = "waypoint"
		end
	end,
}

local prefs = {}
local route
local waypointAt = false
local informationOnly = false
ns.Prefs = function()
	return prefs
end
ns.Setting = function(key)
	if key == "informationOnly" then
		return informationOnly
	end
	return true
end
ns.Route = function()
	return route
end
ns.Snapshot = function()
	return { log = { [226] = { complete = false }, [245] = { complete = false }, [300] = { complete = false } } }
end
ns.Integrations = {
	WaypointAt = function()
		return waypointAt
	end,
}

local failures, checks = {}, 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		failures[#failures + 1] = ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual))
	end
end

-- Enter a fresh area whose first open quest is `id`, with `wasTracked` saying whether a user waypoint is
-- super-tracked before the look.
local function Enter(key, id, wasTracked)
	prefs.focus = nil
	tracked, quest, kind = wasTracked, 0, wasTracked and "waypoint" or nil
	selections = 0
	route = { chosen = true, steps = { { key = key, here = true, objectives = { { id = id } } } } }
	ns.Focus.Sync()
end

-- Shortest Path's waypoint is the one super-tracked; Focus.Sync selects the step's quest and gives navigation back.
waypointAt = false
Enter("area:226:0", 226, true)
equal(quest, 226, "the step's quest is selected")
equal(tracked, true, "another addon's super-tracked waypoint stays super-tracked")
equal(kind, "waypoint", "and stays the destination that leads")

-- The player's own waypoint is treated the same, whoever placed it.
Enter("area:245:0", 245, true)
equal(tracked, true, "the player's super-tracked waypoint stays super-tracked")
equal(kind, "waypoint", "and stays the destination that leads")

-- Adventure Guide's own waypoint still comes back, as before.
waypointAt = true
Enter("area:300:0", 300, true)
equal(tracked, true, "AGF's own super-tracked waypoint still comes back")
equal(kind, "waypoint", "and stays the destination that leads")

-- Walking out clears AGF's quest without dropping a waypoint it found super-tracked, whoever placed it.
waypointAt = false
route = { chosen = true, steps = {} }
ns.Focus.Sync()
equal(quest, 0, "walking out clears AGF's quest selection")
equal(tracked, true, "the super-tracked waypoint survives the clear")
equal(kind, "waypoint", "and still leads")

-- With no waypoint super-tracked, selecting the quest leaves navigation with the quest alone.
Enter("area:301:0", 300, false)
equal(tracked, false, "no waypoint is super-tracked when there was none")
equal(kind, "quest", "the selected quest is the destination")

-- Information mode follows nothing (#715): walking into the route's first area selects no quest, and no call reaches
-- the client's selection.
informationOnly = true
Enter("area:400:0", 400, false)
equal(quest, 0, "information mode selects no quest")
equal(selections, 0, "and never changes the client's selection")
equal(prefs.focus, nil, "nothing is recorded as AGF's")

-- AGF's own selection from before the mode is cleared through the same ownership check.
prefs.focus = 226
route = { chosen = true, steps = { { key = "area:226:0", here = true, objectives = { { id = 226 } } } } }
tracked, quest, kind = false, 226, nil
selections = 0
ns.Focus.Sync()
equal(selections, 1, "AGF's own selection is cleared on entering the mode")
equal(quest, 0, "back to none")
equal(prefs.focus, nil, "and forgotten")

-- A selection that is not AGF's is preserved, with AGF's stale record dropped and no client call made.
prefs.focus = 226
route = { chosen = true, steps = { { key = "area:245:0", here = true, objectives = { { id = 245 } } } } }
tracked, quest, kind = false, 99, nil
selections = 0
ns.Focus.Sync()
equal(selections, 0, "the player's selection is left alone")
equal(quest, 99, "still the player's")
equal(prefs.focus, nil, "AGF forgets its stale selection, not theirs")

-- A super-tracked waypoint also survives entering the mode with a foreign selection.
prefs.focus = nil
route = { chosen = true, steps = { { key = "area:300:0", here = true, objectives = { { id = 300 } } } } }
tracked, quest, kind, waypointAt = true, 99, "waypoint", true
selections = 0
ns.Focus.Sync()
equal(selections, 0, "no selection is made with a waypoint super-tracked")
equal(quest, 99, "the player's selection stays")
equal(tracked, true, "the waypoint stays super-tracked")
equal(kind, "waypoint", "and still leads")
informationOnly = false

for _, failure in ipairs(failures) do
	print("  " .. failure)
end
print(("focus_navigation_spec: %d checks, %d failed"):format(checks, #failures))
if #failures > 0 then
	os.exit(1)
end
