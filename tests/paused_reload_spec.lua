-- Run from the repository root: luajit tests/paused_reload_spec.lua
-- #878: a route that stopped without the player's Stop (another Shortest Path journey replaced it, it was cleared in
-- Shortest Path, or the API paused it) stays paused across a /reload. The login no longer starts it again over the
-- journey the player chose in Shortest Path; its card and the tracker title still resume it.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local LOG = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } }

local function Login(charDB)
	local h = harness.load({ spf = "ended", completed = { 844 }, log = LOG, charDB = charDB })
	h.flush()
	return h
end

local all = {}
local function Case(label, stop)
	local first = Login()
	all[#all + 1] = first
	equal(first.spf.NavigateRoute, 1, label .. ": the offered journey starts on login")
	local key = first.ns.Prefs().journey
	stop(first)
	first.fire("SUPER_TRACKING_CHANGED")
	first.flush()
	equal(first.ns.Prefs().paused, key, label .. ": the paused journey is kept on the character")
	equal(first.ns.Guidance.Status(), "paused", label .. ": and reads as paused")

	local reload = Login(first.G.AdventureGuideForeverCharDB)
	all[#all + 1] = reload
	equal(reload.spf.NavigateRoute, 0, label .. ": no route starts after a reload")
	equal(reload.ns.Prefs().journey, key, label .. ": the choice is kept")
	equal(reload.ns.Guidance.Status(), "paused", label .. ": and still reads as paused")

	-- Resuming it (the card, the tracker title or Go) hands it again and forgets the pause.
	reload.ns.StartRoute()
	reload.flush()
	equal(reload.spf.NavigateRoute, 1, label .. ": resuming hands it again")
	equal(reload.ns.Prefs().paused, nil, label .. ": and forgets the pause")
end

Case("replaced", function(h)
	h.spfOther()
end)
Case("cleared", function(h)
	h.spfEnd("cleared")
end)
Case("API pause", function(h)
	h.ns.Guidance.Pause()
end)

-- Choosing another journey forgets the pause, so the first comes back as offered, not paused, after a /reload.
do
	local h = Login()
	all[#all + 1] = h
	local key = h.ns.Prefs().journey
	h.ns.Guidance.Pause()
	h.flush()
	equal(h.ns.Prefs().paused, key, "switch: paused")
	h.ns.Choose("not-" .. tostring(key))
	equal(h.ns.Prefs().paused, nil, "switch: choosing another journey forgets the pause")
	h.ns.Choose(key)
	equal(h.ns.Prefs().paused, nil, "switch: choosing the first again does not bring it back")
end

for _, h in ipairs(all) do
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end
print(("paused_reload_spec: %d checks passed"):format(checks))
