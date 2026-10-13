-- Class spell reminders and automatic trainer stops are opt-in.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Load(db)
	return harness.load({
		db = db,
		charDB = { journey = "zone:1413" },
		talents = 1,
		tf = { spells = { { name = "Lightning Bolt", level = 18, cost = 0, line = "Elemental", lineID = 375 } } },
	})
end
local function Has(h, key)
	for _, aside in ipairs(h.ns.Asides.All()) do
		if aside.key == key then
			return true
		end
	end
	return false
end
local h = Load()
h.flush()
equal(h.ns.Setting("trainingReminders"), false, "new and missing settings default off")
equal(Has(h, "trainer"), false, "default has no spell reminder")
equal(h.ns.Snapshot().player.train, nil, "default adds no automatic spell training stop")
equal(h.tf.TrainableSpells, 0, "default does not query class spell training")
equal(Has(h, "talents"), true, "talent reminder remains independent")
h.ns.SetSetting("trainingReminders", true)
h.flush()
equal(Has(h, "trainer"), true, "opt-in shows the reminder")
equal(h.ns.Snapshot().player.train ~= nil, true, "opt-in enables automatic trainer stops")
h.ns.SetSetting("trainingReminders", false)
h.flush()
equal(Has(h, "trainer"), false, "opting out removes the reminder")
equal(h.ns.Snapshot().player.train, nil, "opting out removes automatic training")
local saved = Load({ trainingReminders = true })
saved.flush()
equal(Has(saved, "trainer"), true, "explicit saved opt-in survives loading")
-- A burst of PLAYER_MONEY (every coin looted) asks Tweaks Forever once per reader, a moment later, and its answer
-- still lands.
local asked = saved.tf.TrainableSpells
for _ = 1, 20 do
	saved.fire("PLAYER_MONEY")
end
equal(saved.tf.TrainableSpells, asked, "a money event defers the training question")
saved.tick()
-- Once for the route's trainer stop (Core) and once for the trainer aside (Asides), not once per coin.
equal(saved.tf.TrainableSpells, asked + 2, "a burst of money events asks once per reader")
local spells = saved.G.TweaksForever.API.TrainableSpells
saved.G.TweaksForever.API.TrainableSpells = function()
	local list = spells()
	list[#list + 1] = { name = "Earth Shock", level = 18, cost = 0, line = "Elemental", lineID = 375 }
	return list
end
saved.fire("PLAYER_MONEY")
saved.flush()
equal(saved.ns.Snapshot().player.train.count, 2, "a moved answer after the burst rebuilds the route")
equal(#h.errors + #saved.errors, 0, "settings changes do not raise errors")
print(("training_reminders_spec: %d checks passed"):format(checks))
