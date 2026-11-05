-- Run from the repository root: luajit tests/journey_default_spec.lua
-- Quests in your log is the journey a player who has not picked one gets (#378), ahead of zone stories and
-- RestedXP guides. The guide stays selectable and takes over only when the player picks it.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local LOG = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } }

-- No journey picked and a RestedXP guide loaded: the planner's default, Quests in your log, still leads.
local h = harness.load({ completed = { 844 }, log = LOG })
h.flush()
equal(h.ns.Route().journey, "carry", "without a choice the default is Quests in your log")
equal(h.ns.Route().chosen, false, "and it is still a suggestion, not a choice")
dofile("tests/rxp_fixture.lua")(h)
h.flush()
local guide = assert(h.ns.RestedXP.Journey())
equal(h.ns.Route().journey, "carry", "a loaded RestedXP guide does not take over an unchosen route")
equal(h.ns.Route().chosen, false, "nor does it count as a choice")
equal(h.ns.Route().steps[1].rxpIndex, nil, "the route is the log's, not the guide's")
equal(h.ns.Prefs().journey, nil, "nothing is saved as chosen")
local cards = h.ns.Model.Cards(h.ns.Route())
equal(cards[1] and cards[1].key, "carry", "Quests in your log is the first card in the picker")
equal(cards[2] and cards[2].key, "zone:1413", "the zone story follows it")
equal(cards[3] and cards[3].key, guide.key, "the RestedXP guide stays selectable after them")
equal(h.ns.Overview.InGroup(h.ns.Route().journeys, "continue")[1].key, "carry", "the Continue header opens on it")

-- An existing character with autoStart off, still without a choice: the same default holds.
local paused = harness.load({ spf = "v1", db = { autoStart = false }, completed = { 844 }, log = LOG })
paused.flush()
dofile("tests/rxp_fixture.lua")(paused)
paused.flush()
equal(paused.ns.Route().journey, "carry", "autoStart off keeps Quests in your log as the default")
equal(paused.ns.Route().chosen, false, "and does not make it a choice")

-- An existing character whose saved choice is a zone keeps that choice, with a guide loaded too.
local saved = harness.load({ completed = { 844 }, log = LOG, charDB = { journey = "zone:1442" } })
saved.flush()
dofile("tests/rxp_fixture.lua")(saved)
saved.flush()
equal(saved.ns.Route().journey, "zone:1442", "a saved zone choice is not replaced by a loaded guide")
equal(saved.ns.Route().chosen, true, "it is still the player's choice")

-- Picking the guide chooses it and hands over the route, as before.
h.ns.Choose(guide.key, true)
h.flush()
equal(h.ns.Route().journey, guide.key, "picking the guide chooses it")
equal(h.ns.Route().chosen, true, "and records that choice")
equal(h.ns.Route().steps[1].rxpIndex ~= nil, true, "the guide's step leads once picked")
equal(h.ns.Prefs().journey, guide.key, "the picked guide is saved")

print(("journey_default_spec: %d checks passed"):format(checks))
