-- Run from the repository root: luajit tests/information_mode_spec.lua
-- Information-only mode: no AGF-owned route is chosen, started, followed or restored, no AGF control sets a waypoint,
-- clicking a stop reveals Questie's own icons (or AGF's pin) instead, the player's watch list is untouched, and the
-- RestedXP guide keeps its own frontend. The normal planner returns when the setting is off.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	{ id = 850, title = "Kolkar Leaders", level = 15, complete = false },
	{ id = 855, title = "Centaur Bracers", level = 15, complete = false },
}

local function Load(options)
	options = options or {}
	options.spf = options.spf or "v1"
	options.completed = options.completed or { 844 }
	options.log = options.log or LOG
	options.db = options.db or {}
	return harness.load(options)
end

-- A chosen Barrens journey with map pins, as the click tests need.
local function Barrens(extra)
	extra = extra or {}
	extra.planned = true
	extra.spf = extra.spf or "v1"
	extra.db = extra.db or {}
	extra.db.autoStart = false
	extra.charDB = extra.charDB or { journey = "zone:1413" }
	extra.completed = { 844 }
	extra.log = LOG
	return harness.load(extra)
end

local function PinWithQuest(h)
	for _, pin in ipairs(h.Pins("AdventureGuideForeverPinTemplate") or {}) do
		local quests = h.ns.LogQuests(pin.step)
		if #quests > 0 then
			return pin, quests[1]
		end
	end
end

local function ClickLine(ns)
	return ns.L.CLICK_SHOW_MAP or "Click to show this stop on the map"
end

