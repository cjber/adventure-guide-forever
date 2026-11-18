-- Run from the repository root: luajit tests/guidance_quiet_spec.lua
-- #836: Shortest Path's callback and the client's super-tracking events fire on most quest events. When neither changed
-- what guidance shows (the current step, the stops handed, Status, Owns), Guidance tells no one, so the tracker does
-- not rebuild its blocks. A real change still reaches every listener.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function Load(spf)
	local h = harness.load({
		spf = spf,
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		},
	})
	h.flush()
	return h
end

local function Counting(h)
	local told, dirty = 0, 0
	h.ns.Guidance.OnChange(function()
		told = told + 1
	end)
	local mark = h.tracker.MarkDirty
	h.tracker.MarkDirty = function(self)
		dirty = dirty + 1
		return mark(self)
	end
	return function()
		return told, dirty
	end
end

-- Shortest Path with Subscribe: its callback with nothing changed for us.
do
	local h = Load("subscribe")
	h.ns.StartRoute()
	h.flush()
	equal(h.ns.Guidance.Owns(), true, "spf: our route runs")
	local counts = Counting(h)
	for _ = 1, 20 do
		h.spfNotify({ changed = true })
		h.flush()
	end
	local told, dirty = counts()
	equal(told, 0, "spf: 20 callbacks with nothing changed tell no listener")
	equal(dirty, 0, "spf: and the tracker does not rebuild")
	-- Shortest Path ends the journey: that is a change, and every listener hears it.
	h.spfEnd("cleared")
	h.flush()
	told, dirty = counts()
	equal(h.ns.Prefs().guided, nil, "spf: the cleared journey is forgotten")
	equal(told > 0, true, "spf: the journey ending reaches the listeners")
	equal(dirty > 0, true, "spf: and the tracker redraws")
	equal(#h.errors, 0, "spf: errors\n" .. table.concat(h.errors, "\n"))
end

-- An older Shortest Path: the super-tracking event the client fires as quests are watched.
do
	local h = Load("ended")
	h.ns.StartRoute()
	h.flush()
	-- The first look tells the listeners the route is now ours (StartRoute saves that after Go's own notice).
	h.fire("SUPER_TRACKING_CHANGED")
	h.flush()
	local counts = Counting(h)
	for _ = 1, 20 do
		h.fire("SUPER_TRACKING_CHANGED")
		h.flush()
	end
	local told, dirty = counts()
	equal(told, 0, "old spf: 20 super-tracking events with nothing changed tell no listener")
	equal(dirty, 0, "old spf: and the tracker does not rebuild")
	h.spfEnd("cleared")
	h.fire("SUPER_TRACKING_CHANGED")
	h.flush()
	told = counts()
	equal(told > 0, true, "old spf: the journey ending reaches the listeners")
	equal(#h.errors, 0, "old spf: errors\n" .. table.concat(h.errors, "\n"))
end

print(("guidance_quiet_spec: %d checks passed"):format(checks))
