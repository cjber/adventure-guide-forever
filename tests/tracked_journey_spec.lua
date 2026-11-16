-- Run from the repository root: luajit tests/tracked_journey_spec.lua
-- #772: My tracked quests routes exactly the quests the player tracks, in the planner's own order, including the
-- ready hand-ins among them. Trainer destinations are chosen explicitly in its menu.
local harness = dofile("tests/harness.lua")
local checks = 0

local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	{ id = 850, title = "Kolkar Leaders", level = 15, complete = false },
}

local function Load(watched, options)
	options = options or {}
	return harness.load({
		planned = true,
		db = { autoStart = false },
		charDB = options.charDB,
		completed = { 844 },
		log = options.log or LOG,
		logMax = options.logMax,
		setup = function(h)
			h.watched = watched
		end,
	})
end

local function Card(h, kind)
	for _, journey in ipairs(h.ns.Route().journeys) do
		if journey.kind == kind then
			return journey
		end
	end
end

local function Keys(journey)
	local keys = {}
	for index, step in ipairs(journey.steps) do
		keys[index] = step.key
	end
	return table.concat(keys, "|")
end

local function Holds(h, journey, id)
	for _, step in ipairs(journey.steps) do
		for _, quest in ipairs(h.ns.LogQuests(step)) do
			if quest == id then
				return true
			end
		end
	end
	return false
end

