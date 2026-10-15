-- Run from the repository root: luajit tests/count_repaint_spec.lua
-- A quest-log burst that moves only objective counts (Model.LogShape, Model.Repaint, docs/design.md §4.4) repaints
-- the counts on the last route (every order and hold kept) instead of a full plan; a finished objective, a completed
-- quest, a quest accepted or dropped, or any other event plans in full.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- Deathknell: Scavenging Deathknell (3902) under way at 0/6, as objective_area_spec has it.
local h = harness.load({
	planned = true,
	charDB = { journey = "zone:1420" },
	completed = { 376 },
	player = { level = 4, raceID = 5, classID = 1, map = 1420, x = 0.3161, y = 0.656 },
	log = {
		{
			id = 3902,
			title = "Scavenging Deathknell",
			level = 3,
			complete = false,
			objectives = {
				{ type = "item", text = "Scavenged Goods: 0/6", done = false, have = 0, need = 6 },
			},
		},
	},
})
h.flush()

-- The count the route's step for 3902 shows.
local function Have()
	for _, step in ipairs(h.ns.Route().steps) do
		for _, objective in ipairs(step.objectives or {}) do
			if objective.quest == 3902 or (step.quests and step.quests[1] == 3902) then
				return objective.have
			end
		end
	end
end
equal(Have(), 0, "start: 0/6 on the route")

local function Tick(have, done)
	local objective = h.log[1].objectives[1]
	objective.have, objective.done, objective.text = have, done, ("Scavenged Goods: %d/6"):format(have)
	local plans = h.modelCalls.Plan
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	return h.modelCalls.Plan - plans
end

local function Keys()
	local keys = {}
	for _, step in ipairs(h.ns.Route().steps) do
		keys[#keys + 1] = step.key
	end
	return table.concat(keys, " ")
end
local order, here = Keys(), h.ns.Route().here
equal(Tick(1, false), 0, "a count: no full plan")
equal(Have(), 1, "a count: the route shows 1/6")
equal(Keys(), order, "a count: the steps keep their order")
equal(h.ns.Route().here, here, "a count: and the here hold")
equal(Tick(2, false), 0, "another count: still no full plan")
equal(Have(), 2, "another count: 2/6")
-- Something else in the same burst asks for a full plan.
h.log[1].objectives[1].have = 3
h.fire("QUEST_LOG_UPDATE")
h.fire("ZONE_CHANGED_NEW_AREA")
local plans = h.modelCalls.Plan
h.flush()
equal(h.modelCalls.Plan - plans, 1, "a count with a zone change: a full plan")
-- The objective finishing changes the log's shape: a full plan.
equal(Tick(6, true), 1, "the objective done: a full plan")
-- A count after a full plan is cheap again.
h.log[1].objectives[1].done = false
equal(Tick(5, false) >= 1, true, "undone again: the shape moved, a full plan")
equal(Tick(4, false), 0, "then a count: cheap")
equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))

print(("count_repaint_spec: %d checks passed"):format(checks))
