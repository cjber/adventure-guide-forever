-- Run from the repository root: luajit tests/activity_spec.lua
-- Activity records count only authoritative QUEST_TURNED_IN events and remain local to this character.
local harness = dofile("tests/harness.lua")
local h = harness.load({ charDB = {} })
local api = h.G.AdventureGuideForever.API

local stats = api.Stats()
assert(#stats == 1 and stats[1].metric == "quest_turn_ins" and stats[1].value == 0, "new character has empty total")
h.fire("QUEST_TURNED_IN", 1001)
h.fire("QUEST_TURNED_IN", 1002)
h.fire("QUEST_TURNED_IN", 1001)
stats = api.Stats()
assert(stats[1].metric == "quest_turn_in" and stats[1].subject == "1001" and stats[1].value == 2, "per-quest counts")
assert(stats[2].subject == "1002" and stats[2].value == 1, "second quest count")
assert(stats[3].metric == "quest_turn_ins" and stats[3].value == 3, "aggregate count")
stats[1].value = -1
assert(api.Stats()[1].value == 2, "API result is a copy")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("activity_spec: 5 checks passed")
