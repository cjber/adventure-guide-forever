-- Run from the repository root: luajit tests/timed_quest_spec.lua
--[[ A live quest timer (AGF709, C_QuestLog.GetTimeAllowed): the client's total/elapsed becomes one cached absolute
     deadline in State.Log, and an active timer moves its actionable objectives and ready hand-in to the head without
     breaking pickup/hand-in dependencies, merged stops, saved order or the combat refresh. A failed, expired or
     absent timer is never urgent, and elapsed advancing never re-plans by itself. ]]
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local NEAR = { id = 3902, title = "Scavenging Deathknell", level = 3, complete = false }
local TIMED_A = { id = 367, title = "A New Plague", level = 6, complete = false }
local TIMED_B = { id = 375, title = "The Chill of Death", level = 8, complete = false }

local function Copy(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function With(source, fields)
	local copy = Copy(source)
	for key, value in pairs(fields) do
		copy[key] = value
	end
	return copy
end

local function Objective()
	return { { type = "item", text = "Scavenged Goods: 0/6", done = false, have = 0, need = 6 } }
end

local function Load(options)
	local h = harness.load({
		planned = options.planned == true,
		charDB = { journey = "carry" },
		completed = { 376 },
		player = { level = 18, raceID = 2, classID = 7, map = 1420, x = 0.3161, y = 0.656 },
		log = options.log,
	})
	h.flush()
	return h
end

local function Keys(route)
	local keys = {}
	for _, step in ipairs(route.steps) do
		keys[#keys + 1] = step.key
	end
	return table.concat(keys, " ")
end

local function Head(h)
	return h.ns.Route().steps[1]
end

-- Whether a route still marks `id`'s step urgent.
local function Hurried(route, id)
	id = id or 367
	for _, step in ipairs(route.steps) do
		for _, quest in ipairs(step.quests or {}) do
			if quest == id and step.hurry then
				return true
			end
		end
	end
	return false
end

local function ByKey(route, key)
	for _, step in ipairs(route.steps) do
		if step.key == key then
			return step
		end
	end
end

-- A timer entry as the client keeps it: total and elapsed seconds. State.Log turns it into one absolute deadline.
local function Timer(quest, total, elapsed)
	quest.timer = { total = total, elapsed = elapsed }
	return quest
end

-- (a) A timed quest behind nearer ordinary work leads, in both planned and simple order, and says why.
for _, planned in ipairs({ false, true }) do
	local label = planned and "planned" or "nearest"
	local h = Load({
		planned = planned,
		log = {
			With(NEAR, { objectives = Objective() }),
			Timer(Copy(TIMED_A), 600, 0),
		},
	})
	local first = Head(h)
	equal(first.key, "area:367:4", label .. ": the timed objective leads")
	equal(first.quests[1], 367, label .. ": and it is the timed quest's step")
	equal(first.hurry, true, label .. ": marked as urgent")
	equal(first.reason, "before the quest timer runs out", label .. ": with the truthful reason")
	equal(#h.errors, 0, label .. ": no errors\n" .. table.concat(h.errors, "\n"))
end

-- (b) A ready timed hand-in follows its objectives: a complete timed quest's turn-in leads a nearer ordinary one.
do
	local h = Load({
		log = {
			{ id = 3902, title = NEAR.title, level = 3, complete = true, map = 1420, x = 0.3161, y = 0.656 },
			{ id = 367, title = TIMED_A.title, level = 6, complete = true, map = 1420, x = 0.4, y = 0.43 },
		},
	})
	Timer(h.log[2], 600, 0)
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local first = Head(h)
	equal(first.kind, "turnin", "hand-in: the timed turn-in is a turn-in step")
	equal(first.quests[1], 367, "hand-in: it leads")
	equal(first.hurry, true, "hand-in: marked urgent")
	local player, log = h.ns.State.Player(), h.ns.State.Log()
	equal(h.ns.Order.Valid(h.ns.Route().steps, player.logMax, log), true, "hand-in: the order stays legal")
end

-- (c) Several timers: the earliest exact deadline leads, and elapsed advancing or jittering keeps that order.
do
	local h = Load({
		log = {
			Timer(Copy(TIMED_A), 600, 0), -- deadline 700 at t=100
			Timer(Copy(TIMED_B), 600, 300), -- deadline 400 at t=100
		},
	})
	equal(Head(h).quests[1], 375, "two timers: the earlier deadline leads")
	local order = Keys(h.ns.Route())
	-- A rebuild after the same elapsed time has advanced sees the same cached deadline.
	h.time = h.time + 5
	h.log[1].timer.elapsed, h.log[2].timer.elapsed = 5, 305
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Keys(h.ns.Route()), order, "two timers: advancing elapsed keeps the order")
	-- A second's backward jitter is still the same timer, not a restart.
	h.log[1].timer.elapsed, h.log[2].timer.elapsed = 4, 304
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Keys(h.ns.Route()), order, "two timers: jitter keeps the order")
end

-- (c) A changed total while the timer stays active is a new deadline the shape must carry: the order reverses.
do
	local h = Load({ log = { Copy(TIMED_A), Copy(TIMED_B) } })
	h.log[1].timer = { total = 600, elapsed = 0 } -- deadline 700
	h.log[2].timer = { total = 600, elapsed = 300 } -- deadline 400
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Head(h).quests[1], 375, "deadline: the earlier timer leads")
	local shape = h.ns.Model.LogShape(h.ns.State.Log())
	h.log[1].timer.total = 300 -- deadline 400, tying 375; the lower quest ID then leads
	local moved = h.ns.Model.LogShape(h.ns.State.Log())
	equal(moved ~= shape, true, "deadline: a changed total changes the shape")
	local plans = h.modelCalls.Plan
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(h.modelCalls.Plan - plans >= 1, true, "deadline: the changed total plans in full")
	equal(Head(h).quests[1], 367, "deadline: the reversed equal-deadline tie leads by quest ID")