do
	-- Every log quest tracked: the card holds exactly the planner's route for the log's quests, ready hand-in first
	-- where the planner puts it. Comparing it with Clean up my log over the same log proves it reuses that order.
	local h = Load({ 845, 843 }, { log = { LOG[1], LOG[2] }, logMax = 2 })
	h.flush()
	local tracked, carry = Card(h, "tracked"), Card(h, "carry")
	check(tracked ~= nil, "all tracked: the My tracked quests card is offered")
	equal(tracked.title, h.ns.L.JOURNEY_TRACKED, "all tracked: its title")
	equal(tracked.reason, h.ns.L.TRACKED_REASON, "all tracked: its reason")
	equal(Keys(tracked), Keys(carry), "all tracked: the planner's order, not a second one")
	equal(tracked.ready, 1, "all tracked: the ready hand-in is counted")
	equal(tracked.underway, 1, "all tracked: the quest under way is counted")
	equal(Holds(h, tracked, 845), true, "all tracked: the finished quest's hand-in is included")
	equal(Holds(h, tracked, 843), true, "all tracked: the quest under way is included")
	equal(#h.errors, 0, "all tracked: errors\n" .. table.concat(h.errors, "\n"))
end

do
	-- One quest untracked: it stays off the card, while the tracked ones are routed. Choosing the card follows it.
	local h = Load({ 845, 843 }, { logMax = 3 })
	h.flush()
	local tracked = Card(h, "tracked")
	check(tracked ~= nil, "tracked subset: the card is offered")
	equal(Holds(h, tracked, 845), true, "tracked subset: the tracked hand-in is on it")
	equal(Holds(h, tracked, 843), true, "tracked subset: the tracked quest under way is on it")
	equal(Holds(h, tracked, 850), false, "tracked subset: a quest the player does not track is left out")
	local ids, held = 0, {}
	for _, step in ipairs(tracked.steps) do
		for _, quest in ipairs(h.ns.LogQuests(step)) do
			held[quest] = true
		end
	end
	for _ in pairs(held) do
		ids = ids + 1
	end
	equal(ids, 2, "tracked subset: exactly the two tracked quests")
	h.ns.Choose("tracked", true)
	h.flush()
	equal(h.ns.Route().journey, "tracked", "tracked subset: the card can be chosen")
	equal(h.ns.Route().chosen, true, "tracked subset: choosing it is the player's choice")
	equal(h.ns.CurrentJourney() and h.ns.CurrentJourney().kind, "tracked", "tracked subset: the route shows the card")
	equal(#h.errors, 0, "tracked subset: errors\n" .. table.concat(h.errors, "\n"))
end

do
	-- A leading journey's own quests are tracked for it, not by the player: they do not make a second copy of the
	-- journey. A quest the player tracks by hand still opens My tracked quests without the journey's quests.
	local h = Load({}, { log = LOG, logMax = 3, charDB = { journey = "zone:1413" } })
	h.flush()
	equal(Card(h, "tracked"), nil, "leading journey: no duplicate of its own tracked quests")
	h.watched[#h.watched + 1] = 843
	h.fire("QUEST_WATCH_LIST_CHANGED", 843, true)
	h.ns.Invalidate()
	h.flush()
	local tracked = Card(h, "tracked")
	check(tracked ~= nil, "leading journey: a quest the player tracks by hand opens the card")
	equal(Holds(h, tracked, 843), true, "leading journey: the hand-tracked quest is routed")
	equal(Holds(h, tracked, 845), false, "leading journey: the journey's own tracked quest is not")
	equal(#h.errors, 0, "leading journey: errors\n" .. table.concat(h.errors, "\n"))
end

do
	-- Nothing tracked: no card, so the guide is unchanged for a player who never used the tracker.
	local h = Load({}, { logMax = 3 })
	h.flush()
	equal(Card(h, "tracked"), nil, "nothing tracked: no card")
	equal(#h.errors, 0, "nothing tracked: errors\n" .. table.concat(h.errors, "\n"))
end

-- A deliberately chosen trainer is a destination, even without spells waiting or a quest in that town.
for _, planned in ipairs({ false, true }) do
	local h = Load({ 845 }, { charDB = { journey = "tracked", optimisedRoute = planned } })
	h.flush()
	local ids = {}
	for id, npc in pairs(h.ns.Data.npcs) do
		if npc.class and h.ns.Model.HasBit(npc.side, h.ns.State.Player().side) and npc.place.map ~= 1413 then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	check(#ids > 1, "trainer fixtures exist")
	local prefs = h.ns.Prefs()
	prefs.trainerStops = { [ids[1]] = true, [ids[2]] = true }
	h.ns.Invalidate()
	h.flush()
	local route = Card(h, "tracked")
	for _, id in ipairs({ ids[1], ids[2] }) do
		local found
		for _, stop in ipairs(route.steps) do
			if stop.key == "chosen-trainer:" .. id then
				found = stop
			end
		end
		check(found ~= nil, "chosen trainer is routed, planned=" .. tostring(planned))
		equal(found.place, h.ns.Data.npcs[id].place.name, "specific NPC retained")
		equal(#found.quests, 0, "no invented quest")
	end
	equal(Holds(h, route, 845), true, "hand-in retained with chosen trainers")
	prefs.trainerStops = {}
	h.ns.Invalidate()
	h.flush()
	for _, stop in ipairs(Card(h, "tracked").steps) do
		equal(stop.chosenTrainer, nil, "unticking removes chosen trainer")
	end
	equal(#h.errors, 0, "trainer choice errors\n" .. table.concat(h.errors, "\n"))
end

-- Exercise the actual menu callbacks, including removing a destination and the scrollable zone hierarchy.
do
	local h = Load({ 845 })
	h.flush()
	local card = Card(h, "tracked")
	local owner = h.G.CreateFrame("Button", nil, h.G.UIParent)
	h.ns.Menu.Journey(owner, card)
	local choices
	for _, entry in ipairs(h.menu.entries) do
		if entry.text == h.ns.L.TRAINER_STOPS then
			choices = entry
		end
	end
	check(choices ~= nil, "trainer chooser is reachable from the card")
	local zone = choices.entries[1]
	check(zone and #zone.entries > 0, "trainer choices grouped by map")
	local entry = zone.entries[1]
	equal(entry.isSelected(), false, "trainer initially unselected")
	entry.onClick()
	equal(entry.isSelected(), true, "menu selects trainer")
	h.flush()
	local found = false
	for _, stop in ipairs(Card(h, "tracked").steps) do
		found = found or stop.chosenTrainer == true
	end
	equal(found, true, "menu selection reaches planner")
	entry.onClick()
	equal(entry.isSelected(), false, "menu removes trainer")
	h.flush()
	equal(#h.errors, 0, "menu errors\n" .. table.concat(h.errors, "\n"))
end

-- Selection never manufactures a point or permits the other faction, and stale saved identities are ignored.
do
	local h = Load({ 845 })
	h.flush()
	local services = h.ns.Planner.Services
	local function Npc(side, place)
		return { class = 7, upto = 60, side = side, place = place }
	end
	local valid = { map = 1413, x = 0.5, y = 0.5, name = "Trainer" }
	local data = {
		npcs = {
			[1] = Npc(2, valid),
			[2] = Npc(1, valid),
			[3] = Npc(2, { map = 1413, name = "Unknown" }),
		},
	}
	local player = { side = 2 }
	equal(#services.Choices(data, player), 1, "only placed friendly trainers offered")
	local stops =
		services.ChosenTrainers(data, player, { trainerStops = { [1] = true, [2] = true, [3] = true, [99] = true } })
	equal(#stops, 1, "invalid and stale saved choices ignored")
	equal(stops[1].map, 1413, "authoritative map")
	equal(stops[1].x, 0.5, "authoritative coordinate")
end

-- Tracking changes alone rebuild the card, and untracking remains effective while the card leads.
do
	local h = Load({ 845, 843 }, { charDB = { journey = "tracked", journeyWatch = true } })
	h.flush()
	h.G.C_QuestLog.RemoveQuestWatch(843)
	h.fire("QUEST_WATCH_LIST_CHANGED", 843, false)
	h.flush()
	equal(Holds(h, Card(h, "tracked"), 843), false, "untracking removes a saved quest while leading")
	h.G.C_QuestLog.AddQuestWatch(850)
	h.fire("QUEST_WATCH_LIST_CHANGED", 850, true)
	h.flush()
	equal(Holds(h, Card(h, "tracked"), 850), true, "tracking alone refreshes the card")
	h.G.C_QuestLog.RemoveQuestWatch(845)
	h.G.C_QuestLog.RemoveQuestWatch(850)
	h.fire("QUEST_WATCH_LIST_CHANGED", 845, false)
	h.fire("QUEST_WATCH_LIST_CHANGED", 850, false)
	h.flush()
	equal(Card(h, "tracked"), nil, "untracking the last quests removes the card")
	equal(h.G.C_QuestLog.GetQuestWatchType(843), nil, "ending journey does not restore a deliberate untrack")
end

-- The client raises watch events synchronously for addon-owned edits too.
do
	local h = Load({ 845, 843 }, { charDB = { journeyWatch = true } })
	h.flush()
	local api = h.G.C_QuestLog
	local add, remove = api.AddQuestWatch, api.RemoveQuestWatch
	api.AddQuestWatch = function(id)
		local result = add(id)
		h.fire("QUEST_WATCH_LIST_CHANGED", id, true)
		return result
	end
	api.RemoveQuestWatch = function(id)
		remove(id)
		h.fire("QUEST_WATCH_LIST_CHANGED", id, false)
	end
	h.ns.Choose("zone:1413", true)
	h.flush()
	check(h.ns.State.Tracked()[843], "guide hiding a watch preserves the player's choice")
	h.ns.Choose("tracked", true)
	h.flush()
	check(Holds(h, Card(h, "tracked"), 843), "restoring hidden watches preserves tracked route")
	equal(#h.errors, 0, "synchronous watch event errors")
end

print(("tracked_journey_spec: %d checks passed"):format(checks))