-- No automatic start on login and no saved route restored, even when one was guided before the mode was turned on.
do
	local h = Load({ db = { informationOnly = true } })
	h.flush()
	equal(h.spf.NavigateRoute or 0, 0, "information mode starts nothing on load")
	equal(h.ns.Prefs().guided, nil, "information mode records no guided journey")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))

	local saved = Load({
		db = { informationOnly = true },
		charDB = { journey = "zone:1413", guided = "zone:1413" },
	})
	saved.flush()
	equal(saved.spf.NavigateRoute or 0, 0, "a saved guided route is not restored")
	equal(saved.ns.Prefs().guided, nil, "and the saved guidance is cleared")
	equal(#saved.errors, 0, table.concat(saved.errors, "\n"))

	-- The waypoint AGF saved before the mode is cleared only while the client still has AGF's own point.
	local ownedPoint = { uiMapID = 1413, position = { x = 0.5, y = 0.3 } }
	local owned = Load({
		db = { informationOnly = true },
		charDB = { waypoint = { map = 1413, x = 0.5, y = 0.3 } },
		waypoint = ownedPoint,
	})
	owned.flush()
	equal(owned.counts.ClearUserWaypoint, 1, "AGF's saved waypoint is cleared")
	equal(owned.waypoint, nil, "the client waypoint is gone")
	equal(owned.ns.Prefs().waypoint, nil, "and the saved point is forgotten")
	equal(owned.spf.NavigateRoute or 0, 0, "no route starts over it")
	equal(#owned.errors, 0, table.concat(owned.errors, "\n"))

	local foreignPoint = { uiMapID = 1413, position = { x = 0.9, y = 0.9 } }
	local foreign = Load({
		db = { informationOnly = true },
		charDB = { waypoint = { map = 1413, x = 0.5, y = 0.3 } },
		waypoint = foreignPoint,
	})
	foreign.flush()
	equal(foreign.counts.ClearUserWaypoint, 0, "someone else's waypoint is not cleared")
	equal(foreign.waypoint, foreignPoint, "the client waypoint is unchanged")
	equal(foreign.ns.Prefs().waypoint, nil, "AGF forgets the stale saved point")
	equal(#foreign.errors, 0, table.concat(foreign.errors, "\n"))
end

-- StartRoute, StartJourney, Navigate and the explicit Show-on-Map control all refuse, before any choice is written.
do
	local h = Load({ db = { informationOnly = true, autoStart = false } })
	h.flush()
	local step = h.ns.Route().steps[1]
	check(step ~= nil, "the offered route has a step")
	equal(h.ns.Prefs().journey, nil, "no journey is chosen before the click")
	equal(h.ns.StartRoute(), false, "StartRoute refuses")
	equal(h.ns.Prefs().journey, nil, "and does not choose the route's own journey")
	equal(h.ns.StartJourney(h.ns.Route().journey), false, "StartJourney refuses")
	equal(h.spf.NavigateRoute or 0, 0, "nothing reached Shortest Path")
	local place = { map = step.map, x = step.x, y = step.y, title = step.title, quests = {}, adds = {} }
	equal(h.ns.Guidance.Navigate(place), false, "Navigate refuses")
	equal(h.counts.SetUserWaypoint, 0, "no waypoint is set")
	equal(h.ns.Guidance.ShowOnMap(place), false, "Show on Map routes nowhere")
	equal(h.counts.SetUserWaypoint, 0, "and still sets no waypoint")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- A panel card click still chooses the journey for browsing; only the start it asks for is refused.
do
	local h = Load({ db = { informationOnly = true, autoStart = false } })
	h.flush()
	local key = h.ns.Route().journey
	check(key ~= nil, "a journey is offered")
	equal(
		h.G.AdventureGuideForever.API.StartSuggestion(key),
		false,
		"the public card API starts nothing in information mode"
	)
	h.ns.Choose(key, true)
	h.flush()
	equal(h.ns.Prefs().journey, key, "the card chooses its journey")
	equal(h.ns.Prefs().guided, nil, "but no route is recorded")
	equal(h.spf.NavigateRoute or 0, 0, "and nothing starts")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- The giver pin, an aside's Go and a battleground's Go set no waypoint in the mode; the giver click reveals instead.
do
	local h = Barrens({
		db = { showMapPins = true, showQuestGivers = true, informationOnly = true },
	})
	h.G.C_Map.OpenWorldMap()
	h.flush()
	h.ns.Pins.Refresh()
	local pins = h.Pins("AdventureGuideForeverGiverPinTemplate") or {}
	local giverPin = pins[1]
	check(giverPin ~= nil, "the map draws a giver pin whose quests the guide offers")
	h.call(giverPin.OnMouseClickAction, giverPin, "LeftButton")
	h.flush()
	equal(h.counts.SetUserWaypoint, 0, "a giver click sets no waypoint")
	equal(h.spf.NavigateRoute or 0, 0, "and starts no route")
	equal(h.ns.Prefs().guided, nil, "and records no guidance")

	local aside = { place = { map = 1413, x = 0.5, y = 0.3, z = 0, name = "Somewhere" } }
	equal(h.ns.Asides.Go(aside), false, "an aside's Go routes nowhere")
	equal(h.counts.SetUserWaypoint, 0, "and sets no waypoint")

	local data = h.ns.PvP.Data
	h.ns.PvP.Data = function()
		return {
			battlegrounds = {
				{ id = 1, name = "Warsong Gulch", npc = 1, place = { map = 1413, x = 0.5, y = 0.3, z = 0 } },
			},
		}
	end
	equal(h.ns.PvP.Go(1), false, "a battlemaster's Go routes nowhere")
	h.ns.PvP.Data = data
	equal(h.counts.SetUserWaypoint, 0, "and sets no waypoint either")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- Clicking a numbered stop in information mode reveals Questie's own icons and never starts a route.
do
	local h = Barrens({ db = { showMapPins = true, showQuestGivers = true, informationOnly = true } })
	h.G.C_Map.OpenWorldMap()
	h.flush()
	h.ns.Pins.Refresh()
	local pin, questID = PinWithQuest(h)
	check(pin ~= nil, "the route has a numbered stop for a quest in the log")
	harness.questie(h, { frames = { [questID] = 1 } })

	h.Hover(pin)
	local text = table.concat(h.tooltip, "\n")
	check(text:find(ClickLine(h.ns), 1, true) ~= nil, "the tooltip says the click shows the stop on the map")
	check(
		text:find(h.ns.L.PIN_RETURN_STORY or "Right-click to route from the story's start", 1, true) == nil,
		"and offers no way back to a route"
	)

	h.call(pin.OnMouseClickAction, pin, "LeftButton")
	h.flush()
	equal(h.spf.NavigateRoute or 0, 0, "the click starts no route")
	equal(h.ns.Prefs().guided, nil, "and records no guided journey")
	equal(#h.questie.calls.finisher, 1, "Questie's own icon flash is used")
	equal(h.questie.calls.finisher[1].Id, questID, "for the stop's logged quest")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- Questie unavailable, its icons hidden, or a flash failing: AGF's own pin reveal is the fallback, with no error.
for _, case in ipairs({
	{ "no Questie icons", { frames = 0 } },
	{ "a flash error", { frames = 1, finisherError = true } },
	{ "no TrackerUtils", { frames = 1, noTracker = true } },
	{ "Questie not ready", { frames = 1, ready = false } },
}) do
	local h = Barrens({ db = { showMapPins = true, informationOnly = true } })
	h.G.C_Map.OpenWorldMap()
	h.flush()
	h.ns.Pins.Refresh()
	local pin, questID = PinWithQuest(h)
	check(pin ~= nil, case[1] .. ": the route has a clickable stop")
	local options = case[2]
	options.frames = { [questID] = options.frames }
	harness.questie(h, options)
	local before = h.counts.secureCalls
	h.call(pin.OnMouseClickAction, pin, "LeftButton")
	h.flush()
	equal(h.spf.NavigateRoute or 0, 0, case[1] .. ": no route")
	check(h.counts.secureCalls > before, case[1] .. ": AGF's pin reveal opens the map")
	equal(#h.errors, 0, case[1] .. ": " .. table.concat(h.errors, "\n"))
end

-- A stop's slots are the data's need slots, not the client's objective indices: a kill is slot 0, its first collect
-- slot 4, and Questie keeps objectives by the client's 1-based log order. The planner's alignment carries that index,
-- so a lone kill flashes Questie's first objective, a kill and a collect flash the first and second, and a stop's
-- quests are flashed together instead of falling back to their finishers.
do
	local h = Barrens({ db = { informationOnly = true } })
	h.G.SlotKill = {
		miniMapIcon = false,
		data = {},
		IsShown = function()
			return true
		end,
	}
	h.G.SlotKillB = {
		miniMapIcon = false,
		data = {},
		IsShown = function()
			return true
		end,
	}
	h.G.SlotItem = {
		miniMapIcon = false,
		data = {},
		IsShown = function()
			return true
		end,
	}
	local questie = harness.questie(h, {
		frames = { [845] = 1, [843] = 1 },
		objectives = {
			[845] = { { AlreadySpawned = { { mapRefs = { h.G.SlotKill } } } } },
			[843] = {
				{ AlreadySpawned = { { mapRefs = { h.G.SlotKillB } } } },
				{ AlreadySpawned = { { mapRefs = { h.G.SlotItem } } } },
			},
		},
	})
	local data = {
		quests = {
			[845] = { need = { [0] = 10 }, kinds = { [0] = "monster" } },
			[843] = { need = { [0] = 8, [4] = 6 }, kinds = { [0] = "monster", [4] = "item" } },
		},
	}
	local log = {
		[845] = {
			id = 845,
			complete = false,
			objectives = {
				{ type = "monster", text = "Zhevra slain: 0/10", done = false, have = 0, need = 10 },
			},
		},
		[843] = {
			id = 843,
			complete = false,
			objectives = {
				{ type = "monster", text = "Kolkar slain: 0/8", done = false, have = 0, need = 8 },
				{ type = "item", text = "Bracers: 0/6", done = false, have = 0, need = 6 },
			},
		},
	}
	local refs = h.ns.Planner.Steps.LiveObjectives(data, log, {
		{ id = 845, slot = 0 },
		{ id = 843, slot = 0 },
		{ id = 843, slot = 4 },
	})
	equal(#refs, 3, "every open objective is carried")
	equal(refs[1].slot, 0, "the lone kill keeps slot 0")
	equal(refs[1].index, 1, "and takes the client's first objective")
	equal(refs[2].slot, 0, "the second quest's kill keeps slot 0")
	equal(refs[2].index, 1, "and takes its own client's first objective")
	equal(refs[3].slot, 4, "the first collect keeps slot 4")
	equal(refs[3].index, 2, "and takes the client's second objective")

	local failed = false
	local step = { map = 1413, x = 0.52, y = 0.31, quests = { 845, 843 } }
	local scheduled = h.ns.QuestieReveal.Show(step, { 845, 843 }, refs, function()
		failed = true
	end)
	equal(scheduled, true, "the reveal schedules")
	h.flush()
	equal(failed, false, "the reveal did not fall back")
	equal(#h.questie.calls.finisher, 0, "no finisher flash stands in")
	equal(#h.questie.calls.objectives, 1, "the stop's objectives are flashed together")
	local flashed = h.questie.calls.objectives[1]
	equal(#flashed, 3, "every open objective reaches Questie")
	equal(flashed[1], questie.questieDB.GetQuest(845).Objectives[1], "slot 0 is Questie's first objective")
	equal(flashed[2], questie.questieDB.GetQuest(843).Objectives[1], "the second quest's kill is its first")
	equal(flashed[3], questie.questieDB.GetQuest(843).Objectives[2], "slot 4 is Questie's second objective")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- The planner's own nodes, which a fresh route and every RestedXP step are built from, carry the client's indices too:
-- slots 0 and 4 on one quest take its first and second objectives, a log that does not line up carries none, and the
-- client's point stands in with them when the data places no slot. No later log refresh is needed for either path.
do
	local id = 999843
	local quest = {
		zone = 1413,
		need = { [0] = 8, [4] = 6 },
		kinds = { [0] = "monster", [4] = "item" },
		obj = { { 0, 515, 305, 40, 1413 }, { 4, 522, 311, 30, 1413 } },
	}
	local objectives = {
		{ type = "monster", text = "Kolkar slain: 0/8", done = false, have = 0, need = 8 },
		{ type = "item", text = "Bracers: 0/6", done = false, have = 0, need = 6 },
	}
	local h = Barrens({ db = { informationOnly = true } })
	h.ns.Data.quests[id] = quest
	h.log[#h.log + 1] = { id = id, title = "Kolkar Bracers", level = 15, complete = false, objectives = objectives }
	local entry = h.ns.State.Log()[id]
	check(entry ~= nil, "the log holds the quest under way")
	local nodes = h.ns.Planner.Steps.Nodes(h.ns.Data, entry, h.player.level)
	equal(#nodes, 2, "the data places both open slots")
	equal(nodes[1].objectives[1].slot, 0, "the first node is the kill, slot 0")
	equal(nodes[1].objectives[1].index, 1, "and carries the client's first objective")
	equal(nodes[2].objectives[1].slot, 4, "the second node is the collect, slot 4")
	equal(nodes[2].objectives[1].index, 2, "and carries the client's second objective")

	local loose = h.ns.Planner.Steps.Nodes(h.ns.Data, {
		id = id,
		complete = false,
		objectives = { objectives[1], objectives[2], objectives[1] },
	}, h.player.level)
	equal(#loose, 2, "a log that does not line up still places both slots")
	equal(loose[1].objectives[1].index, nil, "and carries no client index for slot 0")
	equal(loose[2].objectives[1].index, nil, "nor for slot 4")

	local placed = quest.obj
	quest.obj = {}
	local fallback = h.ns.Planner.Steps.Nodes(h.ns.Data, {
		id = id,
		complete = false,
		poi = { map = 1413, x = 0.5, y = 0.31 },
		objectives = objectives,
	}, h.player.level)
	quest.obj = placed
	equal(#fallback, 1, "the client's point stands in for the open slots")
	equal(#fallback[1].objectives, 2, "with one ref per open slot")
	equal(fallback[1].objectives[1].slot, 0, "the kill keeps slot 0")
	equal(fallback[1].objectives[1].index, 1, "and the client's first objective")
	equal(fallback[1].objectives[2].slot, 4, "the collect keeps slot 4")
	equal(fallback[1].objectives[2].index, 2, "and the client's second")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))

	-- A RestedXP step copies exactly these nodes' objectives, so its refs reach Questie's own per-objective reveal.
	local rxp = harness.load({
		spf = "v1",
		db = { informationOnly = true, autoStart = false },
		completed = { 844 },
		log = LOG,
		setup = function(client)
			client.G.AdventureGuideForeverDB = client.G.AdventureGuideForeverDB or {}
			client.G.AdventureGuideForeverDB.restedxpChoiceMade = true
			client.ns.SetSetting("restedxpGuide", true)
			local frame = client.G.CreateFrame("Frame", nil, client.G.UIParent)
			local current = {
				index = 1,
				active = true,
				title = "Kolkar Bracers",
				elements = {
					{ text = "Kolkar slain: 0/8", questId = id, tag = "complete" },
					{ text = "Bracers: 0/6", textOnly = true },
				},
			}
			local guide = { name = "Example: The Barrens", group = "Example guides", steps = { current } }
			frame.activeSteps = { current }
			local arrow = client.G.CreateFrame("Frame", nil, client.G.UIParent)
			arrow.element = { zone = 1413, x = 51.5, y = 30.5, arrow = true, step = current }
			client.G.RXP = {
				RXPFrame = frame,
				currentGuide = guide,
				arrowFrame = arrow,
				activeWaypoints = { true },
				GetGuideProgress = function()
					return 1
				end,
				SetStep = function() end,
				UpdateMap = function() end,
				UpdateGotoSteps = function() end,
				GetGuideTable = function()
					return guide
				end,
				IsGuideActive = function()
					return true
				end,
				guideList = { Example = { names_ = { { group = guide.group, name = guide.name } } } },
				LoadGuideTable = function() end,
				settings = { profile = { showEnabled = true } },
			}
			client.fire("ADDON_LOADED", "RXPGuides")
			client.flush()
		end,
	})
	rxp.ns.Data.quests[id] = quest
	rxp.log[#rxp.log + 1] = { id = id, title = "Kolkar Bracers", level = 15, complete = false, objectives = objectives }
	local step = assert(rxp.ns.RestedXP.Journey()).steps[1]
	equal(step.map, 1413, "the guide step sits on the quest's map")
	equal(#step.objectives, 2, "both open objectives reach the step")
	equal(step.objectives[1].slot, 0, "the step's kill keeps slot 0")
	equal(step.objectives[1].index, 1, "with the client's first objective")
	equal(step.objectives[2].slot, 4, "and its collect slot 4")
	equal(step.objectives[2].index, 2, "with the client's second")
	equal(#rxp.errors, 0, table.concat(rxp.errors, "\n"))
	rxp.ns.Data.quests[id] = nil
	h.ns.Data.quests[id] = nil
end

-- A stop whose logged quests share objectives flashes them together, through the colon method; no Questie data means
-- the first-quest fallback, never a crash.
do
	local h = Barrens({ db = { informationOnly = true } })
	h.G.MultiA = {
		miniMapIcon = false,
		data = {},
		IsShown = function()
			return true
		end,
	}
	h.G.MultiB = {
		miniMapIcon = false,
		data = {},
		IsShown = function()
			return true
		end,
	}
	harness.questie(h, {
		frames = { [845] = 1, [843] = 1 },
		objectives = {
			[845] = { { AlreadySpawned = { { mapRefs = { h.G.MultiA } } }, spawnList = { { 1, 1 } } } },
			[843] = {
				[2] = { AlreadySpawned = { { mapRefs = { h.G.MultiB } } }, spawnList = { { 2, 2 } } },
			},
		},
	})
	local failed = false
	local step = { map = 1413, x = 0.52, y = 0.31, quests = { 845, 843 } }
	local refs = { { id = 845, slot = 0, index = 1 }, { id = 843, slot = 4, index = 2 } }
	local scheduled = h.ns.QuestieReveal.Show(step, { 845, 843 }, refs, function()
		failed = true
	end)
	equal(scheduled, true, "the reveal schedules once")
	h.flush()
	equal(failed, false, "the reveal did not fall back")
	equal(#h.questie.calls.objectives, 1, "the objectives are flashed together")
	equal(#h.questie.calls.objectives[1], 2, "both logged quests' objectives reached Questie")
	equal(#h.questie.calls.finisher, 0, "and not a single-quest flash")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- One objective's icons hidden, another objective of the same quest visible: only the visible objective is flashed, so
-- Questie never hides every icon to flash nothing.
do
	local h = Barrens({ db = { informationOnly = true } })
	h.G.ObjHidden = {
		miniMapIcon = false,
		data = {},
		IsShown = function()
			return false
		end,
	}
	h.G.ObjVisible = {
		miniMapIcon = false,
		data = {},
		IsShown = function()
			return true
		end,
	}
	local questie = harness.questie(h, {
		frames = { [845] = 1, [843] = 1 },
		objectives = {
			[845] = { { AlreadySpawned = { { mapRefs = { h.G.ObjHidden } } } } },
			[843] = { [2] = { AlreadySpawned = { { mapRefs = { h.G.ObjVisible } } } } },
		},
	})
	local step = { map = 1413, x = 0.52, y = 0.31 }
	local failed = false
	local scheduled = h.ns.QuestieReveal.Show(step, { 845, 843 }, {
		{ id = 845, slot = 0, index = 1 },
		{ id = 843, slot = 4, index = 2 },
	}, function()
		failed = true
	end)
	equal(scheduled, true, "the reveal schedules")
	h.flush()
	equal(failed, false, "and does not fall back")
	equal(#h.questie.calls.objectives, 1, "the objectives are flashed once")
	equal(#h.questie.calls.objectives[1], 1, "only the visible objective reaches Questie")
	equal(
		h.questie.calls.objectives[1][1],
		questie.questieDB.GetQuest(843).Objectives[2],
		"the hidden objective's quest is left out"
	)
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- Malformed Questie data and an IsShown that throws never break the click: the caller's own pin reveal runs instead.
do
	local broken = {
		miniMapIcon = false,
		data = {},
		IsShown = function()
			error("broken Questie frame")
		end,
	}
	local h = Barrens({ db = { informationOnly = true } })
	h.G.BrokenIcon = broken
	harness.questie(h, {
		frames = { [845] = 1 },
		finisherError = true,
		objectives = { [845] = { { AlreadySpawned = "not a table" } } },
	})
	local failed = false
	local step = { map = 1413, x = 0.52, y = 0.31 }
	local scheduled = h.ns.QuestieReveal.Show(step, { 845 }, { { id = 845, slot = 0, index = 1 } }, function()
		failed = true
	end)
	equal(scheduled, true, "the malformed reveal is still attempted")
	h.flush()
	equal(failed, true, "and falls back to AGF's pin")
	equal(#h.errors, 0, "without a Lua error: " .. table.concat(h.errors, "\n"))

	local throws = Barrens({ db = { informationOnly = true } })
	throws.G.BrokenIcon = broken
	harness.questie(throws, { frames = { [845] = { "BrokenIcon" } } })
	local ok = pcall(throws.ns.QuestieReveal.Show, step, { 845 }, nil, nil)
	equal(ok, true, "a failing IsShown is caught")
	equal(#throws.errors, 0, table.concat(throws.errors, "\n"))
end

-- No Questie setting, frame or character table is written, and the calls that would change the player's pin choice
-- are never made.
do
	local h = Barrens({ db = { showMapPins = true, informationOnly = true } })
	h.G.C_Map.OpenWorldMap()
	h.flush()
	h.ns.Pins.Refresh()
	local pin, questID = PinWithQuest(h)
	check(pin ~= nil, "the route has a clickable stop")
	local questie = harness.questie(h, {
		frames = { [questID] = 1 },
		char = { TrackerFocus = 7, TrackerHiddenQuests = { [845] = true } },
	})
	local function Copy(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, inner in pairs(value) do
			copy[key] = Copy(inner)
		end
		return copy
	end
	local before = Copy(questie.db)
	h.call(pin.OnMouseClickAction, pin, "LeftButton")
	h.flush()
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
	local after = Copy(questie.db)
	for key, value in pairs(before) do
		equal(after[key] ~= nil, true, "Questie's " .. key .. " table is kept")
		for inner, setting in pairs(value) do
			if type(setting) ~= "table" then
				equal(after[key][inner], setting, "Questie's " .. key .. "." .. inner .. " is unchanged")
			end
		end
	end
	equal(questie.calls.forbidden.FocusQuest, 0, "no focus is set")
	equal(questie.calls.forbidden.Unfocus, 0, "no focus is cleared")
	equal(questie.calls.forbidden.UnhideQuest, 0, "no quest is unhidden")
	equal(questie.calls.forbidden.HideQuest, 0, "no quest is hidden")
	equal(questie.calls.forbidden.ToggleNotes, 0, "no notes are toggled")
end

-- A chosen journey does not lead the tracker in information mode: the player's watch list is left exactly as it is.
do
	local h = Load({
		planned = true,
		db = { informationOnly = true, autoStart = false },
		charDB = { journey = "zone:1413" },
	})
	h.watched = { 850, 855 }
	h.ns.Choose("zone:1413", false)
	h.flush()
	equal(h.ns.QuestWatch.Source(), nil, "no leader settles the watches")
	equal(#h.watched, 2, "the player's two watches stay")
	equal(h.watched[1], 850, "in order")
	equal(h.watched[2], 855, "and both")
	equal(h.ns.Prefs().guideWatch, nil, "nothing was taken over")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- Switching on cancels only AGF's route and its waiting start; switching off lets autoStart return.
do
	local h = Load()
	h.flush()
	local key = h.ns.Prefs().journey
	check(key ~= nil and h.ns.Prefs().guided == key, "autoStart began the route")
	local started = h.spf.NavigateRoute
	h.ns.SetSetting("informationOnly", true)
	h.flush()
	equal(h.ns.Prefs().guided, nil, "the AGF route is cancelled")
	equal(h.ns.Guidance.Running(key), false, "the card is not running")
	check(h.spf.Cancel >= 1, "Shortest Path's AGF-owned journey is cancelled")
	equal(h.spfRoute, nil, "and no route is left drawn")
	h.ns.SetSetting("informationOnly", false)
	h.flush()
	equal(h.ns.Prefs().guided, key, "autoStart returns with the planner")
	check(h.spf.NavigateRoute > started, "and the route is sent again")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- Tracker's Polestar row takes nothing over in the mode, and the step menu offers Show on Map instead of Go and no
-- Shortest Path companion submenu.
do
	local h = Load({ db = { informationOnly = true, autoStart = false } })
	h.flush()
	local tookOver = 0
	h.ns.Polestar.TakeOver = function()
		tookOver = tookOver + 1
	end
	h.call(h.tracker.OnBlockHeaderClick, h.tracker, { id = "polestar" }, "LeftButton")
	equal(tookOver, 0, "Polestar is not taken over")
	equal(h.spf.NavigateRoute or 0, 0, "and no route starts")

	local labels, added = {}, {}
	local root = {}
	function root:CreateTitle() end
	function root:CreateButton(text)
		labels[#labels + 1] = text
		return self
	end
	function root:SetScrollMode() end
	function root:SetTooltip() end
	local addMenu = h.ns.Companions.AddMenu
	h.ns.Companions.AddMenu = function(_, name)
		added[#added + 1] = name
	end
	h.ns.Menu.Step(root, h.ns.Route().steps[1])
	h.ns.Companions.AddMenu = addMenu
	local has, go = false, false
	for _, label in ipairs(labels) do
		has = has or label == h.ns.L.SHOW_ON_MAP
		go = go or label == h.ns.L.GO
	end
	equal(has, true, "the menu offers Show on Map")
	equal(go, false, "and not Go")
	equal(#added, 0, "no Shortest Path companion submenu")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end

-- A RestedXP guide is still shown for browsing, but AGF restores the frames it hid, applies no automatic skips and
-- leaves the external guide in charge. Switching off restores AGF's frontend and watch ownership.
do
	local group, name = "Example guides", "Example: The Barrens"
	local key = "guide:" .. #group .. ":" .. group .. ":" .. #name .. ":" .. name
	local h = harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = key },
		completed = { 844 },
		log = LOG,
		setup = function(client)
			dofile("tests/rxp_fixture.lua")(client, 0)
		end,
	})
	h.flush()
	local rxp = h.G.RXP
	check(rxp ~= nil, "the RestedXP engine is loaded")
	equal(rxp.RXPFrame:GetAlpha(), 0, "normal mode hides RestedXP's window behind the guide")
	equal(rxp.arrowFrame:GetAlpha(), 0, "and its arrow behind Shortest Path")

	h.ns.SetSetting("informationOnly", true)
	h.flush()
	equal(rxp.RXPFrame:GetAlpha(), 1, "information mode gives RestedXP's window back")
	equal(rxp.arrowFrame:GetAlpha(), 1, "and its arrow")
	equal(
		h.G.AdventureGuideForever.API.RestedXPIntegrated(),
		false,
		"AGF tells Shortest Path it is not integrating RestedXP"
	)
	equal(h.G.AdventureGuideForever.API.RestedXPNativeUI(), true, "and that RestedXP's native frontend is restored")
	equal(h.ns.RestedXP.Active(), true, "while the guide stays readable for browsing")

	local skipsKey = key
	h.ns.Prefs().guideSkips = { [skipsKey] = { [2] = true } }
	local setSteps = 0
	local setStep = rxp.SetStep
	rxp.SetStep = function(value)
		setSteps = setSteps + 1
		return setStep(value)
	end
	h.ns.RestedXP.Refresh()
	h.flush()
	equal(setSteps, 0, "no automatic skip is applied")

	h.watched = { 850, 855 }
	h.ns.QuestWatch.Sync()
	equal(h.ns.QuestWatch.Source(), nil, "the RestedXP guide does not lead AGF's watches")
	equal(#h.watched, 2, "the player's watches stay")

	h.ns.SetSetting("informationOnly", false)
	h.flush()
	equal(rxp.RXPFrame:GetAlpha(), 0, "normal mode hides RestedXP's window again")
	equal(h.ns.QuestWatch.Source(), "rxp", "and the guide leads the watches again")
	equal(h.G.AdventureGuideForever.API.RestedXPIntegrated(), true, "AGF integrates RestedXP again")
	equal(#h.errors, 0, table.concat(h.errors, "\n"))

	-- Starting directly in information mode never restored anything AGF did not hide: no redraw, no frame move.
	local updates = 0
	local fromStart = harness.load({
		spf = "v1",
		db = { informationOnly = true, autoStart = false },
		charDB = { journey = key },
		completed = { 844 },
		log = LOG,
		setup = function(client)
			local engine = dofile("tests/rxp_fixture.lua")(client, 0)
			local update = engine.UpdateMap
			engine.UpdateMap = function(...)
				updates = updates + 1
				return update(...)
			end
		end,
	})
	fromStart.flush()
	local started = fromStart.G.RXP
	equal(started.RXPFrame:GetAlpha(), 1, "RestedXP's window was never hidden")
	equal(started.arrowFrame:GetAlpha(), 1, "and its arrow was never hidden")
	equal(updates, 0, "AGF did not restore state it never owned")
	equal(fromStart.spf.NavigateRoute or 0, 0, "and started no route")
	equal(#fromStart.errors, 0, table.concat(fromStart.errors, "\n"))
end

print(("information_mode_spec: %d checks passed"):format(checks))