end

-- (d) Failed, expired and missing timers are not urgent, and a failed quest is never ready to hand in.
do
	local h = harness.load({
		log = {
			{
				id = 3902,
				title = NEAR.title,
				level = 3,
				complete = true,
				failed = true,
				objectives = { { type = "item", text = "Scavenged Goods: 6/6", done = true, have = 6, need = 6 } },
			},
			Timer({ id = 367, title = TIMED_A.title, level = 6, complete = false, objectives = {} }, 60, 60),
		},
	})
	local log = h.ns.State.Log()
	equal(log[3902].complete, false, "failed: IsComplete true does not leave it ready")
	equal(log[3902].failed, true, "failed: flagged")
	equal(log[3902].deadline, nil, "failed: no deadline")
	equal(log[367].deadline, nil, "expired: elapsed reaching total drops the deadline")
	h.log[2].timer = nil
	equal(h.ns.State.Log()[367].deadline, nil, "missing: no timer, no urgency")
end

-- (d/e) Shape moves only on the timer/failed transitions, never on a count.
do
	local h = harness.load({
		log = {
			{
				id = 3902,
				title = NEAR.title,
				level = 3,
				complete = false,
				objectives = { { type = "item", text = "Scavenged Goods: 0/6", done = false, have = 0, need = 6 } },
			},
		},
	})
	local plain = h.ns.Model.LogShape(h.ns.State.Log())
	h.log[1].objectives[1].have = 3
	equal(h.ns.Model.LogShape(h.ns.State.Log()), plain, "shape: a count alone changes nothing")
	h.log[1].timer = { total = 600, elapsed = 0 }
	local active = h.ns.Model.LogShape(h.ns.State.Log())
	equal(active ~= plain, true, "shape: a timer appearing plans in full")
	h.log[1].timer.elapsed = 120
	equal(h.ns.Model.LogShape(h.ns.State.Log()), active, "shape: elapsed advancing changes nothing")
	h.log[1].failed = true
	equal(h.ns.Model.LogShape(h.ns.State.Log()) ~= active, true, "shape: failing plans in full")
