local harness = dofile("tests/harness.lua")

local function journey(x, reach, blocked)
	local h = harness.load({
		spf = "subscribe",
		player = { level = 18, faction = "Horde", raceID = 2, classID = 64, map = 1413, x = x, y = 0.5 },
	})
	h.flush()
	local route = {
		journey = "arrival",
		chosen = true,
		steps = {
			{ key = "trainer", kind = "trainer", title = "Trainer", map = 1413, x = 0.5, y = 0.5, quests = {} },
		},
	}
	h.ns.Route = function()
		return route
	end
	if reach then
		h.G.ShortestPathForever.API.JourneyState = function()
			return { reach = reach, blocked = blocked }
		end
	end
	return h, route
end

-- The fake provider keeps the route pending until told otherwise. Reaching the destination must close it
-- even if the provider still has no result. An updated stop at that location must not restart the search.
for _, update in ipairs({ false, true }) do
	local h, route = journey(0.4, 15)
	local searches = h.spf.NavigateRoute
	assert(h.ns.StartRoute(), "guidance starts from outside the destination")
	h.flush()
	assert(h.spf.NavigateRoute == searches + 1 and h.spfRoute, "one pending search")
	h.player.x = 0.5
	if update then
		local updated = {}
		for key, value in pairs(route.steps[1]) do
			updated[key] = value
		end
		updated.title = "Updated trainer"
		route.steps[1] = updated
	end
	for _ = 1, 3 do
		h.spfNotify({ changed = true })
		h.flush()
	end
	assert(h.spf.NavigateRoute == searches + 1, "reaching the destination must not restart the pending search")
	assert(not h.spfRoute and h.ns.Guidance.Status() == "arrived", "the pending search closes as arrived")
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

do
	local h = journey(0.5, 15)
	local searches = h.spf.NavigateRoute
	assert(h.ns.StartRoute(), "starting at the destination succeeds")
	h.flush()
	assert(h.spf.NavigateRoute == searches, "starting at the destination needs no search")
	assert(h.ns.Guidance.Status() == "arrived", "already arrived")
end

do
	local h = journey(0.501, 15)
	local searches = h.spf.NavigateRoute
	assert(h.ns.StartRoute(), "starting within the configured reach succeeds")
	h.flush()
	assert(h.spf.NavigateRoute == searches, "starting within reach needs no search")
	assert(h.ns.Guidance.Status() == "arrived", "within reach counts as arrived")
end

do
	local h = journey(0.5)
	local searches = h.spf.NavigateRoute
	assert(h.ns.StartRoute(), "starting at the destination with an older provider succeeds")
	h.flush()
	assert(h.spf.NavigateRoute == searches + 1, "without JourneyState the provider receives the route once")
end

local exclusions = {
	{ label = "held quest turn-in", stop = { kind = "turnin", quests = { 844 }, handins = { 844 } } },
	{ label = "floor-aware stop", stop = { z = 12 } },
	{ label = "instance entrance", stop = { kind = "area", entrance = 389 } },
	{ label = "dungeon stop", stop = { kind = "dungeon" } },
	{ label = "player on a taxi", onTaxi = true },
	{ label = "provider blocked by combat", blocked = "combat" },
}
for _, case in ipairs(exclusions) do
	local h, route = journey(0.5, 15, case.blocked)
	for key, value in pairs(case.stop or {}) do
		route.steps[1][key] = value
	end
	h.onTaxi = case.onTaxi
	local searches = h.spf.NavigateRoute
	assert(h.ns.StartRoute(), case.label .. ": starting within reach succeeds")
	h.flush()
	assert(h.spf.NavigateRoute == searches + 1 and h.spfRoute, case.label .. ": provider receives the route once")
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("guidance_arrival_spec: arrival closes eligible stops and hands excluded stops to Shortest Path")
