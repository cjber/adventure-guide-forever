-- Run from the repository root: luajit tests/redridge_chain_spec.lua
-- "Show of Force" (98407) is offered by Deputy Feldon only once "Encroaching Gnolls" (244), the quest that sends the
-- player to him, is turned in. QuestieDB's Forever record has no prerequisite for it, so the route sent the player to
-- Feldon before Guard Parker's Encroaching Gnolls (#642).
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

-- The missing link: Show of Force waits for Encroaching Gnolls.
equal(data.quests[98407].pre and data.quests[98407].pre[1], 244, "Show of Force needs Encroaching Gnolls")
equal(data.quests[98407].preAny, nil, "the link is an all-of prerequisite, not an alternative")

local player = {
	level = 15,
	maxLevel = 60,
	side = 1,
	raceBit = 1, -- Human
	classBit = 1, -- Warrior
	map = 1433,
	x = 0.1037, -- at Guard Parker, where Encroaching Gnolls starts
	y = 0.7126,
	logMax = 20,
}
-- Every other Redridge quest is done, so the route has nothing but this chain to weigh.
local completed = {}
for id, quest in pairs(data.quests) do
	if id ~= 244 and id ~= 98407 and quest.zone == 1433 and (quest.side == 1 or quest.side == 3) then
		completed[id] = true
	end
end
local prefs = { quests = true, dungeons = false, skipped = {}, journey = "zone:1433", optimisedRoute = true }

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

equal(Model.Eligible(data, player, completed, {}, 98407), false, "before Encroaching Gnolls: Show of Force is locked")
local route = Model.Plan(data, player, completed, {}, prefs)
equal(Holds(route.steps, 98407), false, "before Encroaching Gnolls: the route does not offer it")
equal(Holds(route.steps, 244), true, "the route sends the player to Encroaching Gnolls first")

-- Encroaching Gnolls turned in opens Show of Force at the same NPC.
completed[244] = true
equal(Model.Eligible(data, player, completed, {}, 98407), true, "after Encroaching Gnolls: Show of Force is open")
local after = Model.Plan(data, player, completed, {}, prefs)
equal(Holds(after.steps, 98407), true, "after Encroaching Gnolls: the route offers it at Deputy Feldon")
equal(Holds(after.steps, 244), false, "after Encroaching Gnolls: it is no longer offered")

print(("redridge_chain_spec: %d checks passed"):format(checks))
