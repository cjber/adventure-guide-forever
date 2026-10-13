-- Run from the repository root: luajit tests/completed_sync_spec.lua
-- The completed quests (State.Completed) follow the server, not just QUEST_TURNED_IN: a nil first answer is retried
-- until the client gives one, an empty one is read again, every loading screen reads them whole, and a turn-in brings
-- one more read once its quest log settles. Quests are only ever added, and nothing else re-reads them.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function clean(h, label)
	equal(#h.errors, 0, label .. ": no errors (" .. table.concat(h.errors, "\n") .. ")")
end

-- Counts the reads of the completed quests, and lets a spec say what the server answers.
local function Load(options)
	options.charDB = options.charDB or { journey = "zone:1413" }
	local reads = 0
	local answer
	local setup = options.setup
	options.setup = function(h)
		local read = h.G.C_QuestLog.GetAllCompletedQuestIDs
		h.G.C_QuestLog.GetAllCompletedQuestIDs = function()
			reads = reads + 1
			if answer then
				return answer(reads)
			end
			return read()
		end
		if setup then
			setup(h)
		end
	end
	local h = harness.load(options)
	h.flush()
	return h, function()
		local seen = reads
		reads = 0
		return seen
	end, function(fn)
		answer = fn
	end
end

-- A nil first answer is retried each second until the client gives one: the guide leaves "Loading" on its own.
do
	local list = { 844 }
	local h, Reads, Answer = Load({
		setup = function(h)
			h.completedPending = true
		end,
		completed = list,
	})
	equal(h.ns.State.Ready(), false, "nil answer: not ready")
	equal(Reads() > 1, true, "nil answer: retried")
	-- A loading screen while the client still has no answer starts the retries again, and one lands.
	local calls = 0
	Answer(function()
		calls = calls + 1
		return calls >= 3 and list or nil
	end)
	h.fire("PLAYER_ENTERING_WORLD", false, false)
	equal(h.ns.State.Ready(), false, "nil answer: still none at the loading screen")
	h.flush()
	equal(h.ns.State.Ready(), true, "nil answer: a retry readies the guide without a /reload")
	equal(h.ns.State.Completed()[844], true, "nil answer: with the client's list")
	equal(#h.ns.Route().steps > 0, true, "nil answer: and plans a route")
	Reads()
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Reads(), 0, "nil answer: once ready, the retries stop")
	clean(h, "nil answer")
end

-- A quest-log event while there is no answer yet asks again at once.
do
	local h, Reads = Load({
		setup = function(h)
			h.completedPending = true
		end,
		completed = { 844 },
	})
	Reads()
	h.completedPending = false
	h.fire("QUEST_LOG_UPDATE")
	equal(h.ns.State.Ready(), true, "log update: readies the guide")
	equal(Reads(), 1, "log update: one read")
	clean(h, "log update")
end

-- An empty first answer readies the guide (a new character has none) but is read again, in case the list had not
-- loaded yet.
do
	local h, Reads = Load({
		setup = function(h)
			local read = h.G.C_QuestLog.GetAllCompletedQuestIDs
			local calls = 0
			h.G.C_QuestLog.GetAllCompletedQuestIDs = function()
				calls = calls + 1
				return calls <= 2 and {} or read()
			end
		end,
		completed = { 844 },
	})
	equal(h.ns.State.Ready(), true, "empty answer: ready")
	equal(h.ns.State.Completed()[844], true, "empty answer: the list read again once it loaded")
	equal(h.ns.Snapshot().completed[844], true, "empty answer: and the route rebuilt with it")
	Reads()
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Reads(), 0, "empty answer: no more reads once the list has quests")
	clean(h, "empty answer")
end

-- The server marks quests done with no QUEST_TURNED_IN (another branch of a chain closing): a turn-in brings one read
-- once its log settles, and a later loading screen reads them whole. Plain quest-log ticks read nothing.
do
	local list = { 844 }
	local h, Reads = Load({ completed = list })
	Reads()
	for _ = 1, 10 do
		h.fire("QUEST_LOG_UPDATE")
	end
	h.flush()
	equal(Reads(), 0, "resync: objective ticks read nothing")

	list[#list + 1] = 869
	h.fire("QUEST_TURNED_IN", 845)
	equal(h.ns.State.Completed()[845], true, "resync: the turn-in counts at once")
	equal(Reads(), 0, "resync: not read yet")
	for _ = 1, 5 do
		h.fire("QUEST_LOG_UPDATE")
	end
	equal(Reads(), 0, "resync: deferred past the turn-in's burst")
	h.flush()
	equal(Reads(), 1, "resync: one read for the turn-in")
	equal(h.ns.State.Completed()[869], true, "resync: the quest the server closed is done")
	equal(h.ns.State.Completed()[845], true, "resync: the turn-in the list lacks is kept")
	equal(h.ns.Snapshot().completed[869], true, "resync: the route rebuilt with it")

	list[#list + 1] = 870
	h.fire("PLAYER_ENTERING_WORLD", false, false)
	h.flush()
	equal(h.ns.State.Completed()[870], true, "resync: a loading screen reads them whole")
	equal(Reads(), 1, "resync: once")

	clean(h, "resync")
end

print(("completed_sync_spec: %d checks passed"):format(checks))
