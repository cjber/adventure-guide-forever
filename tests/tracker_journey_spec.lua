-- The tracker names the journey it follows (docs/design.md §2.5), holds instead of flipping while QuestieDB's
-- catalogue builds (§2.14), and every numbered map pin offers a way back to the story's start.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function Barrens(extra)
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	extra = extra or {}
	extra.charDB = extra.charDB or { journey = "zone:1413" }
	extra.completed = { 844 }
	extra.log = log
	return harness.load(extra)
end

-- The journey the route shows, by the same lookup the tracker uses.
local function Shown(ns)
	local route = ns.Route()
	for _, journey in ipairs(route.journeys) do
		if journey.key == route.journey then
			return journey
		end
	end
end

-- One section heading names the chosen story; the action retains its route interaction.
do
	local h = Barrens({ spf = "v1", db = { autoStart = false } })
	local ns, route = h.ns, h.ns.Route()
	local journey = Shown(ns)
	check(journey ~= nil and journey.title == "The Barrens story", "the chosen story")
	check(h.tracker.Header.Text:GetText() == journey.title, "one section heading names the story")
	check(h.tracker.liveBlocks.journey == nil, "no duplicate story block")
	check(h.tracker.layoutOrder[1] == route.steps[1].key, "current action follows the section heading")
	local block = h.tracker.liveBlocks[route.steps[1].key]
	check(block.header:find("|A:QuestNormal:", 1, true) ~= nil, "current town action uses its pickup icon")
	check(block.header:find(route.steps[1].title, 1, true) ~= nil, "current action remains readable")
	local count = 0
	for _, key in ipairs(block.order) do
		if block.dashes[key] == h.G.OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE then
			count = count + 1
			local upcoming = route.steps[1 + count]
			check(block.lines[key]:find(upcoming.title, 1, true) ~= nil, "preview follows route order")
			check(block.lines[key]:find("|cff7f7f7f", 1, true) ~= nil, "preview is muted")
		end
	end
	check(count == 2, "only two upcoming actions")
	h.tracker:OnBlockHeaderClick(block, "LeftButton")
	h.flush()
	check(h.spf.NavigateRoute == 1, "current action starts the journey")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
	local current = ns.Guidance.CurrentStep
	ns.Guidance.CurrentStep = function()
		return route.steps[#route.steps]
	end
	h.tracker:MarkDirty()
	local last = h.tracker.liveBlocks[route.steps[#route.steps].key]
	local previews = 0
	for _, key in ipairs(last.order) do
		if last.dashes[key] == h.G.OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE then
			previews = previews + 1
		end
	end
	check(previews == 0, "last current stop has no earlier or invented upcoming actions")
	ns.Guidance.CurrentStep = current
	local previousTitle = route.steps[1].title
	ns.Skip(route.steps[1].key, previousTitle)
	h.flush()
	check(h.tracker.Header.Text:GetText() == journey.title, "advancing retains the story heading")
	local nextAction = h.tracker.liveBlocks[ns.Guidance.CurrentStep().key]
	check(nextAction.header:find(previousTitle, 1, true) == nil, "advancing replaces the current action")
	local unchosen = Barrens({ charDB = {}, db = { autoStart = false } })
	check(unchosen.tracker.Header.Text:GetText() == unchosen.ns.L.TITLE, "no chosen journey uses generic heading")
end

-- A guided hand-in already says what to do, without a second ready-to-hand-in line.
do
	local h = harness.load({
		questiedb = false,
		spf = "v1",
		charDB = { journey = "carry" },
		log = { { id = 845, title = "The Zhevra", complete = true, map = 1413, x = 0.52, y = 0.31 } },
	})
	local step = h.ns.Guidance.CurrentStep()
	check(step ~= nil and step.reason == h.ns.L.READY_TO_HAND_IN, "fixture has a ready hand-in")
	check(h.ns.Integrations.Guiding(), "the hand-in is guided")
	local block = h.tracker.liveBlocks[step.key]
	for _, key in ipairs(block.order) do
		check(block.lines[key] ~= h.ns.L.READY_TO_HAND_IN, "hand-in status is not repeated")
	end
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A slow QuestieDB build: the guide holds an empty route and the auto-start, shows a quiet loading line, then
-- commits the chosen journey once when the records land, never a log-only route that flips underneath the player.
do
	local h = Barrens({
		spf = "v1",
		setup = function(h2)
			h2.ns.QuestieStatus.state = "building"
			h2.ns.Data.quests = {}
		end,
	})
	local ns = h.ns
	check(ns.QuestieStatus.state == "building", "the catalogue is still building")
	check(ns.QuestieBuilding(), "the guide knows it")
	check(#ns.Route().steps == 0 and ns.Route().journey == nil, "no log-only route is built while it builds")
	check(h.spf.NavigateRoute == 0, "and the auto-start waits with it")
	check(h.tracker.liveBlocks.loading ~= nil, "the tracker shows a loading line")
	check(h.tracker.liveBlocks.loading.header == ns.L.TRACKER_LOADING, "in the game's words")
	check(h.tracker.liveBlocks.journey == nil, "and names no journey it hasn't got")

	h.ns.Data.quests = harness.fixtureQuests()
	h.ns.QuestieStatus.state = "questie"
	h.ns.Invalidate()
	h.flush()
	check(ns.Route().journey == "zone:1413", "the chosen journey appears once, when the records land")
	check(ns.Route().chosen, "chosen as before")
	check(h.spf.NavigateRoute == 1, "and the held auto-start begins")
	check(h.tracker.liveBlocks.loading == nil or not h.tracker.liveBlocks.loading.used, "the loading line goes")
	check(h.tracker.Header.Text:GetText() == "The Barrens story", "the tracker names the story then")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- Questie genuinely absent: the source says so, and the guide still routes from the quest log (design §2.14).
do
	local h = Barrens({ questiedb = false, spf = "v1" })
	local ns = h.ns
	check(ns.QuestieStatus.state == "unavailable", "an absent QuestieDB is unavailable, not building")
	check(not ns.QuestieBuilding(), "and is never waited for")
	check(next(ns.Data.quests) == nil, "the bundled data carries no quest records")
	check(ns.Route().journey == "zone:1413", "the log's route still names its journey")
	check(#ns.Route().steps > 0, "with the log's steps")
	check(h.spf.NavigateRoute == 1, "and the auto-start still begins")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A numbered pin past the first: left-click routes from that step, right-click returns to the story's start, and the
-- tooltip says so only on a step past the first.
do
	local h =
		Barrens({ planned = true, spf = "v1", db = { showMapPins = true, showQuestGivers = true, autoStart = false } })
	local ns = h.ns
	h.G.C_Map.OpenWorldMap()
	h.flush()
	h.providers[1]:RefreshAllData()
	local route = ns.Route()
	local first, second = route.steps[1], route.steps[2]
	check(second ~= nil, "the route has a second step")
	local pin, firstPin
	for _, candidate in ipairs(h.pins.AdventureGuideForeverPinTemplate or {}) do
		pin = candidate.step == second and candidate or pin
		firstPin = candidate.step == first and candidate or firstPin
	end
	check(pin ~= nil and firstPin ~= nil, "both steps have numbered pins")

	h.Hover(pin)
	check(table.concat(h.tooltip, "\n"):find(ns.L.PIN_RETURN_STORY, 1, true) ~= nil, "the later pin says how to return")
	h.Hover(firstPin)
	check(table.concat(h.tooltip, "\n"):find(ns.L.PIN_RETURN_STORY, 1, true) == nil, "the first needs no return")

	h.call(pin.OnClick, pin, "LeftButton")
	h.flush()
	check(h.spf.NavigateRoute == 1, "clicking the pin routes")
	check(
		h.spfRoute.stops[1].title == (second.kind == "town" and second.place or second.title),
		"from the clicked step"
	)
	h.call(pin.OnClick, pin, "RightButton")
	h.flush()
	check(
		h.spfRoute.stops[1].title == (first.kind == "town" and first.place or first.title),
		"right-click is back at the story's start"
	)
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("tracker_journey_spec: " .. checks .. " checks passed")
