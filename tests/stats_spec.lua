-- Local activity remains available after peer leaderboards are removed.
local harness = dofile("tests/harness.lua")
local h = harness.load({ charDB = {} })
local api = h.G.AdventureGuideForever.API

local stats = api.Stats()
assert(#stats > 0 and stats[1].metric == "quest_turn_ins", "local stats remain available")
assert(api.Leaderboard == nil, "the public leaderboard API is removed")
h.fire("QUEST_TURNED_IN", 1001)
assert(api.Stats()[#api.Stats()].value == 1, "local turn-ins remain counted")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("stats_spec: 3 checks passed")
