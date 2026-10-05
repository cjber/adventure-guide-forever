-- Run from the repository root: luajit tests/race_bit_spec.lua
-- Forever's Skyborne are races 95 (Alliance) and 96 (Horde). QuestieDB gives them bits 32 and 33 of a quest's race
-- mask, past the client's 32-bit integers: a shift of the race's number wraps to 2 ^ 31, which the client's %d
-- refuses. The guide plans for a Skyborne as for any race, and a side's quests are theirs too.
local harness = dofile("tests/harness.lua")

-- Questie says which quests a character may take up; here, all of them.
local function Policy(loaded)
	loaded.G.Questie = { API = {
		isReady = true,
		RegisterOnReady = function(fn)
			fn()
		end,
	} }
	loaded.G.QuestieLoader = {
		ImportModule = function()
			return {
				IsDoable = function()
					return true
				end,
			}
		end,
	}
end

local h = harness.load({
	questiedb = harness.questieMirror(harness.data()),
	setup = Policy,
	player = { level = 16, faction = "Horde", raceID = 96, classID = 3, map = 1454, x = 0.37, y = 0.29 },
})
h.flush()
assert(#h.errors == 0, table.concat(h.errors, "\n"))
local player, HasBit = h.ns.State.Player(), h.ns.Model.HasBit
assert(player.raceBit == 2 ^ 33, "a Horde Skyborne's bit is QuestieDB's, 2 ^ 33")
assert(HasBit(2 ^ 33, player.raceBit), "a quest for the Horde Skyborne alone is the player's")
assert(not HasBit(2 ^ 32, player.raceBit), "a quest for the Alliance Skyborne is not")
assert(not HasBit(2, player.raceBit), "a quest for orcs alone is not")
local route = h.ns.Route()
assert(route and #route.steps > 0, "a route with steps is planned")
-- A quest whose mask is the whole Horde's carries no race rule: its side says who takes it.
local horde, orcs = 0, 0
for _, quest in pairs(h.ns.Data.quests) do
	if quest.side == 2 then
		horde = horde + (quest.races == nil and 1 or 0)
		orcs = orcs + (quest.races == 2 and 1 or 0)
	end
	assert(quest.races ~= 178 and quest.races ~= 77 and quest.races ~= 255, "a side's mask is no race rule")
end
assert(horde > 0, "the Horde's quests are open to every Horde race")
assert(orcs > 0, "a quest for orcs alone keeps its race rule")

print("race_bit_spec: 8 checks passed")
