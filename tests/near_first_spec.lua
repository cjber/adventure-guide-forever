-- Run from the repository root: luajit tests/near_first_spec.lua
-- A ready hand-in or a pickup beside the player comes before the step the route heads for, and a broad objective area
-- counts the ground between its objectives as reached (docs/design.md §4.1 and §4.2). The player report: a level 5
-- orc warrior in the Valley of Trials, Simple Parchment ready to hand in to Frang 44 yards away, while the guide
-- headed for Sting of the Scorpid's objective hundreds of yards off. The real bundled data, through the scenario
-- helpers.
local harness = dofile("tests/harness.lua")

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- The step of the route with `key`, or nil.
local function step(route, key)
	for _, each in ipairs(route.steps) do
		if each.key == key then
			return each
		end
	end
	return nil
end

-- The town visit that hands in `id`.
local function handin(route, id)
	for _, each in ipairs(route.steps) do
		for _, other in ipairs(each.handins or {}) do
			if other == id then
				return each
			end
		end
	end
	return nil
end

-- The player of the report: a level 5 orc warrior in Durotar, Cutting Teeth (788) done, Simple Parchment (2383)
-- finished and waiting at Frang, Sting of the Scorpid (789) under way with the rest of the Valley of Trials' work
-- carried, so the town holds the hand-in and no pickups.
local function Valley(x, y)
	local h = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = "zone:1411" },
		completed = { 788 },
		player = { level = 5, faction = "Horde", raceID = 2, classID = 1, map = 1411, x = x, y = y },
		log = {
			{ id = 2383, title = "Simple Parchment", level = 1, complete = true, map = 1411, x = 0.4289, y = 0.6944 },
			{ id = 789, title = "Sting of the Scorpid", level = 3, complete = false },
			{ id = 790, title = "Burning Blade Medallion", level = 4, complete = false },
			{ id = 792, title = "Vile Familiars", level = 4, complete = false },
			{ id = 5441, title = "Thwarting the Peons", level = 4, complete = false },
			{ id = 4402, title = "Galgar's Cactus Apple Surprise", level = 3, complete = false },
		},
	})
	h.flush()
	return h
end

