-- Run from the repository root: luajit tests/rebuild_slice_spec.lua
-- Core.StepRebuild uses budgeted planner yield points across frames so a heavy
-- rebuild never spends its whole cost in one frame (WFA-13). The route is committed atomically: a partial build is
-- never visible, and an invalidation that lands while a build is under way earns exactly one follow-up build.
local harness = dofile("tests/harness.lua")

-- A level-60 character with many zones of work: enough card routes that the build is sliced.
local function Load()
	local h = harness.load({
		player = { level = 60, faction = "Horde", raceID = 2, classID = 1, map = 1423, x = 0.81, y = 0.58 },
		charDB = { journey = "zone:1413" },
	})
	h.flush()
	h.clockStep = 1
	return h
end

-- The build is sliced: one frame starts it without finishing it, and the route is unchanged until the commit frame.
do
	local h = Load()
	local previous = h.ns.Route()
	h.ns.Invalidate()
	assert(h.ns.Rebuilding(), "the build is in flight before its first frame")
	assert(h.tick() >= 1, "the first slice ran")
	assert(h.ns.Rebuilding(), "the build is still sliced after one frame")
	assert(h.ns.Route() == previous, "a partial build is not visible: the route is unchanged mid-flight")
	h.flush()
	assert(not h.ns.Rebuilding(), "the build settled")
	assert(not h.ns.Settling(), "nothing else is due")
	assert(h.ns.Route() ~= previous, "the commit replaced the route")
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- An invalidation mid-build is coalesced into exactly one follow-up build, not one per frame.
do
	local h = Load()
	local plan, builds = h.ns.Model.Plan, 0
	h.ns.Model.Plan = function(...)
		builds = builds + 1
		return plan(...) -- multi-value: the wrapper is transparent
	end
	h.ns.Invalidate()
	assert(h.tick() >= 1, "the first slice ran")
	assert(h.ns.Rebuilding(), "the build is under way")
	h.ns.Invalidate()
	h.flush()
	assert(builds == 2, "a mid-build invalidation earns exactly one more build, got " .. builds)
	h.ns.Model.Plan = plan
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A listener that invalidates the route from its own notification still settles: the follow-up build is queued, not
-- run reentrantly inside the notify, and it is queued exactly once (a second chain would resume the same coroutine,
-- giving a spurious extra notification and double-slice frames).
do
	local h = Load()
	local plan, builds, notifies = h.ns.Model.Plan, 0, 0
	h.ns.Model.Plan = function(...)
		builds = builds + 1
		return plan(...) -- multi-value: the wrapper is transparent
	end
	local fired = false
	h.ns.OnRouteChange(function()
		notifies = notifies + 1
		if not fired then
			fired = true
			h.ns.Invalidate()
		end
	end)
	h.ns.Invalidate()
	h.flush()
	h.ns.Model.Plan = plan
	assert(fired, "the listener ran")
	assert(not h.ns.Settling(), "a reentrant invalidation still settles")
	assert(builds == 2, "the reentrant invalidation earns exactly one more build, got " .. builds)
	assert(notifies == 2, "exactly one notification per committed build, got " .. notifies)
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("rebuild_slice_spec: the build is sliced, committed atomically, and reentrant invalidations settle")
