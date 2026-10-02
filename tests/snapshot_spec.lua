-- Run from the repository root: luajit tests/snapshot_spec.lua
-- ns.Snapshot() is the read of the client the cached route was planned from: the views that draw the route share it
-- and walk no quest log of their own, a change to the log brings a new one with the next build, and it is a fresh
-- read while no build stands behind the route.
local harness = dofile("tests/harness.lua")

local function Load(options)
	options.charDB = { journey = "zone:1413" }
	options.completed = { 844 }
	options.log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	local h = harness.load(options)
	h.flush()
	local quests = h.G.C_QuestLog
	local walks, count = 0, quests.GetNumQuestLogEntries
	quests.GetNumQuestLogEntries = function()
		walks = walks + 1
		return count()
	end
	return h, function()
		local seen = walks
		walks = 0
		return seen
	end
end

-- One snapshot per build, held beside the route.
do
	local h, Walks = Load({})
	local ns = h.ns
	local world = ns.Snapshot()
	assert(Walks() == 0, "the snapshot of a built route is no new walk of the quest log")
	assert(ns.Snapshot() == world, "and is the same one until the route is rebuilt")
	assert(world.log[845].title == "The Zhevra" and world.log[843] ~= nil, "it holds the log the build read")
	assert(world.completed[844] == true, "the completed quests")
	assert(world.player.level == h.G.UnitLevel("player"), "and the player")

	-- The views that draw the route read it: the tracker's quest lines walk no log, however many rows there are.
	local step = { key = "k", kind = "area", title = "Complete objectives", quests = { 845, 843 }, reason = "r" }
	ns.Guidance.CurrentStep = function()
		return step
	end
	h.tracker:LayoutContents()
	local block = h.tracker.liveBlocks[step.key]
	assert(block.lines[1]:find("[13] The Zhevra", 1, true), "the tracker names the quest from the snapshot")
	assert(block.lines[2]:find("[23] Gann's Reclamation", 1, true), "and the next")
	assert(Walks() == 0, "without walking the quest log per line")
	ns.Order.CanMove(1, 2)
	assert(Walks() == 0, "nor does a drag's check")

	-- A change to the log invalidates the route, and the next build brings the next snapshot, read once.
	table.remove(h.log, 2)
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local after = ns.Snapshot()
	assert(after ~= world, "a rebuild replaces the snapshot")
	assert(after.log[843] == nil and after.log[845] ~= nil, "with the log as it is now")
	assert(Walks() == 1, "one walk of the quest log for the rebuild and all its listeners, got more")
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- No build behind the route: every call is a fresh read, as the views took before.
do
	local h, Walks = Load({ completedPending = true })
	local ns = h.ns
	assert(#ns.Route().steps == 0, "no route before the completed quests load")
	local world = ns.Snapshot()
	assert(world.log[845] ~= nil, "the log is read live")
	assert(ns.Snapshot() ~= world, "afresh each time")
	assert(Walks() == 2, "one walk per call")
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("snapshot_spec: one snapshot per build, shared by the route's views; live while there is no build")
