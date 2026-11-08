-- Run from the repository root: luajit tests/darkshore_chain_spec.lua
-- "It's All Fun and Games Until..." (98042) starts at the Twilight Tome, the hand-in for "The Twilight Camp" (949)
-- and the giver of "Return to Onu" (950), so it belongs to the middle of the Master's Glaive chain. QuestieDB's
-- Forever record has no prerequisite for it, and the route offered it at the Tome in the south before the chain's
-- first quest, "Cave Mushrooms" (947), in Auberdine (#496).
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local ns = {}
ns.Data = harness.data()
harness.model(ns)
local Model, data = ns.Model, ns.Data

-- The missing link: the Forever quest waits for the chain's middle chapter, The Twilight Camp.
equal(data.quests[98042].pre and data.quests[98042].pre[1], 949, "the Twilight Tome quest needs The Twilight Camp")
equal(data.quests[98042].preAny, nil, "the link is an all-of prerequisite, not an alternative")

local player = {
	level = 15,
	maxLevel = 60,
	side = 1,
	raceBit = 8, -- Night Elf
	classBit = 4, -- Hunter
	map = 1439,
	x = 0.3854, -- at the Twilight Tome, the quest's start
	y = 0.8605,
	logMax = 20,
}
local completed = {}
for id, quest in pairs(data.quests) do
	if quest.zone == 1438 and (quest.side == 1 or quest.side == 3) then
		completed[id] = true
	end
end
local prefs = { quests = true, dungeons = false, skipped = {}, optimisedRoute = true }

local function Holds(steps, id)
	for _, step in ipairs(steps) do
		for _, pickup in ipairs(step.pickups or {}) do
			if pickup == id then
				return true
			end
		end
	end
	return false
end

equal(Model.Eligible(data, player, completed, {}, 98042), false, "before the chain: the middle quest is locked")
local route = Model.Plan(data, player, completed, {}, prefs)
equal(Holds(route.steps, 98042), false, "before the chain: the route does not offer it")
equal(Holds({ route.steps[1] }, 947), true, "the chain's first quest leads, in Auberdine")

-- Once the chain reaches the Tome, the quest is open and the route takes it.
completed[947], completed[948], completed[944], completed[949] = true, true, true, true
equal(Model.Eligible(data, player, completed, {}, 98042), true, "after the chain: the middle quest is open")
local after = Model.Plan(data, player, completed, {}, prefs)
equal(Holds(after.steps, 98042), true, "after the chain: the route offers it at the Tome")

print(("darkshore_chain_spec: %d checks passed"):format(checks))
