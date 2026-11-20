-- Ordered chain pools retain accepted chapters, overlapping tails and card contents.
local function same(a, b, path)
	path = path or "output"
	assert(type(a) == type(b), path .. " type")
	if type(a) ~= "table" then
		assert(a == b, path .. " value")
		return
	end
	for k, v in pairs(b) do
		same(a[k], v, path .. "." .. tostring(k))
	end
	for k in pairs(a) do
		assert(b[k] ~= nil, path .. " extra " .. tostring(k))
	end
end
local function run(extra, variant, journey)
	local ns = {}
	dofile("tests/harness.lua").model(ns)
	local world = {
		quests = {},
		zones = { [1] = { name = "Here", min = 10, max = 20 }, [2] = {
			name = "Away",
			min = 10,
			max = 20,
		} },
	}
	local function quest(id, zone)
		world.quests[id] = {
			title = "Quest " .. id,
			level = 16,
			min = 10,
			side = 2,
			zone = zone,
			start = { map = zone, x = 0.4, y = 0.5, name = "Giver" },
			finish = { map = zone, x = 0.4, y = 0.5, name = "Ender" },
			need = { [1] = 2 },
			obj = { { 1, id * 100, 500, 10, 1 } },
		}
	end
	for id = 1, 9 do
		quest(id, 1)
	end
	world.quests[1].next = 2
	world.quests[2].pre = { 1 }
	world.quests[2].next = 3
	world.quests[3].pre = { 2 }
	world.quests[4].next = 5
	world.quests[5].pre = { 4 }
	world.quests[5].next = 6
	world.quests[6].pre = { 5 }
	-- A converging tail belongs to both heads although Story(tail) is nil.
	world.quests[7].next = 9
	world.quests[8].next = 9
	world.quests[7].group = 42
	world.quests[8].group = 42
	for id = 100, 99 + extra do
		quest(id, 2)
	end
	local who =
		{ level = 16, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5, tracked = {} }
	local prefs = {
		quests = true,
		dungeons = false,
		skipped = {},
		optimisedRoute = true,
		journey = journey or "chain:4",
		notInterested = {},
	}
	local completed, log = {}, {}
	if variant == 2 then
		completed[4] = true
		log[5] = { id = 5, title = "Quest 5", level = 16, complete = false }
	end
	if variant == 3 then
		prefs.notInterested["chain:7"] = true
		prefs.journey = journey or "chain:8"
	end
	if variant == 4 then
		prefs.quests = false
	end
	if variant == 5 then
		who.maxLevel = 16
		world.instances = { [36] = { name = "Hall" } }
		world.quests[6].dungeon = 36
	end
	if variant == 6 then
		world.quests[5].pre, world.quests[6].pre = nil, nil
		world.quests[4].group, world.quests[5].group, world.quests[5].min = 45, 45, 12
	end
	if variant == 7 then
		log[4] = { id = 4, title = "Quest 4", level = 16, complete = true }
		world.quests[4].finish = nil
	end
	local output = ns.Model.Journeys(world, who, completed, log, prefs)
	return output
end
local function card(cards, key)
	for _, v in ipairs(cards) do
		if v.key == key then
			return v
		end
	end
end
local function pickups(value)
	local found = {}
	for _, step in ipairs(value.steps) do
		for _, id in ipairs(step.pickups or {}) do
			found[#found + 1] = id
		end
	end
	return found
end
for variant = 1, 7 do
	for _, key in ipairs({ "chain:4", "chain:7", "chain:8" }) do
		local a, b = run(0, variant, key), run(12, variant, key)
		same(card(a, key), card(b, key), key)
	end
end
-- Only the chosen chain is a card: Continue lists zones (design 2.3).
same(pickups(assert(card(run(0, 1, "chain:7"), "chain:7"))), { 7, 9 }, "first converging chain")
same(pickups(assert(card(run(0, 1, "chain:8"), "chain:8"))), { 8, 9 }, "second converging chain")
local unchosen = run(0, 1)
assert(card(unchosen, "chain:7") == nil and card(unchosen, "chain:8") == nil, "an unchosen chain is not offered")
assert(card(unchosen, "chain:4") ~= nil, "the chosen chain is offered")
local accepted = assert(card(run(0, 2), "chain:4"))
assert(accepted.story.chapter == 2, "accepted chapter remains the lead")
same(pickups(accepted), {}, "accepted quest is never offered as a pickup")
assert(accepted.steps[1].quests[1] == 5, "accepted chapter retains objective work")
assert(card(run(0, 3, "chain:7"), "chain:7") == nil, "dismissed chain stays hidden even when chosen")
assert(card(run(0, 3), "chain:8") ~= nil, "the other chain stays")
assert(card(run(0, 4), "chain:4") == nil, "quests off removes pickup story")
assert(card(run(0, 5), "chain:4").instance == 36, "stranded preparation retains its dungeon")
local exclusive = assert(card(run(0, 6), "chain:4"))
same(pickups(exclusive), { 4, 6 }, "exclusive group offers its first eligible member")
assert(exclusive.count == "3 quests near your level", "card count retains all eligible members")
assert(exclusive.story.chapter == 1, "exclusive group keeps the first chapter as lead")
assert(card(run(0, 7), "chain:4") == nil, "unplaced accepted chapter creates no route card")
print("chain_pools_spec: card and route semantics passed")
