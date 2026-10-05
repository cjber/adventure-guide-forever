-- Run from the repository root: luajit -joff tests/plan_bench.lua
-- Times the real rebuild through tests/harness.lua, frame by frame, with -joff standing in for the client's plain
-- Lua 5.1. The full build is sliced across frames (Core.StepRebuild, Model.Journeys' YieldCards): a sample drives the
-- rebuild to rest and every one of its frames is timed and must stay under the budget, not just the last. Shortest
-- Path is a counted cost model, not a sleep: its cache semantics (API.lua:9,166-181: origin rounded to 1e-4 plus the
-- exact destination, 256 slots, 5 s TTL) on a fake clock, charging 2.45 ms per miss (a cold estimate, API.lua:132) and
-- 0.003 ms per hit. The cache is reset before every sample, so each one is the cold worst case.
-- CI asserts the call counts; AGF_BENCH_STRICT=1 also asserts the 3 ms frame budget (WFA-13), which shared runners
-- would flake.
local harness = dofile("tests/harness.lua")
local MISS_MS, HIT_MS, BUDGET_MS, SLOTS, TTL = 2.45, 0.003, 3, 256, 5
-- QuestieDB's catalogue is built once a login in 5 ms slices (QuestieSource.lua's SLICE_MS): nothing can be drawn
-- until it lands, so it trades the 3 ms budget for a tracker that fills in seconds.
local BUILD_BUDGET_MS = 7
local SAMPLES, strict = 20, os.getenv("AGF_BENCH_STRICT") == "1"

local data = harness.data()

-- Where each level stands, per side (uiMapID, x, y), and the race and class IDs it plays.
local SIDES = {
	{
		faction = "Alliance",
		side = 1,
		raceID = 1,
		classID = 1,
		at = { [1] = { 1429, 0.48, 0.42 }, [10] = { 1436, 0.56, 0.47 }, [20] = { 1433, 0.27, 0.45 } },
	},
	{
		faction = "Horde",
		side = 2,
		raceID = 2,
		classID = 1,
		at = { [1] = { 1411, 0.52, 0.68 }, [10] = { 1413, 0.52, 0.30 }, [20] = { 1442, 0.47, 0.61 } },
	},
}
-- From 30 both sides share the contested zones.
local SHARED = { [30] = { 1434, 0.27, 0.77 }, [40] = { 1446, 0.51, 0.28 }, [50] = { 1449, 0.44, 0.08 } }
SHARED[60] = { 1423, 0.81, 0.58 }

-- Every quest of the side below level - 5 is done: deterministic, and a realistic amount of history.
local function Completed(side, level)
	local ids = {}
	for id, quest in pairs(data.quests) do
		if (quest.side == 3 or quest.side == side) and quest.level > 0 and quest.level < level - 5 then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	return ids
end

