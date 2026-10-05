-- Run from the repository root: luajit tests/trainer_api_spec.lua
-- Tweaks Forever's API is consumed as a RANGE (v1 and v2), and v2's class trainers with their places give a class the
-- bundled trainer data does not place (Forever's extra combos) a trainer hint.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- v2: Training still answers (additive), and Trainers returns the class trainers with their places.
local h = harness.load({
	player = { level = 20, faction = "Horde", raceID = 2, classID = 2, map = 1420, x = 0.5, y = 0.6 },
	tf = {
		version = 2,
		spells = { { spellID = 635, name = "Holy Light", level = 20, cost = 0, line = "Holy", lineID = 594 } },
		trainers = {
			{ npc = 999003, name = "Other Side", map = 1420, x = 0.5, y = 0.6 },
			{ npc = 999001, name = "Aranis Hammerhand", map = 1420, x = 0.32, y = 0.62 },
			{ npc = 999002, name = "Placed Nowhere" },
		},
	},
})
local training, known = h.ns.Integrations.Training()
equal(known, true, "v2 Training answers")
equal(training and training.count, 1, "v2 Training counts the affordable spell")
local trainers = h.ns.Integrations.Trainers()
equal(#trainers, 3, "v2 Trainers returns every row")
equal(trainers[2].npc, 999001, "a trainer entry")
equal(trainers[2].place.map, 1420, "a trainer has its place")
equal(trainers[3].place, nil, "a trainer the data places nowhere has no place")

-- The aside falls back to the Tweaks trainer place: a Horde paladin has no bundled trainer. The trainer standing
-- on the player serves only the Alliance, so the nearest one who does not is taken.
h.ns.Data.npcs[999003] = { side = 1, place = { map = 1420, x = 0.5, y = 0.6 } }
h.ns.Asides.Refresh()
local aside
for _, entry in ipairs(h.ns.Asides.All()) do
	if entry.key == "trainer" then
		aside = entry
	end
end
equal(aside ~= nil, true, "the trainer aside is offered")
equal(aside.place and aside.place.map, 1420, "a class the bundled data does not place uses the Tweaks trainer place")
equal(aside.place.x, 0.32, "a trainer of the other side alone is passed over")

-- v1: no Trainers, and Training still answers.
local one = harness.load({
	tf = { version = 1, spells = { { spellID = 1, name = "X", level = 5, cost = 0, line = "L", lineID = 1 } } },
})
equal(one.ns.Integrations.Trainers(), nil, "v1 has no Trainers")
equal(select(2, one.ns.Integrations.Training()), true, "v1 Training still answers")

-- No Tweaks Forever at all.
local none = harness.load()
equal(none.ns.Integrations.Trainers(), nil, "no Tweaks, no Trainers")
equal(select(2, none.ns.Integrations.Training()), false, "no Tweaks, Training unknown")

-- A reply with a known, affordable fee but no level cannot be placed: it is left out like an unknown fee, never
-- passed to math.max. This is the owner crash: with a journey chosen, any rebuild (a setting click) raised here.
local unplaced = harness.load({
	charDB = { journey = "zone:1413" },
	tf = {
		version = 1,
		spells = {
			{ spellID = 1, name = "No level", cost = 0, line = "L", lineID = 1, general = true },
			{ spellID = 2, name = "Placed", level = 5, cost = 0, line = "L", lineID = 1, general = true },
		},
	},
})
local placed, placedKnown = unplaced.ns.Integrations.Training()
equal(placedKnown, true, "unplaced: the provider answered")
equal(placed and placed.count, 1, "unplaced: a spell without a level is left out")
equal(placed and placed.level, 5, "unplaced: the placed spell's level stands")
unplaced.ns.OpenWindow()
unplaced.flush()
equal(#unplaced.errors, 0, "unplaced: a rebuild with it does not raise\n" .. table.concat(unplaced.errors, "\n"))

assert(#h.errors == 0, table.concat(h.errors, "\n"))
print(("trainer_api_spec: %d checks passed"):format(checks))
