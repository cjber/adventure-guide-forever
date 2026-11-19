-- Run from the repository root: luajit tests/questie_tracker_default_spec.lua
-- "Turn off Questie's tracker" (#858) is off unless the player ticks it in the guide's settings: a saved value that
-- only carries the old default (on) moves to off, and a tick the player gave stays.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local fresh = harness.load()
equal(fresh.ns.Setting("hideQuestieTracker"), false, "off for a new player")

local old = harness.load({ db = { hideQuestieTracker = true } })
equal(old.ns.Setting("hideQuestieTracker"), false, "a saved old default moves to off")

local ticked = harness.load({ db = { hideQuestieTracker = true, questieTrackerChoiceMade = true } })
equal(ticked.ns.Setting("hideQuestieTracker"), true, "a tick the player gave stays")

fresh.ns.SetSetting("hideQuestieTracker", true)
equal(fresh.ns.Setting("questieTrackerChoiceMade"), true, "ticking it in the guide's settings is remembered")

print(("questie_tracker_default_spec: %d checks passed"):format(checks))
