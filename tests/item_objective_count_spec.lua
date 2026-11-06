-- Run from the repository root: luajit tests/item_objective_count_spec.lua
-- An item objective's count moving is the loot, and the client can report it on a later bag event, with its words
-- and its finished/complete flags a tick behind the count (#410). The stop's words follow the count, and a count that
-- reaches its need makes the quest complete, so the journey advances to the turn-in: counting the objective is not a
-- full plan until the count fills it (docs/design.md §4.4).
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- Washed Ashore (3524) in Darkshore: the one quest item the issue looted, still 0/1 in the log.
local h = harness.load({
	planned = true,
	charDB = { journey = "zone:1439" },
	completed = { 376 },
	player = { level = 14, raceID = 4, classID = 1, map = 1439, x = 0.364, y = 0.509 },
	log = {
		{
			id = 3524,
			title = "Washed Ashore",
			level = 13,
			complete = false,
			objectives = {
				{ type = "item", text = "0/1 Sea Turtle Remains", done = false, have = 0, need = 1 },
			},
		},
	},
})
h.flush()

local step = h.ns.Route().steps[1]
equal(step.key, "area:3524:4", "before: the objective area leads")
equal(step.title, "Collect 0/1 Sea Turtle Remains · Washed Ashore", "before: 0/1 on the stop")

-- QUEST_LOG_UPDATE can arrive before the client's quest log has the looted item's count: still 0/1.
h.fire("QUEST_LOG_UPDATE")
h.flush()
equal(h.ns.Route().steps[1].key, "area:3524:4", "early: a stale quest log event keeps the stop")
equal(h.ns.Route().steps[1].title, "Collect 0/1 Sea Turtle Remains · Washed Ashore", "early: and its count")

-- The bags then hold the item: the quest log's count moves to 1/1 while its words, finished flag and IsComplete can
-- still read as they did, and BAG_UPDATE_DELAYED is the client's later event for it.
h.log[1].objectives[1].have = 1
h.fire("BAG_UPDATE_DELAYED")
h.flush()

local route = h.ns.Route()
equal(route.steps[1].key, "turnin:3524", "looted: the journey advances to the turn-in")
equal(route.steps[1].title, "Turn in: Washed Ashore", "looted: named by the turn-in")
for _, each in ipairs(route.steps) do
	equal((each.title or ""):find("0/1", 1, true), nil, "looted: no stop keeps the stale count")
end
equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))

-- A partial item count (3/6) leaves the shape alone: the last route is repainted from the live count, with the
-- client's stale words replaced by the count it now reports.
local p = harness.load({
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
				{ type = "item", text = "0/6 Scavenged Goods", done = false, have = 0, need = 6 },
			},
		},
	},
})
p.flush()
equal(p.ns.Route().steps[1].title, "Collect 0/6 Scavenged Goods · Scavenging Deathknell", "partial: 0/6")
p.log[1].objectives[1].have = 3
local plans = p.modelCalls.Plan
p.fire("QUEST_LOG_UPDATE")
p.flush()
equal(p.modelCalls.Plan - plans, 0, "partial: no full plan")
equal(
	p.ns.Route().steps[1].title,
	"Collect 3/6 Scavenged Goods · Scavenging Deathknell",
	"partial: the stop's words follow the live count"
)
equal(#p.errors, 0, "errors\n" .. table.concat(p.errors, "\n"))

print(("item_objective_count_spec: %d checks passed"):format(checks))
