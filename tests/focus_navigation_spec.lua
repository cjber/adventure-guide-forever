-- Run from the repository root: luajit tests/focus_navigation_spec.lua
-- Focusing the route's quest must not take native navigation from whoever holds it (#531): selecting the quest for
-- its objective area leaves a super-tracked waypoint super-tracked afterwards, whether Adventure Guide, Shortest Path
-- or the player placed it, while no waypoint means nothing is turned on.
local ns = {}
assert(loadfile("Planning/Focus.lua"))("AdventureGuideForever", ns)

-- The client's super-tracking: selecting a quest makes it the tracked destination; tracking the user waypoint
-- again raises the waypoint back above it.
local tracked, quest, kind = false, 0, nil
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
ns.Prefs = function()
	return prefs
end
ns.Setting = function()
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

for _, failure in ipairs(failures) do
	print("  " .. failure)
end
print(("focus_navigation_spec: %d checks, %d failed"):format(checks, #failures))
if #failures > 0 then
	os.exit(1)
end