-- A full log (design §5.2): 40 quests of the side around `level`, not yet done, every other one finished (the live
-- client gives its turn-in waypoint) and the rest under way, with the client's objectives in the data's need slots
-- and, on every third, the client's point for it. The worst case for the log's steps and their area merging.
local LOG_SIZE = 40
local function FullLog(side, level)
	local ids = {}
	for id, quest in pairs(data.quests) do
		if
			(quest.side == 3 or quest.side == side)
			and not quest.dungeon
			and quest.level >= level - 2
			and quest.level <= level + 2
			and quest.min <= level
		then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local log = {}
	for index = 1, math.min(LOG_SIZE, #ids) do
		local quest = data.quests[ids[index]]
		local entry = { id = ids[index], title = quest.title, level = quest.level, complete = index % 2 == 0 }
		if entry.complete and quest.finish then
			entry.map, entry.x, entry.y = quest.finish.map, quest.finish.x, quest.finish.y
		elseif not entry.complete then
			local slots, objectives = {}, {}
			for slot in pairs(quest.need or {}) do
				slots[#slots + 1] = slot
			end
			table.sort(slots)
			for _, slot in ipairs(slots) do
				local kind = slot < 4 and "monster" or slot < 16 and "item" or "event"
				objectives[#objectives + 1] = { type = kind, done = false, have = 0, need = quest.need[slot] }
			end
			entry.objectives = objectives
			local area = quest.obj and quest.obj[1]
			if area and index % 3 == 0 then
				entry.poi = { map = area[5] or quest.zone, x = area[2] / 1000, y = area[3] / 1000 }
			end
		end
		log[#log + 1] = entry
	end
	return log
end

-- Shortest Path's estimate cache, modelled: returns the modelled milliseconds of one call.
local function CostModel()
	local model = { now = 0, ms = 0, misses = 0, calls = 0 }
	local entries, order = {}, {}
	function model.reset()
		entries, order, model.ms, model.misses, model.calls = {}, {}, 0, 0, 0
	end
	function model.charge(fromMap, fromX, fromY, toMap, toX, toY)
		local key = ("%d:%d:%d>%d:%s:%s"):format(
			fromMap,
			math.floor(fromX / 1e-4 + 0.5),
			math.floor(fromY / 1e-4 + 0.5),
			toMap,
			tostring(toX),
			tostring(toY)
		)
		model.calls = model.calls + 1
		local entry = entries[key]
		if entry and model.now - entry.at < TTL then
			model.ms = model.ms + HIT_MS
			return
		end
		model.ms, model.misses = model.ms + MISS_MS, model.misses + 1
		if not entry then
			order[#order + 1] = key
			if #order > SLOTS then
				entries[table.remove(order, 1)] = nil
			end
		end
		entries[key] = { at = model.now }
	end
	return model
end

local function Median(values)
	local sorted = { unpack(values) }
	table.sort(sorted)
	return sorted[math.ceil(#sorted / 2)]
end

local function Max(values)
	return math.max(unpack(values)) -- multi-value: every sample is an argument
end

local failures, lines = {}, {}
local function check(ok, message)
	if not ok then
		failures[#failures + 1] = message
	end
end

local worstRebuild, worstTravel, worstSlice, worstSession, profiles = 0, 0, 0, 0, 0

-- QuestieDB's build (QuestieSource.lua) on the real clock: each frame's slice, timed as the timer that runs it.
local function Slices(h)
	-- The synthetic provider mirrors this fixture; its policy uses the same character gates.
	local policy = {}
	h.G.Questie = { API = {
		isReady = true,
		RegisterOnReady = function(fn)
			fn()
		end,
	} }
	h.G.QuestieLoader = {
		ImportModule = function()
			return {
				IsDoable = function(id)
					if policy[id] == nil then
						policy[id] =
							h.ns.Model.Eligible(data, h.ns.State.Player(), h.ns.State.Completed(), h.ns.State.Log(), id)
					end
					return policy[id]
				end,
			}
		end,
	}
	h.G.debugprofilestop = function()
		return os.clock() * 1000
	end
	local after = h.G.C_Timer.After
	h.G.C_Timer.After = function(delay, fn)
		local source = debug.getinfo(fn, "S").source
		after(delay, function()
			local started = os.clock()
			fn()
			if source:find("QuestieSource") then
				worstSlice = math.max(worstSlice, (os.clock() - started) * 1000)
			end
		end)
	end
end

local function Profile(profile, level, questiedb, full)
	local at = profile.at[level] or SHARED[level]
	local label = ("%s %d%s%s"):format(
		profile.faction,
		level,
		questiedb and " QuestieDB" or "",
		full and " log 40" or ""
	)
	profiles = profiles + 1
	local h = harness.load({
		spf = "v1",
		completed = Completed(profile.side, level),
		player = {
			level = level,
			faction = profile.faction,
			raceID = profile.raceID,
			classID = profile.classID,
			map = at[1],
			x = at[2],
			y = at[3],
		},
		questiedb = questiedb,
		setup = questiedb and Slices,
		log = full and FullLog(profile.side, level) or nil,
	})
	check(not questiedb or h.ns.QuestieStatus.state == "questie", label .. ": QuestieDB's quests not in use")
	local api, model = h.G.ShortestPathForever.API, CostModel()
	for _, name in ipairs({ "Estimate", "EstimateDetail" }) do
		local original = api[name]
		if original then
			api[name] = function(...)
				model.charge(...)
				return original(...) -- multi-value: the wrapper is transparent
			end
		end
	end
	-- The Adventure Guide window, built and closed: it redraws only while shown, so no rebuild frame reaches its tabs.
	h.ns.OpenWindow()
	h.flush()
	h.G.AdventureGuideForeverWindow:Hide()
	local windowRefreshes = 0
	for _, tab in ipairs(h.ns.Window.Tabs()) do
		local refresh = tab.Refresh
		tab.Refresh = function(content)
			windowRefreshes = windowRefreshes + 1
			refresh(content)
		end
	end
	h.ns.OpenPanel()
	h.flush()
	-- Earlier profiles are discarded clients, including their full databases. Reclaim those before timing this
	-- character; ordinary incremental GC stays enabled throughout the measured frames.
	collectgarbage("collect")
	local created = h.counts.CreateFrame
	local rebuild, travel, steps = {}, {}, #h.ns.Route().steps
	for sample = 1, SAMPLES do
		model.reset()
		model.now = sample * 60
		-- A full log's rebuild follows the log's event, so it reads the objectives and the quest points again. The
		-- event's own frame (State coalesces it) only queues the rebuild; the sampled frames below run it. Every other
		-- profile rebuilds from the invalidation directly.
		if full then
			h.fire("QUEST_LOG_UPDATE")
			h.tick()
		else
			h.ns.Invalidate()
		end
		-- The full build is sliced across frames (Core.StepRebuild): drive it to rest, timing every frame. A rebuild
		-- frame asks Shortest Path nothing; each travel frame asks at most once. Its modelled cost is charged to the
		-- frame that made the call.
		local worstFrameRebuild, worstFrameTravel, builtFrames = 0, 0, 0
		while h.ns.Settling() do
			local rebuilding = h.ns.Rebuilding()
			local callsBefore, msBefore = model.calls, model.ms
			local started = os.clock()
			local ran = h.tick()
			local frameMs = (os.clock() - started) * 1000
			if ran == 0 then
				break
			end
			if rebuilding then
				check(
					model.calls == callsBefore,
					label .. ": a rebuild frame asked Shortest Path " .. (model.calls - callsBefore) .. " times"
				)
				worstFrameRebuild = math.max(worstFrameRebuild, frameMs)
				builtFrames = builtFrames + 1
			else
				check(
					model.calls - callsBefore <= 1,
					label .. ": a travel frame asked " .. (model.calls - callsBefore) .. " times"
				)
				worstFrameTravel = math.max(worstFrameTravel, frameMs + model.ms - msBefore)
			end
		end
		check(builtFrames >= 1, label .. ": the build was not sliced")
		rebuild[sample], travel[sample] = worstFrameRebuild, worstFrameTravel
	end
	check(h.counts.CreateFrame == created, label .. ": frames created after the first render")
	check(windowRefreshes == 0, label .. ": the closed window redrew " .. windowRefreshes .. " times")
	check(not full or #h.log == LOG_SIZE, label .. ": a log of " .. #h.log)
	check(#h.errors == 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
	worstRebuild, worstTravel = math.max(worstRebuild, Max(rebuild)), math.max(worstTravel, Max(travel))
	lines[#lines + 1] = ("%-14s %d steps  rebuild %.3f / %.3f ms  travel %.3f / %.3f ms (modelled, median / max)"):format(
		label,
		steps,
		Median(rebuild),
		Max(rebuild),
		Median(travel),
		Max(travel)
	)
end

for _, level in ipairs({ 1, 10, 20, 30, 40, 50, 60 }) do
	for _, profile in ipairs(SIDES) do
		Profile(profile, level)
	end
end
-- The same frames with a full log.
for _, profile in ipairs(SIDES) do
	Profile(profile, 20, nil, true)
end
-- The same frames on QuestieDB's quests, converted from a synthetic mirror of the bundled data (the harness's).
local mirror = harness.questieMirror(data)
for _, level in ipairs({ 10, 40 }) do
	for _, profile in ipairs(SIDES) do
		Profile(profile, level, mirror)
	end
end

-- Cold Legacy reads return pending immediately, including while the guide is hidden. Session legs share
-- the travel scheduler; showing either guide must not cause a second SPF estimate in the same frame.
for _, shown in ipairs({ false, true }) do
	local h = harness.load({
		spf = "ended",
		legacy = { error = "loading" },
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	})
	if shown then
		h.ns.OpenWindow()
	end
	h.flush()
	local api, model = h.G.ShortestPathForever.API, CostModel()
	for _, name in ipairs({ "Estimate", "EstimateDetail" }) do
		local original = api[name]
		api[name] = function(...)
			model.charge(...)
			return original(...) -- multi-value: preserve the provider's refusal reason
		end
	end
	collectgarbage("collect")
	local samples, frames = {}, {}
	for sample = 1, SAMPLES do
		model.reset()
		model.now = sample * 60
		local started = os.clock()
		local completion = h.ns.Providers.Completion()
		check(completion.zones[1].error == "loading", "cold provider must preserve pending")
		samples[sample] = (os.clock() - started) * 1000
		h.ns.Session.Set(sample % 2 == 0 and 30 or 15)
		for _ = 1, 30 do
			local asked, charged = model.calls, model.ms
			local frameStart = os.clock()
			local ran = h.tick()
			frames[#frames + 1] = (os.clock() - frameStart) * 1000 + model.ms - charged
			check(model.calls - asked <= 1, "session/card travel must share one SPF call per frame")
			if ran == 0 then
				break
			end
		end
	end
	worstSession = math.max(worstSession, Max(frames))
	lines[#lines + 1] = ("Session frames, window %s: %.3f / %.3f ms (modelled, median / max)"):format(
		shown and "shown" or "hidden",
		Median(frames),
		Max(frames)
	)
	check(#h.errors == 0, "session benchmark errors: " .. table.concat(h.errors, "\n"))
	lines[#lines + 1] = ("Legacy cold, window %s: %.3f / %.3f ms (median / max)"):format(
		shown and "shown" or "hidden",
		Median(samples),
		Max(samples)
	)
end

-- The visible dungeon page, cold and cached; source reads use the same coroutine slice as the live tab.
local worstDungeon = 0
for _, instance in ipairs({ 43, 230, 429 }) do
	-- Keep allocations from the previous isolated harness out of this scenario's
	-- timed frames. The client owns GC scheduling, so this does not change addon
	-- behavior; it makes the benchmark measure the dungeon work itself.
	collectgarbage("collect")
	local h = harness.load({ questiedb = mirror, player = { level = 60 } })
	h.G.debugprofilestop = function()
		return os.clock() * 1000
	end
	h.ns.OpenWindow()
	h.flush()
	collectgarbage("collect")
	local reads, original = 0, h.ns.ReadDungeonDetails
	h.ns.ReadDungeonDetails = function(yield)
		reads = reads + 1
		return original(yield)
	end
	local frames = {}
	for _ = 1, 2 do
		local opened = os.clock()
		h.ns.Window.OpenDungeon(instance)
		frames[#frames + 1] = (os.clock() - opened) * 1000
		for _ = 1, 1000 do
			local started = os.clock()
			local ran = h.tick()
			frames[#frames + 1] = (os.clock() - started) * 1000
			if ran == 0 then
				break
			end
		end
	end
	h.G.AdventureGuideForeverWindow:Hide()
	h.ns.Window.Refresh()
	h.flush()
	check(reads == 1, "dungeon source read once across page shows")
	check(#h.errors == 0, "dungeon benchmark errors: " .. table.concat(h.errors, "\n"))
	worstDungeon = math.max(worstDungeon, Max(frames))
	lines[#lines + 1] = ("Dungeon %d frames: %.3f / %.3f ms (median / max)"):format(
		instance,
		Median(frames),
		Max(frames)
	)
end

print(table.concat(lines, "\n"))
if strict then
	check(worstDungeon < BUDGET_MS, ("dungeon frame max %.3f ms is over %d ms"):format(worstDungeon, BUDGET_MS))
	check(worstRebuild < BUDGET_MS, ("rebuild frame max %.3f ms is over %d ms"):format(worstRebuild, BUDGET_MS))
	check(worstTravel < BUDGET_MS, ("travel frame max %.3f ms is over %d ms"):format(worstTravel, BUDGET_MS))
	check(worstSession < BUDGET_MS, ("session frame max %.3f ms is over %d ms"):format(worstSession, BUDGET_MS))
	check(
		worstSlice < BUILD_BUDGET_MS,
		("QuestieDB build slice max %.3f ms is over %d ms"):format(worstSlice, BUILD_BUDGET_MS)
	)
end
assert(#failures == 0, table.concat(failures, "\n"))
print(
	(
		"plan_bench: %d profiles x %d samples; worst rebuild %.3f ms, travel %.3f ms, "
		.. "QuestieDB slice %.3f ms, session %.3f ms%s"
	):format(
		profiles,
		SAMPLES,
		worstRebuild,
		worstTravel,
		worstSlice,
		worstSession,
		strict and " (budget checked)" or ""
	)
)
