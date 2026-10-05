local harness = dofile("tests/harness.lua")

local function atObjectives()
	local h = harness.load({
		spf = "ended",
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
	})
	h.ns.StartRoute()
	h.flush()
	h.log[3] = { id = 887, title = "Southsea Freebooters", level = 14, complete = false }
	h.log[4] = { id = 895, title = "WANTED: Baron Longshore", level = 16, complete = false }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	h.MovePlayer(1413, 0.64, 0.46)
	h.ns.Invalidate()
	h.flush()
	assert(h.ns.Guidance.CurrentStep().key == "area:887:0", "active guidance targets the objective area")
	assert(h.spfRoute.stops[1].hold == true, "objective interaction holds its destination")
	assert(h.spfRoute.stops[1].radius >= 30, "objective arrival carries its area radius to SPF")
	local shapes = h.spfRoute.stops[1].shapes
	assert(type(shapes) == "table" and #shapes > 0, "objective arrival carries its areas to SPF")
	for _, shape in ipairs(shapes) do
		assert(
			shape.map and shape.x and shape.y and shape.radius and shape.radius >= 0,
			"each area reaches SPF as a map, a point and a yard radius"
		)
	end
	-- Every quest of the area reaches Shortest Path; one alone is also named the way older versions read it.
	local areaStep = h.ns.Guidance.CurrentStep()
	local quests, stop = areaStep.quests or {}, h.spfRoute.stops[1]
	assert((#quests == 1) == (stop.questID ~= nil), "an area names its quest alone only when it is the only one")
	assert(#quests == #(stop.questIDs or {}), "an area names every quest it covers")
	for index, questID in ipairs(quests) do
		assert(stop.questIDs[index] == questID, "the area's quests reach Shortest Path in order")
	end
	assert(stop.questIDs ~= areaStep.quests, "Shortest Path gets its own copy of the quest list")
	return h
end

do
	local h = atObjectives()
	h.log[3].objectives = {
		{ type = "monster", have = 1, need = 6, text = "Freebooter slain: 1/6" },
		{ type = "monster", have = 0, need = 8, text = "Cannoneer slain: 0/8" },
	}
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local before = h.spf.NavigateRoute
	h.log[3].objectives[1].have = 5
	h.log[3].objectives[1].text = "Freebooter slain: 5/6"
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	assert(h.ns.Guidance.CurrentStep().title:find("5/6", 1, true), "the guide reads current objective progress")
	assert(h.spfRoute.stops[1].title == h.ns.Route().steps[1].title, "Shortest Path receives current progress")
	assert(h.spf.NavigateRoute == before + 1, "progress refreshes held guidance once")
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	assert(h.spf.NavigateRoute == before + 1, "unchanged progress does not resend the journey")
end

for _, action in ipairs({ "complete", "abandon" }) do
	local h = atObjectives()
	local before = h.spf.NavigateRoute
	if action == "complete" then
		h.log[3].complete, h.log[4].complete = true, true
	else
		table.remove(h.log, 4)
		table.remove(h.log, 3)
	end
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	assert(h.spf.NavigateRoute == before + 1, action .. ": replaces the held route once")
	assert(h.ns.Guidance.CurrentStep().key ~= "area:887:0", action .. ": no longer directs back to cleared work")
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

local h = atObjectives()
for _, kind in ipairs({ "trainer", "battlemaster", "explore" }) do
	local step = { kind = kind, title = kind, map = 1413, x = 0.5, y = 0.5, quests = {}, handins = {} }
	assert(h.ns.Integrations.Hand({ step }, true), "can navigate to " .. kind)
	assert(h.spfRoute.stops[1].hold == false, kind .. ": proximity can finish a non-quest stop")
end
assert(#h.errors == 0, table.concat(h.errors, "\n"))
-- Standalone map/dungeon buttons have no chosen-journey progress owner.
for _, kind in ipairs({ "giver", "town" }) do
	local single = harness.load({ spf = "ended" })
	local stop = {
		kind = kind,
		key = "standalone",
		title = "Quest giver",
		map = 1413,
		x = 0.5,
		y = 0.5,
		quests = { 844 },
		handins = {},
	}
	assert(single.ns.Guidance.Navigate(stop), "standalone navigation starts")
	assert(single.spfRoute.stops[1].hold == false, "standalone navigation must still finish on arrival")
	assert(single.ns.Prefs().guided == nil, "standalone destination is not owned by a chosen journey")
end
print("held_guidance_spec: completed/abandoned objectives replace held guidance; non-quest stops remain transient")
