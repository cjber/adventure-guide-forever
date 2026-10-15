-- Run from the repository root: luajit tests/subscribe_spec.lua
-- Subscriptions both ways (docs/api.md, cjber/adventure-guide-forever#159): AGF follows a Shortest Path with
-- Subscribe (minor 1) through its callback instead of the super-tracking events, and keeps the events for an older one;
-- AGF's own API.Subscribe calls back the frame after the current stop or the journey changes, once per burst, each
-- subscriber with its own table and its errors kept apart.
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
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
	})
	h.flush()
	return h
end

-- Shortest Path with Subscribe: subscribed once at login; its callback, not the super-tracking event, notices our
-- journey ending.
do
	local h = Load("subscribe")
	equal(h.spf.Subscribe, 1, "spf: subscribed once")
	h.ns.StartRoute()
	h.flush()
	equal(h.ns.Guidance.Owns(), true, "spf: our route runs")
	local watching = false
	for _, frame in ipairs(h.frames) do
		watching = watching
			or (frame.events and frame.events.SUPER_TRACKING_CHANGED and frame.events.USER_WAYPOINT_UPDATED)
			or false
	end
	equal(watching, false, "spf: the super-tracking event is no longer watched")
	-- Shortest Path ends the journey and calls back on the next frame (the harness profile does, as SPF does).
	h.spfEnd("cleared")
	h.flush()
	equal(h.ns.Prefs().guided, nil, "spf: its callback forgets the cleared journey")
	equal(#h.errors, 0, "spf: errors\n" .. table.concat(h.errors, "\n"))
	-- An error in AGF's handling is caught for the report, under its own label, and still reaches the error handler.
	local follow = h.ns.Route
	h.ns.Route = function()
		error("route broke", 0)
	end
	h.spfNotify({ changed = true })
	h.ns.Route = follow
	local caught = h.ns.CaughtErrors()
	equal(caught[#caught].label, "spf subscriber", "spf: a failing look is caught for the report")
	equal(#h.errors, 1, "spf: and passed to the error handler")
end

-- An older Shortest Path (no Subscribe): the super-tracking event still notices.
do
	local h = Load("ended")
	equal(h.spf.Subscribe, nil, "old spf: nothing to subscribe to")
	h.ns.StartRoute()
	h.flush()
	h.spfEnd("cleared")
	h.fire("SUPER_TRACKING_CHANGED")
	h.flush()
	equal(h.ns.Prefs().guided, nil, "old spf: the event still forgets the cleared journey")
end

-- AGF's own Subscribe.
do
	local h = Load("subscribe")
	local API = h.G.AdventureGuideForever.API
	equal(API.version, 1, "api: still version 1")
	equal(API.minor, 1, "api: minor 1")
	local ok = pcall(API.Subscribe, "not a function")
	equal(ok, false, "api: a non-function callback is an error")
	local calls, seen, failing = 0, {}, 0
	local unsubscribe = API.Subscribe(function(changes)
		calls = calls + 1
		seen[#seen + 1] = changes
	end)
	API.Subscribe(function()
		failing = failing + 1
		error("subscriber broke", 0)
	end)
	local others = 0
	API.Subscribe(function()
		others = others + 1
	end)
	-- Nothing changed yet: a burst that moves nothing calls nobody.
	h.ns.Invalidate()
	h.flush()
	equal(calls, 0, "api: no call when nothing changed since subscribing")
	local base = calls
	-- Choosing another journey changes the stop and the journey: one call, both set, a fresh table each time.
	local other
	for _, journey in ipairs(h.ns.Route().journeys) do
		if journey.key ~= h.ns.Route().journey then
			other = other or journey.key
		end
	end
	h.ns.Choose(assert(other, "another journey"))
	h.ns.Invalidate()
	h.ns.Invalidate()
	h.flush()
	equal(calls, base + 1, "api: one call for the burst")
	local changes = seen[#seen]
	equal(changes.journey, true, "api: the journey changed")
	equal(changes.stop, true, "api: and the stop")
	equal(failing > 0 and others > 0, true, "api: a failing subscriber doesn't stop the next")
	local caught = h.ns.CaughtErrors()
	equal(caught[#caught].label, "API subscriber", "api: its error is caught for the report")
	equal(#h.errors > 0, true, "api: and passed to the error handler")
	-- A rebuild that leaves the stop and journey alone calls nobody.
	h.ns.Invalidate()
	h.flush()
	equal(calls, base + 1, "api: nothing changed, no call")
	-- Unsubscribed: no more calls, and unsubscribing again is safe.
	unsubscribe()
	unsubscribe()
	h.ns.Choose(nil)
	h.flush()
	equal(calls, base + 1, "api: unsubscribed")
	-- A subscriber added by a callback waits for the next burst; one unsubscribed by a callback is not called.
	local late, dropped, joined = 0, 0, false
	local unsubscribeDropped
	API.Subscribe(function()
		if not joined then
			joined = true
			API.Subscribe(function()
				late = late + 1
			end)
			unsubscribeDropped()
		end
	end)
	unsubscribeDropped = API.Subscribe(function()
		dropped = dropped + 1
	end)
	h.ns.Choose(other)
	h.flush()
	equal(late, 0, "api: added during a call-back, not called in it")
	equal(dropped, 0, "api: unsubscribed during a call-back, not called")
	h.ns.Choose(nil)
	h.flush()
	equal(late, 1, "api: called on the next burst")
end

print(("subscribe_spec: %d checks passed"):format(checks))
