-- Run from the repository root: luajit tests/laps_spec.lua
-- The lap route's invariants (docs/design.md §4.2) on random characters over the real data: each stands at a random
-- quest giver near their level, with an older history done and a random log under a random log limit. Every card they
-- are offered, chosen, is walked in order as a player would play it: a new quest's objectives never before its pickup,
-- a hand-in only once its objectives are done, the log never past its limit, one quest of an exclusive group at most,
-- and every step on a point the data has, for several seeds of characters; AGF_LAPS_SEED runs one seed alone.
local ns = {}
assert(loadfile("Data/Quests.lua"))("AdventureGuideForever", ns)
-- Core.lua for ns.L, the planner's copy; its load-time hooks into the client are stubbed, since only the copy is read.
local core = assert(loadfile("Core.lua"))
setfenv(
	core,
	setmetatable({
		EventUtil = { ContinueOnAddOnLoaded = function() end },
		SlashCmdList = {},
		CreateFrame = function()
			return { SetScript = function() end }
		end,
	}, { __index = _G })
)
core("AdventureGuideForever", ns)
assert(loadfile("Model.lua"))("AdventureGuideForever", ns)
local Model, data = ns.Model, ns.Data
-- Several sets of characters by default: one seed alone let seed-dependent failures through.
local SEEDS, CHARACTERS = { tonumber(os.getenv("AGF_LAPS_SEED")) }, 150
if #SEEDS == 0 then
	SEEDS = { 4, 2, 3, 5, 6, 9, 12, 99 }
end

-- The data's places, keyed to 4 places: a step's point must be one of them.
local places = {}
local function Key(map, x, y)
	return ("%d:%.4f:%.4f"):format(map or 0, x or -1, y or -1)
end
local function Add(place)
	if place and place.map then
		places[Key(place.map, place.x, place.y)] = true
	end
