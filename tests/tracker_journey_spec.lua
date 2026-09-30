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

-- The tracker's journey line names the story above the step, and a click on it routes from the story's start.
do
	local h = Barrens({ spf = "v1", db = { autoStart = false } })
	local ns, route = h.ns, h.ns.Route()
	local journey = Shown(ns)
	check(journey ~= nil and journey.title == "The Barrens story", "the Barrens story is the chosen journey")
	local block = h.tracker.liveBlocks.journey
	check(block ~= nil, "the tracker has a journey line")
	check(block.header == journey.title, "it names the journey, not just the step")
	check(block.header ~= route.steps[1].title, "the title is not the step's")
	check(h.tracker.layoutOrder[1] == "journey", "the journey line sits above the step")
	-- Its click is the way back to the story's start.
	h.tracker:OnBlockHeaderClick(block, "LeftButton")
	h.flush()
	check(h.spf.NavigateRoute == 1, "clicking it starts the journey's route")
	check(h.spfRoute.stops[1].title == route.steps[1].title, "from the story's first step")
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
	check(h.tracker.liveBlocks.journey.header == "The Barrens story", "the tracker names the story then")
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
	h.G.OpenQuestLog()
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
	check(h.spfRoute.stops[1].title == second.title, "from the clicked step")
	h.call(pin.OnClick, pin, "RightButton")
	h.flush()
	check(h.spfRoute.stops[1].title == first.title, "right-click is back at the story's start")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("tracker_journey_spec: " .. checks .. " checks passed")
