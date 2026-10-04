-- Run from the repository root: luajit tests/race_bit_spec.lua
-- A race's bit in a quest's race mask is 2 ^ (raceID - 1). The 32nd race's is 2 ^ 31, one past a signed 32-bit
-- integer, which the client's %d refuses and its bit library's shift does not hold in LuaJIT. The guide plans
-- for that race as for any other.
local harness = dofile("tests/harness.lua")

local h = harness.load({
	player = { level = 20, faction = "Alliance", raceID = 32, classID = 1, map = 1453, x = 0.5, y = 0.5 },
})
h.flush()
assert(#h.errors == 0, table.concat(h.errors, "\n"))
assert(h.ns.State.Player().raceBit == 2 ^ 31, "the 32nd race's bit is 2 ^ 31")
assert(h.ns.Model.HasBit(2 ^ 31, h.ns.State.Player().raceBit), "a quest for that race alone is the player's")
assert(not h.ns.Model.HasBit(2 ^ 31 - 1, h.ns.State.Player().raceBit), "a quest for the other races is not")
assert(h.ns.Route(), "a route is planned")

print("race_bit_spec: 5 checks passed")