end

-- (e) A timer appearing on a counts-only event plans in full; an unchanged timer plus a count repaints.
do
	local h = Load({
		log = {
			With(NEAR, { objectives = Objective() }),
			Copy(TIMED_A),
		},
	})
	local waypoint = h.waypoint
	local plans = h.modelCalls.Plan
	h.log[2].timer = { total = 600, elapsed = 0 }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(h.modelCalls.Plan - plans >= 1, true, "repaint: a timer appearing forces a full plan")
	equal(Head(h).quests[1], 367, "repaint: and the timed step leads")
	local order = Keys(h.ns.Route())
	plans = h.modelCalls.Plan
	h.log[1].objectives[1].have, h.log[1].objectives[1].text = 2, "Scavenged Goods: 2/6"
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(h.modelCalls.Plan - plans, 0, "repaint: an unchanged timer plus a count is a repaint")
	equal(Keys(h.ns.Route()), order, "repaint: the order is kept")
	equal(h.waypoint, waypoint, "repaint: the waypoint is not moved")
	equal(#h.errors, 0, "repaint: no errors\n" .. table.concat(h.errors, "\n"))
end

-- (f) The one-shot deadline invalidation: armed once, not re-armed while the timer set stands, and cached expiry
-- ends urgency even when the client keeps answering the last stale active elapsed.
do
	local h = harness.load({ log = { Timer({ id = 367, title = TIMED_A.title, level = 6, complete = false }, 60, 0) } })
	-- The load already read the log once; clear the timer so the next reading re-arms from nothing.
	h.log[1].timer = nil
	h.ns.State.Log()
	h.counts.After = 0
	h.log[1].timer = { total = 60, elapsed = 0 }
	local log = h.ns.State.Log()
	equal(log[367].deadline, 160, "one-shot: the absolute deadline is GetTime() - elapsed + total")
	equal(h.counts.After, 1, "one-shot: exactly one deadline timer is armed")
	h.ns.State.Log()
	equal(h.counts.After, 1, "one-shot: the same deadline is not re-armed")
	h.time = 200 -- past the cached deadline; the API still answers the stale active timer
	log = h.ns.State.Log()
	equal(log[367].deadline, nil, "one-shot: the cached deadline passing removes urgency")
	equal(h.counts.After, 1, "one-shot: expiry does not re-arm")
	equal(h.ns.State.Log()[367].deadline, nil, "one-shot: a stale reading cannot recreate the expired timer")
	equal(h.counts.After, 1, "one-shot: and re-arms nothing")
end

-- (f) The captured deadline callback itself: it invalidates once with no quest event, the rebuild drops the urgency,
-- and the same stale active timer is not re-armed.
do
	local h = Load({
		log = {
			With(NEAR, { objectives = Objective() }),
			Copy(TIMED_A),
		},
	})
	-- Re-arm from a clean timer set, capturing only the deadline shot.
	h.log[2].timer = nil
	h.ns.State.Log()
	local captured
	local realAfter = h.G.C_Timer.After
	h.G.C_Timer.After = function(_, fn)
		captured = fn
	end
	h.log[2].timer = { total = 60, elapsed = 0 }
	h.ns.State.Log()
	h.G.C_Timer.After = realAfter
	equal(captured ~= nil, true, "callback: the deadline shot is armed")
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Hurried(h.ns.Route()), true, "callback: the timer is urgent before it runs")
	h.time = 200 -- past the cached deadline, with no QUEST_LOG_UPDATE and the API still stale
	captured()
	h.flush()
	equal(Hurried(h.ns.Route()), false, "callback: expiry alone clears the urgency")
	local before = h.counts.After
	h.ns.State.Log()
	equal(h.counts.After, before, "callback: the stale timer is not re-armed after expiry")
