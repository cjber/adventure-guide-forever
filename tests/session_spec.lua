local harness = dofile("tests/harness.lua")
local checks = 0
local function eq(a, b, label)
	checks = checks + 1
	assert(a == b, (label or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local h = harness.load({ spf = "ended" })
local ns, calls, seconds, failure = h.ns, 0, 20, nil
local function Step(key, x)
	return {
		key = key,
		kind = "trainer",
		verb = "trainer",
		title = "Train in " .. key,
		reason = "Training",
		detail = "Training",
		quests = {},
		map = 1413,
		x = x,
		y = 0.3,
	}
end
local steps = { Step("one", 0.3), Step("two", 0.4), Step("three", 0.5) }
ns.Model.Plan = function()
	local card = { key = "test", kind = "calling", title = "Training", subline = "Training", map = 1413, steps = steps }
	return { journey = "test", chosen = ns.Prefs().journey == "test", steps = steps, journeys = { card } }
end
ns.Model.Refresh = ns.Model.Plan
h.G.ShortestPathForever.API.Estimate = function()
	calls = calls + 1
	return seconds, failure
end
local function Settle()
	for _ = 1, 40 do
		local before = calls
		local ran = h.tick()
		eq(calls - before <= 1, true, "at most one estimate per frame")
		if ran == 0 then
			break
		end
	end
	eq(#h.errors, 0, table.concat(h.errors, "\n"))
end
ns.Session.Set(15)
ns.Choose("test", true)
Settle()
eq(#ns.Route().steps, 3, "initial fit")
eq(ns.Session.Info().seconds, 90, "travel plus ten seconds per interaction")
eq(ns.Prefs().guided, "test", "start waits for estimates")
eq(ns.Integrations.Guiding(), true)
steps = { Step("new", 0.6) }
ns.Invalidate()
Settle()
eq(#ns.Route().steps, 0, "committed endpoint never adds new work")
eq(ns.Route().chosen, true, "raw chosen journey survives empty display")
eq(ns.Integrations.Owns(), false, "empty session cancels old guidance")

-- A provider refusal is unknown even where offline geometry exists.
seconds, failure = nil, "unreachable"
ns.Session.Set(30)
Settle()
eq(#ns.Route().steps, 0, "unreachable does not fall back to geometry")
eq(ns.Session.Info().empty, true)
eq(ns.Session.Info().seconds, nil, "unknown travel is never displayed as zero")

-- In-flight duration changes and route changes discard their stale estimate jobs.
seconds, failure = 10, nil
ns.Session.Set(60)
h.tick()
steps = { Step("replacement", 0.7) }
ns.Session.Set(15)
ns.Invalidate()
Settle()
eq(ns.Prefs().sessionCommit.minutes, 15)
eq(ns.Prefs().sessionCommit.keys.replacement, true)
eq(ns.Prefs().sessionCommit.keys.new, nil)
eq(ns.Session.Info().seconds, 20)

-- Combat holds the shared queue and does not convert a refusal to zero travel.
h.combat = true
local before = calls
ns.Session.Set(30)
h.tick()
h.tick()
h.tick()
eq(calls, before, "combat makes no estimates")
eq(ns.Session.Info().pending, true)
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
Settle()
eq(ns.Session.Info().pending, false)
eq(#ns.Route().steps, 1)

-- Stable custom ordering reaches SPF verbatim and Reset clears the persisted override.
ns.Session.Set(0)
steps = { Step("a", 0.3), Step("b", 0.4), Step("c", 0.5) }
ns.Invalidate()
Settle()
ns.StartRoute()
Settle()
eq(ns.Order.Move(3, 1), true)
Settle()
eq(ns.Route().steps[1].key, "c")
eq(h.spfRoute.stops[1].title, "Train in c")
ns.Invalidate()
Settle()
eq(ns.Route().steps[1].key, "c", "rebuild preserves order")
ns.Order.Reset()
Settle()
eq(ns.Route().steps[1].key, "a")
eq(ns.Order.IsCustom(), false)
print(("session_spec: %d checks passed"):format(checks))
