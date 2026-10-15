-- Run from the repository root: luajit tests/level_up_spec.lua
-- PLAYER_LEVEL_UP's own level (Core/State.lua State.Level): UnitLevel can still answer the old level when the
-- deferred rebuild reads it, so the event's level counts until UnitLevel catches up, and the rebuild plans for it.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local h = harness.load({ completed = { 844 }, log = {} })
h.flush()
local State = h.ns.State
local before = h.player.level
equal(State.Level(), before, "the client's level")

-- The event says one level more while UnitLevel still lags.
h.fire("PLAYER_LEVEL_UP", before + 1)
h.flush()
equal(State.Level(), before + 1, "the event's level while UnitLevel lags")
equal(State.Player().level, before + 1, "the planner's player has it")
equal(h.ns.Snapshot().player.level, before + 1, "and the rebuild planned for it")

-- UnitLevel catches up: its answer counts again, and a later lower answer (a level-down) is not held back.
h.player.level = before + 1
equal(State.Level(), before + 1, "caught up")
h.player.level = before
equal(State.Level(), before, "the event's level is forgotten once UnitLevel reached it")

-- An event with no level keeps the one announced before it; a loading screen forgets a stale announcement.
h.fire("PLAYER_LEVEL_UP", before + 2)
h.fire("PLAYER_LEVEL_UP")
h.flush()
equal(State.Level(), before + 2, "no payload: the earlier announcement stands")
h.fire("PLAYER_ENTERING_WORLD", false)
h.flush()
equal(State.Level(), before, "a loading screen: UnitLevel again")
equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))

print(("level_up_spec: %d checks passed"):format(checks))