end

-- (f) A non-rebuild observer read (QuestWatch, pins, RXP) just after the deadline tombstones the timer and clears
-- `armedDeadline`; the already-armed shot must still invalidate rather than leaving the drawn route hurried.
do
	local h = Load({
		log = {
			With(NEAR, { objectives = Objective() }),
			Copy(TIMED_A),
		},
	})
	h.log[2].timer = nil
	h.ns.State.Log()
	local captured
	local realAfter = h.G.C_Timer.After
	h.G.C_Timer.After = function(_, fn)
		captured = fn
	end
	h.log[2].timer = { total = 60, elapsed = 0 }
	h.ns.State.Log()
	h.G.C_Timer.After = realAfter
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Hurried(h.ns.Route()), true, "observer: the timer is urgent before the deadline")
	h.time = 160.01
	h.ns.State.Log() -- an observer read, not a route rebuild
	equal(Hurried(h.ns.Route()), true, "observer: the drawn route is still hurried until a rebuild")
	local plans = h.modelCalls.Plan
	captured()
	h.flush()
	equal(h.modelCalls.Plan - plans >= 1, true, "observer: the armed shot still invalidates")
	equal(Hurried(h.ns.Route()), false, "observer: the rebuild clears the stale urgency")
end

-- (c/g) Equal deadlines tie by the lowest quest ID, including a merged stop, and a lead the order refuses does not
-- cancel the others.
do
	local h = harness.load({ log = {} })
	local Laps = h.ns.Planner.Laps
	local log = {
		[60] = { id = 60, complete = false, deadline = 500 },
		[50] = { id = 50, complete = false, deadline = 500 },
	}
	local merged = { kind = "area", key = "area:60", quests = { 60, 50 }, objectives = { { id = 60 }, { id = 50 } } }
	equal(Laps.Urgent(log, merged).id, 50, "merged: the lowest quest ID wins an equal-deadline tie")
	local other = { kind = "area", key = "area:70", quests = { 70 }, objectives = { { id = 70 } } }
	log[70] = { id = 70, complete = false, deadline = 500 }
	local moved = Laps.LeadUrgent({ merged, other }, log, function()
		return true
	end)
	equal(moved[1], merged, "merged: the stop whose canonical timer is lowest leads")
	-- The soonest lead (A) is illegal alone; the later one (B) still leads when the whole set cannot stand.
	local A = { kind = "area", key = "area:10", quests = { 10 }, objectives = { { id = 10 } } }
	local B = { kind = "area", key = "area:20", quests = { 20 }, objectives = { { id = 20 } } }
	local pickup = { kind = "town", key = "town:x", pickups = { 10 }, handins = {}, quests = { 10 } }
	log[10] = { id = 10, complete = false, deadline = 300 }
	log[20] = { id = 20, complete = false, deadline = 400 }
	local infeasible = Laps.LeadUrgent({ pickup, A, B }, log, function(steps)
		-- The pickup must stay before A's objectives; B has no pickup here.
		local pickupAt, aAt
		for index, step in ipairs(steps) do
			pickupAt = step == pickup and index or pickupAt
			aAt = step == A and index or aAt
		end
		return pickupAt and aAt and pickupAt < aAt or false
	end)
	equal(infeasible[1], B, "fallback: an infeasible lead does not cancel a feasible one")
end

-- (h) Saved order wins over automatic urgency, and its dependency edges stay intact.
do
	local h = harness.load({ log = {} })
	local timed = { kind = "turnin", key = "turnin:10", quests = { 10 }, handins = { 10 } }
	local ordinary = { kind = "turnin", key = "turnin:20", quests = { 20 }, handins = { 20 } }
	local log = {
		[10] = { id = 10, complete = true, deadline = 500 },
		[20] = { id = 20, complete = true },
	}
	local merged = h.ns.Order.Merge({ timed, ordinary }, { "turnin:20", "turnin:10" }, 40, log)
	equal(merged[1], ordinary, "custom: the player's saved order leads")
	equal(h.ns.Order.Valid(merged, 40, log), true, "custom: dependencies still hold")