-- Standing at the near edge of Sting of the Scorpid's objective area, Frang 43 yd away: the ready hand-in leads, not
-- the objective's point 102 yd off. The route keeps the hand-in: a rebuild with nothing changed still leads with it.
do
	local h = Valley(0.42479, 0.68394)
	local route = h.ns.Route()
	local area, town = step(route, "area:789:4"), handin(route, 2383)
	equal(area ~= nil, true, "beside: the objective area is on the route")
	equal(town ~= nil, true, "beside: the ready hand-in is on the route")
	local player = h.ns.State.Player()
	local yards = h.ns.Model.Yards(h.ns.Data, player, town)
	equal(yards ~= nil and yards <= 60, true, "beside: the hand-in is within a short walk")
	equal(yards < h.ns.Model.Yards(h.ns.Data, player, area), true, "beside: nearer than the objective's point")
	equal(route.steps[1].key, town.key, "beside: the ready hand-in leads")
	equal(step(route, "area:789:4") ~= nil, true, "beside: the objective keeps its place after it")
	-- A rebuild with nothing changed holds the hand-in at the head.
	h.ns.Invalidate()
	h.flush()
	equal(h.ns.Route().steps[1].key, town.key, "beside: a rebuild keeps it leading")
	equal(#h.errors, 0, "beside: no errors")
end

-- Walking into the area, more than a short walk from the hand-in, releases it: the objective they stand in leads.
do
	local h = Valley(0.4150, 0.6650)
	local route = h.ns.Route()
	local area, town = step(route, "area:789:4"), handin(route, 2383)
	equal(area ~= nil and town ~= nil, true, "released: the area and the hand-in are on the route")
	local player = h.ns.State.Player()
	equal(h.ns.Model.Yards(h.ns.Data, player, town) > 60, true, "released: the hand-in is past a short walk")
	equal(route.steps[1].key, area.key, "released: the objective leads from inside it")
	equal(area.here, true, "released: the player is in the area")
	equal(#h.errors, 0, "released: no errors")
end

-- A broad objective area counts the ground between its objectives as reached. North of Galgar's Cactus Apple
-- Surprise's objectives, inside the ring merged round them but on no objective's ground, the step reads as being in
-- the area: no walking leg, and the merge is what puts the player there.
do
	local h = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = "zone:1411" },
		completed = { 788 },
		player = { level = 5, faction = "Horde", raceID = 2, classID = 1, map = 1411, x = 0.447, y = 0.6111 },
		log = {
			{ id = 4402, title = "Galgar's Cactus Apple Surprise", level = 3, complete = false },
			{ id = 5441, title = "Thwarting the Peons", level = 4, complete = false },
		},
	})
	h.flush()
	local route = h.ns.Route()
	local area = route.steps[1]
	equal(area ~= nil and area.kind == "area", true, "broad: an objective area leads")
	local player, data = h.ns.State.Player(), h.ns.Data
	local insideShape = false
	for _, shape in ipairs(area.shapes or {}) do
		local yards = h.ns.Model.Yards(data, player, shape)
		insideShape = insideShape or (yards ~= nil and yards <= shape.r)
	end
	equal(insideShape, false, "broad: outside every objective's own shape")
	local ring = h.ns.Model.Yards(data, player, area.shapes[1])
	equal(ring ~= nil and ring <= area.r, true, "broad: inside the ring merged round them")
	equal(area.here, true, "broad: the step reads as being in the area")
	equal(h.ns.Integrations.Travel(area), nil, "broad: no walking leg")
	equal(#h.errors, 0, "broad: no errors")
end

-- Galgar's Cactus Apple Surprise (4402) is known and offered to a level 3 to 5 orc or troll: in the log alone, its
-- prerequisite Cutting Teeth done, it is one of the town's pickups. The player report feared the guide did not know
-- it; it does, and the fix above puts a nearby town's offers ahead of a far objective.
for _, case in ipairs({
	{ label = "orc warrior", level = 3, raceID = 2, classID = 1 },
	{ label = "orc warrior", level = 5, raceID = 2, classID = 1 },
	{ label = "troll shaman", level = 4, raceID = 128, classID = 64 },
}) do
	local h = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = "zone:1411" },
		completed = { 788 },
		player = {
			level = case.level,
			faction = "Horde",
			raceID = case.raceID,
			classID = case.classID,
			map = 1411,
			x = 0.4289,
			y = 0.6944,
		},
		log = { { id = 789, title = "Sting of the Scorpid", level = 3, complete = false } },
	})
	h.flush()
	local offered = false
	for _, each in ipairs(h.ns.Route().steps) do
		for _, id in ipairs(each.pickups or {}) do
			offered = offered or id == 4402
		end
	end
	equal(
		offered,
		true,
		("pickup: the %s at %d is offered Galgar's Cactus Apple Surprise"):format(case.label, case.level)
	)
	equal(#h.errors, 0, "pickup: no errors")
end

-- The starting zones' class parchment quests are known for the right class and race: each is eligible for its own
-- mask at level 1 and 5, with the chain quest before it done.
do
	local ns = { Data = harness.data() }
	harness.model(ns)
	local data, Model = ns.Data, ns.Model
	local parchment = { 2383, 3083, 3087, 3088, 3089, 3090, 3091, 3092, 3095, 3096, 3100, 3102, 3109, 3113, 3118 }
	local known = 0
	for _, id in ipairs(parchment) do
		local quest = data.quests[id]
		if quest and quest.classes and quest.races then
			known = known + 1
			for _, level in ipairs({ 1, 5 }) do
				local completed = {}
				for _, pre in ipairs(quest.pre or {}) do
					completed[pre] = true
				end
				local player = {
					level = level,
					maxLevel = 60,
					side = quest.side,
					raceBit = quest.races,
					classBit = quest.classes,
					map = quest.zone,
					x = 0.5,
					y = 0.5,
				}
				equal(Model.Eligible(data, player, completed, {}, id), true, ("parchment %d at %d"):format(id, level))
			end
		end
	end
	equal(known, #parchment, "parchment: every starting class quest is in the data")

	-- A troll rogue's Encrypted Tablet is eligible; the mask is the troll's alone.
	local troll = { level = 5, maxLevel = 60, side = 2, raceBit = 128, classBit = 8, map = 1411, x = 0.5, y = 0.5 }
	equal(Model.Eligible(data, troll, { [788] = true }, {}, 3083), true, "parchment: troll rogue")
end

print(("near_first_spec: %d checks passed"):format(checks))