end
local givers, groups = {}, {}
for id, quest in pairs(data.quests) do
	Add(quest.start)
	Add(quest.finish)
	for _, area in ipairs(quest.obj or {}) do
		places[Key(area[5] or quest.zone, area[2] / 1000, area[3] / 1000)] = true
	end
	if quest.start and quest.start.hub and quest.side ~= 3 and not quest.dungeon and not quest.raid then
		givers[#givers + 1] = id
	end
	if quest.group then
		groups[quest.group] = groups[quest.group] or {}
		table.insert(groups[quest.group], id)
	end
end
for _, npc in pairs(data.npcs or {}) do
	Add(npc.place)
end
table.sort(givers)

-- A step's point is a place the data has, or, for an area, where the player enters it: inside the ring of one of its
-- shapes, each centred on a place the data has, with the ring's middle one too (Model.lua Enter).
local function Placed(step)
	if places[Key(step.map, step.x, step.y)] then
		return true
	end
	local ring = step.ring
	if not (ring and places[Key(ring.map, ring.x, ring.y)]) then
		return false
	end
	for _, shape in ipairs(step.shapes or {}) do
		local yards = Model.Yards(data, step, shape)
		if places[Key(shape.map, shape.x, shape.y)] and yards and yards <= shape.r then
			return true
		end
	end
	return false
end

local checks, failures = 0, {}
local function check(ok, text)
	checks = checks + 1
	if not ok then
		failures[#failures + 1] = text
	end
end

-- A random character at a random giver of one side: level about the quest's, the quests five or more levels below
-- mostly done, and a log of quests they could take, some finished, within a random limit.
local function Character()
	local at = data.quests[givers[math.random(#givers)]]
	local side = at.side
	local level = math.max(1, math.min(60, at.level + math.random(-2, 1)))
	local player = {
		level = level,
		maxLevel = 60,
		side = side,
		raceBit = side == 1 and 1 or 2,
		classBit = 2 ^ (math.random(1, 9) - 1),
		map = at.start.map,
		x = at.start.x,
		y = at.start.y,
		logMax = math.random(4, 25),
	}
	local completed, log = {}, {}
	local ids = {}
	for id in pairs(data.quests) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local quest = data.quests[id]
		if quest.level <= level - 5 and math.random() < 0.8 and Model.Eligible(data, player, completed, log, id) then
			completed[id] = true
		end
	end
	local size = math.random(0, player.logMax)
	local held = 0
	for _, id in ipairs(ids) do
		local quest = data.quests[id]
		if
			held < size
			and quest.zone == player.map
			and math.random() < 0.3
			and not Model.IsGray(quest.level, level)
			and Model.Eligible(data, player, completed, log, id)
		then
			local done = math.random() < 0.4
			local entry = { id = id, title = quest.title, level = quest.level, complete = done }
			if done and quest.finish then
				entry.map, entry.x, entry.y = quest.finish.map, quest.finish.x, quest.finish.y
			end
			log[id], held = entry, held + 1
		end
	end
	return player, completed, log, held
end

-- Walks `steps` in order as the player would.
local function Walk(where, steps, player, completed, log, held)
	local picked, worked, handed, count = {}, {}, {}, held
	local later = {}
	for index, step in ipairs(steps) do
		for _, objective in ipairs(step.objectives or {}) do
			later[objective.id] = index
		end
	end
	for index, step in ipairs(steps) do
		local label = ("%s, step %d %s"):format(where, index, step.key)
		check(Placed(step), label .. ": a point the data has")
		for _, id in ipairs(step.kind == "town" and step.handins or {}) do
			local entry = log[id]
			check(entry or picked[id], label .. ": hands in " .. id .. ", carried or picked up")
			check((later[id] or 0) < index, label .. ": hands in " .. id .. " after all its objectives")
			if not (entry and entry.complete) then
				check(worked[id] or not next(data.quests[id].need or {}), label .. ": " .. id .. " done before")
			end
			check(not handed[id], label .. ": hands in " .. id .. " once")
			handed[id], count = true, count - 1
		end
		for _, id in ipairs(step.kind == "turnin" and step.quests or {}) do
			check(log[id] and log[id].complete, label .. ": a turn-in of a finished quest")
			handed[id], count = true, count - 1
		end
		for _, id in ipairs(step.pickups or {}) do
			check(not log[id] and not picked[id], label .. ": picks " .. id .. " up once")
			for _, other in ipairs(groups[data.quests[id].group] or {}) do
				check(
					other == id or not (completed[other] or log[other] or picked[other]),
					label .. ": " .. id .. " is the only one of its group"
				)
			end
			picked[id], count = true, count + 1
			check(count <= player.logMax, ("%s: the log at %d of %d"):format(label, count, player.logMax))
		end
		if step.kind == "area" or step.kind == "dungeon" then
			for _, objective in ipairs(step.objectives or {}) do
				local id = objective.id
				check(log[id] or picked[id], label .. ": " .. id .. "'s objective after its pickup")
				worked[id] = true
			end
		end
	end
end

-- The card's keys in order.
local function Keys(route, key)
	local keys = {}
	for _, journey in ipairs(route.journeys) do
		for _, step in ipairs(journey.key == key and journey.steps or {}) do
			keys[#keys + 1] = step.key
		end
	end
	return table.concat(keys, " ")
end

-- Whether the player stands where step 1 is, which leads whatever the committed order (docs/design.md §4.2): a town
-- with a giver or hand-in within 100 yd, else an open area's ring.
local function Standing(player, route)
	local head = route.steps[1]
	for _, spot in pairs(head and head.kind ~= "area" and head.hub and head.spots or {}) do
		local yards = Model.Yards(data, player, spot)
		if yards and yards <= 100 then
			return true
		end
	end
	return head ~= nil and Model.Here(data, player, route.steps) == 1
end

-- Stability (docs/design.md §4.2) on the chosen card: a rebuild with nothing changed gives the same route; one
-- after the player walked to a later step, or took up a quest the route does not hold, keeps step 1 unless the player
-- stands where another leads; and each such route still walks in order.
local stable = { same = 0, walked = 0, added = 0, fronted = 0 }
local function Stability(where, player, completed, log, held, prefs)
	local first = Model.Plan(data, player, completed, log, prefs)
	local key = first.journey
	if not (key and first.steps[2]) then
		return
	end
	-- The first build commits an order; a rebuild keeps its step 1 and may only settle what the order left out (a
	-- visit back past the step limit), and from then on every rebuild with nothing changed is the same route.
	local again = Model.Plan(data, player, completed, log, prefs, nil, nil, first)
	local head = first.steps[1].key
	check(again.steps[1] and again.steps[1].key == head, where .. ": the first rebuild keeps step 1")
	local third = Model.Plan(data, player, completed, log, prefs, nil, nil, again)
	check(Keys(third, key) == Keys(again, key), where .. ": a rebuild with nothing changed keeps the route")
	stable.same = stable.same + (Keys(again, key) == Keys(first, key) and 1 or 0)
	-- Walked to a later step's point.
	local to = first.steps[math.random(2, #first.steps)]
	local moved = { map = to.map, x = to.x, y = to.y }
	for name, value in pairs(player) do
		moved[name] = moved[name] or value
	end
	local walked = Model.Plan(data, moved, completed, log, prefs, nil, nil, again)
	if walked.journey == key and walked.steps[1] then
		local fronted = Standing(moved, walked)
		check(walked.steps[1].key == head or fronted, where .. ": walked to " .. to.key .. ", step 1 holds")
		stable.walked, stable.fronted = stable.walked + 1, stable.fronted + (fronted and 1 or 0)
		Walk(where .. " walked", walked.steps, moved, completed, log, held)
	end
	-- A quest of the zone the route holds nowhere, taken up while the log has room for it and every pickup on the
	-- route, so the log's limit changes nothing.
	-- Nor the quest a breadcrumb on the route leads to, which takes the breadcrumb off it.
	local on, picks = {}, 0
	for _, journey in ipairs(first.journeys) do
		for _, step in ipairs(journey.steps) do
			for _, id in ipairs(step.quests) do
				on[id] = true
				on[data.quests[id].breadcrumb or id] = true
			end
		end
	end
	for _, step in ipairs(again.steps) do
		picks = picks + #(step.pickups or {})
	end
	local extra
	for id, quest in pairs(data.quests) do
		if
			not on[id]
			and not log[id]
			and quest.zone == player.map
			and quest.obj
			and (not extra or id < extra)
			and Model.Eligible(data, player, completed, log, id)
		then
			extra = id
		end
	end
	if extra and held + picks < (player.logMax or math.huge) then
		log[extra] =
			{ id = extra, title = data.quests[extra].title, level = data.quests[extra].level, complete = false }
		local added = Model.Plan(data, player, completed, log, prefs, nil, nil, again)
		if added.journey == key and added.steps[1] then
			check(
				added.steps[1].key == head or Standing(player, added),
				where .. ": took up " .. extra .. ", step 1 holds"
			)
			stable.added = stable.added + 1
			Walk(where .. " took up " .. extra, added.steps, player, completed, log, held + 1)
		end
		log[extra] = nil
	end
end

local plans, started = 0, os.clock()
local function Play(seed, character)
	local player, completed, log, held = Character()
	local prefs = { quests = true, dungeons = false, skipped = {} }
	local route = Model.Plan(data, player, completed, log, prefs)
	plans = plans + 1
	local where = ("seed %d, character %d (level %d at %s)"):format(
		seed,
		character,
		player.level,
		Key(player.map, player.x, player.y)
	)
	if route.journeys[1] then
		Walk(where .. " card 1", route.journeys[1].steps, player, completed, log, held)
	end
	for _, journey in ipairs(route.journeys) do
		prefs.journey = journey.key
		local chosen = Model.Plan(data, player, completed, log, prefs)
		plans = plans + 1
		for _, card in ipairs(chosen.journeys) do
			if card.key == journey.key then
				Walk(where .. " " .. card.key, card.steps, player, completed, log, held)
			end
		end
	end
	prefs.journey = nil
	Stability(where, player, completed, log, held, prefs)
	plans = plans + 4
end
for _, seed in ipairs(SEEDS) do
	math.randomseed(seed)
	for character = 1, CHARACTERS do
		Play(seed, character)
	end
end

-- A short lap still shows the next town's pickups: a human at Raven Hill, Duskwood, with Wolves at Our Heels (226)
-- under way, Jitters' Growling Gut (5) finished and 28 quests from Westfall and Redridge carried, gets Watcher Dodds's
-- Eight-Legged Menaces (245) after the lap back to Lars, and the log's 30 of 40 leave it room.
do
	local carried = {}
	for id, quest in pairs(data.quests) do
		if
			(quest.side == 1 or quest.side == 3)
			and (quest.zone == 1433 or quest.zone == 1436)
			and quest.level >= 14
			and quest.level <= 22
			and quest.start
			and not quest.elite
		then
			carried[#carried + 1] = id
		end
	end
	table.sort(carried)
	for _, level in ipairs({ 19, 20 }) do
		local player = {
			level = level,
			maxLevel = 60,
			side = 1,
			raceBit = 1,
			classBit = 1,
			map = 1431,
			x = 0.162,
			y = 0.365,
			logMax = 40,
		}
		local log, completed = {}, {}
		for index = 1, 28 do
			local id = carried[index]
			log[id] = { id = id, title = data.quests[id].title, level = data.quests[id].level, complete = false }
		end
		log[226] = { id = 226, title = data.quests[226].title, level = data.quests[226].level, complete = false }
		log[5] = { id = 5, title = data.quests[5].title, level = data.quests[5].level, complete = true }
		local done = { [1426] = true, [1429] = true, [1432] = true, [1433] = true, [1436] = true }
		for id, quest in pairs(data.quests) do
			if (quest.side == 1 or quest.side == 3) and done[quest.zone] and not log[id] then
				completed[id] = true
			end
		end
		local prefs = { quests = true, dungeons = false, skipped = {}, journey = "zone:1431" }
		local where = ("Raven Hill at level %d"):format(level)
		local steps
		for _, journey in ipairs(Model.Plan(data, player, completed, log, prefs).journeys) do
			steps = journey.key == prefs.journey and journey.steps or steps
		end
		check(steps ~= nil, where .. ": the Duskwood card")
		local handed, picked = nil, nil
		for index, step in ipairs(steps or {}) do
			for _, id in ipairs(step.handins or {}) do
				handed = id == 226 and index or handed
			end
			for _, id in ipairs(step.pickups or {}) do
				picked = id == 245 and index or picked
			end
		end
		check(handed ~= nil, where .. ": the lap under way hands in Wolves at Our Heels")
		check(picked ~= nil and picked > (handed or 0), where .. ": Eight-Legged Menaces after it")
		Walk(where, steps or {}, player, completed, log, 30)
	end
end

for index = 1, math.min(10, #failures) do
	print("  " .. failures[index])
end
print(("laps_spec: %d checks, %d failed; %d plans in %.1f s"):format(checks, #failures, plans, os.clock() - started))
print(
	("laps_spec: stability: %d first rebuilds the same, %d walked (%d led by where they stand), %d taken up"):format(
		stable.same,
		stable.walked,
		stable.fronted,
		stable.added
	)
)
if #failures > 0 then
	os.exit(1)
end
