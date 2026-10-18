-- Run from the repository root: luajit tests/expiring_spec.lua
-- A quest item that runs out (docs/design.md §4.1): while the bags hold one, the quest it belongs to goes first, its
-- hand-in once it is done, and says why. Apothecary Zamah (853) hands the player Rendered Spores, which last 45
-- minutes (Data/Geometry.lua `expiring`, from ItemSparse), to take to Thunder Bluff.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local SPORES = 5027
local ns = {}
harness.model(ns)
local data = harness.data()
equal(data.expiring[SPORES], 2700, "data: Rendered Spores last 45 minutes")
equal(data.expiring[10790], nil, "data: an item that lasts a fortnight is no hurry")
equal(data.quests[853].expires and data.quests[853].expires[1], SPORES, "catalogue: the quest's item runs out")

-- Model.LogShape: carrying the item is part of the log's shape, so picking it up or losing it plans in full.
local entry = { id = 853, complete = true, objectives = {} }
local plain = ns.Model.LogShape({ [853] = entry })
entry.expiring = SPORES
equal(ns.Model.LogShape({ [853] = entry }) ~= plain, true, "shape: carrying an expiring item changes it")

-- An area moved up keeps its line when a count tick repaints it (Model.Repaint tells areas again).
local area = { quests = { 1, 2 }, hurry = "before Rendered Spores runs out" }
ns.Planner.Steps.Tell(area)
equal(area.reason, "before Rendered Spores runs out", "repaint: the hurry line outlives a recount")

local function Load(options)
	local h = harness.load({
		spf = "ended",
		charDB = { journey = "carry" },
		completed = { 844 },
		items = { [SPORES] = { name = "Rendered Spores" } },
		bags = options.bags,
		planned = options.planned,
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 853, title = "Apothecary Zamah", level = 15, complete = true },
		},
	})
	h.flush()
	return h
end

local function Handing(step, id)
	for _, other in ipairs(step.handins or (step.kind == "turnin" and step.quests) or {}) do
		if other == id then
			return true
		end
	end
	return false
end

for _, planned in ipairs({ false, true }) do
	local label = planned and "planned" or "nearest"
	local h = Load({ planned = planned })
	local first = h.ns.Route().steps[1]
	equal(Handing(first, 853), false, label .. ": without the spores, the far hand-in waits")
	h = Load({ planned = planned, bags = { [SPORES] = 1 } })
	first = h.ns.Route().steps[1]
	equal(Handing(first, 853), true, label .. ": with them, Zamah's hand-in goes first")
	equal(first.reason, "before Rendered Spores runs out", label .. ": and says why")
	equal(#h.errors, 0, label .. ": no errors\n" .. table.concat(h.errors, "\n"))
	-- The item gone (it ran out), the usual order comes back: the hurry never enters the committed order.
	h.bags[SPORES] = nil
	h.fire("BAG_UPDATE_DELAYED")
	h.flush()
	first = h.ns.Route().steps[1]
	equal(Handing(first, 853), false, label .. ": the spores gone (a bag event), the hurry ends")
	equal(first.reason ~= "before Rendered Spores runs out", true, label .. ": the spores gone, no hurry line")
	-- And back in the bags, the bag event alone brings it back.
	h.bags[SPORES] = 1
	h.fire("BAG_UPDATE_DELAYED")
	h.flush()
	equal(Handing(h.ns.Route().steps[1], 853), true, label .. ": the spores back, the hurry again")
end

-- With no quest of that kind in the log, a bag change plans nothing.
do
	local h = harness.load({
		spf = "ended",
		charDB = { journey = "carry" },
		completed = { 844 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	})
	h.flush()
	local builds = h.modelCalls.Journeys
	h.fire("BAG_UPDATE_DELAYED")
	h.flush()
	equal(h.modelCalls.Journeys, builds, "bags: nothing to watch, no rebuild")
end

-- An item the client hasn't named yet still says why.
do
	local h = harness.load({
		spf = "ended",
		charDB = { journey = "carry" },
		completed = { 844 },
		bags = { [SPORES] = 1 },
		log = { { id = 853, title = "Apothecary Zamah", level = 15, complete = true } },
	})
	h.flush()
	equal(h.ns.Route().steps[1].reason, "before a quest item runs out", "unnamed: the generic line")
end

print(("expiring_spec: %d checks passed"):format(checks))