end

-- (i) Combat refresh: an active timer leads in the carry journey; a quest that fails mid-fight loses the stale line.
do
	local h = Load({
		log = {
			With(NEAR, { objectives = Objective() }),
			Copy(TIMED_A),
		},
	})
	h.log[2].timer = { total = 600, elapsed = 0 }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	h.combat = true
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local first = Head(h)
	equal(first.quests[1], 367, "combat: the active timer still leads the carry journey")
	equal(first.hurry, true, "combat: and is marked urgent")
	h.log[2].failed = true
	h.log[2].timer = nil
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local stale = false
	for _, step in ipairs(h.ns.Route().steps) do
		for _, id in ipairs(step.quests or {}) do
			if id == 367 and step.hurry then
				stale = true
			end
		end
	end
	equal(stale, false, "combat: a failed quest drops its stale hurry")
	h.combat = false
end

-- (i) Combat refresh of a retained story: a timer that starts mid-fight leads there too, and failing restores the
-- step's own story reason rather than leaving the urgency line behind.
do
	local h = harness.load({
		charDB = { journey = "zone:1420" },
		completed = { 376 },
		player = { level = 18, raceID = 2, classID = 7, map = 1420, x = 0.3161, y = 0.656 },
		log = {
			With(NEAR, { objectives = Objective() }),
			Copy(TIMED_A),
		},
	})
	h.flush()
	local ordinary = Head(h).key
	h.combat = true
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Head(h).key, ordinary, "story combat: no timer, the story order stands")
	h.log[2].timer = { total = 600, elapsed = 0 }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local timed = Head(h)
	equal(timed.quests[1], 367, "story combat: the timer leads the retained story")
	equal(timed.hurry, true, "story combat: marked urgent")
	equal(timed.hurryKept ~= nil, true, "story combat: its own reason is kept")
	h.log[2].failed = true
	h.log[2].timer = nil
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local after
	for _, step in ipairs(h.ns.Route().steps) do
		after = step.quests[1] == 367 and step or after
	end
	equal(after and after.hurry, nil, "story combat: failure drops the urgency mark")
	equal(after and after.reason ~= "before the quest timer runs out", true, "story combat: the story reason returns")
	h.combat = false
end

-- (i) A hurry over a standing area clears its "here" hold in the combat reorder too, as Laps does in a full build.
do
	local h = Load({
		log = {
			With(NEAR, { objectives = Objective() }),
			Timer(Copy(TIMED_A), 600, 0),
		},
	})
	equal(Head(h).quests[1], 367, "here: the timer leads the full build")
	equal(ByKey(h.ns.Route(), "area:3902:4").here, nil, "here: a full build clears the displaced area")
	h.combat = true
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local standing = ByKey(h.ns.Route(), "area:3902:4")
	equal(standing and standing.here, nil, "here: the combat refresh clears the displaced area")
	h.combat = false
end

-- (i) A retained story step keeps its "here" in the last route while the combat refresh clears its copy.
do
	local h = harness.load({
		charDB = { journey = "zone:1420" },
		completed = { 376 },
		player = { level = 18, raceID = 2, classID = 7, map = 1420, x = 0.3161, y = 0.656 },
		log = {
			With(NEAR, { objectives = Objective() }),
			Copy(TIMED_A),
		},
	})
	h.flush()
	local standing = ByKey(h.ns.Route(), "area:3902:4")
	equal(standing and standing.here, true, "here copy: the player's area leads before the timer")
	h.log[2].timer = { total = 600, elapsed = 0 }
	h.combat = true
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(ByKey(h.ns.Route(), "area:3902:4").here, nil, "here copy: the displaced area is cleared")
	equal(standing.here, true, "here copy: the last route's step is not mutated")
	h.combat = false
