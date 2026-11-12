-- Run from the repository root: luajit tests/timed_quest_spec.lua
-- The state reader keeps only active native quest timers, and remains compatible with clients without the API.
local harness = dofile("tests/harness.lua")
local h = harness.load({
	log = {
		{ id = 101, title = "Active timer", level = 18, complete = false, objectives = {} },
		{ id = 102, title = "Expired timer", level = 18, complete = false, objectives = {} },
	},
})
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end

h.G.C_QuestLog.GetQuestTimers = function()
	return {
		{ questID = 101, questTimer = 900 },
		{ questID = 102, questTimer = 0 },
	}
end
local log = h.ns.State.Log()
equal(log[101].timed, 900, "state: active timer is recorded")
equal(log[102].timed, nil, "state: expired timer is ignored")

h.G.C_QuestLog.GetQuestTimers = nil
local ok, missing = pcall(h.ns.State.Log)
equal(ok, true, "state: missing timer API is safe")
equal(missing[101].timed, nil, "state: missing timer API has no timer")

print(("timed_quest_spec: %d checks passed"):format(checks))
