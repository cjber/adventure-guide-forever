-- Run from the repository root: luajit tests/autostart_spec.lua
-- autoStart (default on): on login/reload the guide sends the chosen journey's route to Shortest Path without a click,
-- so the map line is drawn. Never for a wanderer, never when it is off, and a route the player started comes back.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local LOG = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } }

-- Default: the offered journey is started on load, with no click.
local h = harness.load({ spf = "v1", completed = { 844 }, log = LOG })
h.flush()
equal(h.spf.NavigateRoute >= 1, true, "auto-start sends the route on load")
equal(type(h.ns.Prefs().guided), "string", "auto-start records the guided journey")
equal(#h.errors, 0, table.concat(h.errors, "\n"))

-- autoStart off: nothing is sent and no journey is recorded.
local off = harness.load({ spf = "v1", db = { autoStart = false }, completed = { 844 }, log = LOG })
off.flush()
equal(off.spf.NavigateRoute or 0, 0, "autoStart off sends nothing")
equal(off.ns.Prefs().guided, nil, "autoStart off records no journey")

-- A wanderer sets off on foot: nothing is sent.
local wander = harness.load({ spf = "v1", db = { wanderer = true }, completed = { 844 }, log = LOG })
wander.flush()
equal(wander.spf.NavigateRoute or 0, 0, "a wanderer is never auto-started")
equal(wander.ns.Prefs().guided, nil, "a wanderer records no journey")

-- The route the player started comes back on the next load (the persist -> restore round trip).
local before = harness.load({ spf = "v1", completed = { 844 }, log = LOG })
before.flush()
local journey = before.ns.Prefs().journey
local again = harness.load({
	spf = "v1",
	completed = { 844 },
	log = LOG,
	charDB = { journey = journey, guided = journey },
})
again.flush()
equal(again.spf.NavigateRoute >= 1, true, "a started route is restored on the next load")
equal(again.ns.Prefs().guided, journey, "the restored journey is the one that was started")

print(("autostart_spec: %d checks passed"):format(checks))