end

-- (i) A pruned merged area takes the fresh reason Tell writes, not the hurry reason from before the prune.
do
	local h = harness.load({
		charDB = { journey = "zone:1420" },
		completed = { 376 },
		player = { level = 18, raceID = 2, classID = 7, map = 1420, x = 0.3161, y = 0.656 },
		log = {
			With(NEAR, { objectives = Objective() }),
			Timer({
				id = 364,
				title = "The Mindless Ones",
				level = 2,
				complete = false,
				objectives = {
					{ type = "monster", text = "Mindless One slain: 0/1", done = false, have = 0, need = 1 },
				},
			}, 600, 0),
		},
	})
	h.flush()
	local merged = Head(h)
	equal(merged.key, "area:364:0", "prune: the timed and ordinary objectives merge")
	equal(merged.hurry, true, "prune: the merged area is urgent")
	equal(merged.hurryKept.reason, "2 quests here", "prune: its own reason is kept")
	h.combat = true
	h.log[2].complete = true
	h.log[2].timer = nil
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local after = ByKey(h.ns.Route(), "area:364:0")
	equal(after and after.hurry, nil, "prune: the timed quest finishing clears the urgency")
	equal(after and after.reason ~= "2 quests here", true, "prune: the fresh reason replaces the pre-prune one")
	h.combat = false
end

-- (j) A timer changes order and reason only: no waypoint, quest watch or selection side effects.
do
	local h = Load({
		log = {
			With(NEAR, { objectives = Objective() }),
			Copy(TIMED_A),
		},
	})
	h.watched = { 3902 }
	local waypoint, watched, selected = h.waypoint, #h.watched, #h.selectedQuests
	h.log[2].timer = { total = 600, elapsed = 0 }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Head(h).quests[1], 367, "side effects: the timer reorders the plan")
	equal(h.waypoint, waypoint, "side effects: no waypoint")
	equal(#h.watched, watched, "side effects: no quest watch change")
	equal(#h.selectedQuests, selected, "side effects: no quest selection")
end

-- (k) A held step yields to an active timer, and the hold (and its own reason) returns when the timer ends.
do
	local h = Load({
		log = {
			With(NEAR, { objectives = Objective() }),
			Copy(TIMED_A),
		},
	})
	local ordinary = Head(h).key
	local function Build(held)
		return h.ns.Shown.Build({
			data = h.ns.Data,
			player = h.ns.State.Player(),
			completed = h.ns.State.Completed(),
			log = h.ns.State.Log(),
			prefs = h.ns.Prefs(),
			mapName = h.ns.State.MapName,
			instanceName = h.ns.State.InstanceName,
			last = h.ns.Route(),
			held = held,
			combat = false,
			repaint = false,
		})
	end
	h.log[2].timer = { total = 600, elapsed = 0 }
	local route = Build(ordinary)
	equal(route.steps[1].key, "area:367:4", "held: the active timer leads past the hold")
	equal(route.steps[1].hurry, true, "held: it is marked urgent")
	equal(route.steps[1].hurryKept ~= nil, true, "held: the step's own reason is kept under the urgency line")
	h.log[2].timer = nil
	route = Build(ordinary)
	equal(route.steps[1].key, ordinary, "held: the hold returns when the timer ends")
	local timed
	for _, step in ipairs(route.steps) do
		timed = step.key == "area:367:4" and step or timed
	end
	equal(timed and timed.hurry, nil, "held: the timed step is no longer urgent")
	equal(timed and timed.reason ~= "before the quest timer runs out", true, "held: its own reason is restored")
end

print(("timed_quest_spec: %d checks passed"):format(checks))
