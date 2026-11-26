-- The grave POI stays in the log while bag events move the route between the item source and its use.
local harness = dofile("tests/harness.lua")
local QUEST, ITEM, MAP = 6395, 16333, 1420

local function Load(logged, variant, saved, spf)
	local other = variant ~= nil
	local id, item = QUEST, ITEM
	local title, itemName, target, objectiveText =
		"Marla's Last Wish", "Samuel's Remains", 178090, "Samuel's Remains Buried"
	if other then
		id, item = 700001, 700002
		title, itemName, target, objectiveText = "The Floodgate", "Floodgate Key", 700003, "Floodgate Opened"
	end
	local required = variant == "two items" and { item, 700004 } or { item }
	local trigger = variant == "two slots" and { "Signal sent", { [85] = { { 48, 65 } } } } or nil
	local objectives = { { type = "object", text = objectiveText, done = false } }
	if trigger then
		objectives[2] = { type = "event", text = trigger[1], done = false }
	end
	local h = harness.load({
		spf = spf,
		planned = true,
		charDB = saved or { journey = "zone:1420" },
		player = { level = 5, raceID = 5, classID = 1, map = MAP, x = 0.32, y = 0.65 },
		bank = { [item] = 1 },
		items = { [item] = { name = itemName, quality = 3 } },
		questiedb = {
			quests = {
				[id] = {
					name = title,
					questLevel = 5,
					requiredLevel = 3,
					startedBy = { { 1661 } },
					finishedBy = { { 1661 } },
					zoneOrSort = 85,
					requiredSourceItems = required,
					objectives = { nil, { { target } } },
					triggerEnd = trigger,
				},
			},
			npcs = {
				[1661] = { name = "Novice Elreth", spawns = { [85] = { { 32, 65 } } } },
				[1919] = { name = "Samuel Fipps", spawns = { [85] = { { 36, 65 } } } },
			},
			objects = {
				[target] = { name = objectiveText, spawns = { [85] = { { 30, 65 } } } },
				[700005] = { name = "Lockbox", spawns = variant ~= "unplaced" and { [85] = { { 36, 65 } } } or nil },
			},
			items = {
				[item] = {
					name = itemName,
					npcDrops = not other and { 1919 } or nil,
					itemDrops = other and { 700006 } or nil,
				},
				[700004] = { name = "Floodgate Handle", objectDrops = { 700005 } },
				[700006] = { name = "Closed Box", objectDrops = { 700005 } },
			},
			zones = { area = { [85] = MAP } },
		},
		log = logged and {
			{
				id = id,
				title = title,
				level = 5,
				poi = { map = MAP, x = 0.30, y = 0.65 },
				objectives = objectives,
			},
		} or {},
		setup = function(loaded)
			if saved then
				loaded.G.LibQuestieDB.Quest.GetAllIds = function()
					error("login rebuilt the saved catalogue")
				end
			end
			loaded.G.Questie = { API = { isReady = true } }
			loaded.G.QuestieLoader = {
				ImportModule = function()
					return {
						IsDoable = function()
							return true
						end,
					}
				end,
			}
		end,
	})
	h.flush()
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
	assert(h.ns.QuestieStatus.state == "questie", "provider catalogue is ready")
	return h, id
end

local function Place(h, id, x, label)
	for _, step in ipairs(h.ns.Route().steps) do
		for _, objective in ipairs(step.objectives or {}) do
			if objective.id == id and step.map == MAP and step.x == x then
				return step, objective
			end
		end
	end
	error(label .. ", expected a step at " .. x)
end

local h = Load(true)
local _, source = Place(h, QUEST, 0.36, "logged quest with the item in the bank points to Samuel")
assert(source.type == "item" and source.text == "Samuel's Remains" and not source.index)
h.fire("BAG_UPDATE_DELAYED")
h.flush()
local _, repainted = Place(h, QUEST, 0.36, "repaint keeps the item step")
assert(repainted.text == source.text)

h.bags[ITEM] = 1
h.fire("BAG_UPDATE_DELAYED")
h.flush()
local _, use = Place(h, QUEST, 0.30, "looting the item sends the guide to the grave")
assert(use.index == 1, "the grave retains its client objective index")
h.bags[ITEM] = nil
h.fire("BAG_UPDATE_DELAYED")
h.flush()
Place(h, QUEST, 0.36, "losing the item sends the guide back to Samuel")
assert(#h.errors == 0, table.concat(h.errors, "\n"))

local pickup = Load(false)
local step = Place(pickup, QUEST, 0.36, "lap after pickup sends the guide to Samuel first")
assert(step.planned and step.planned[QUEST], "the lap marks the work as after pickup")
for _, each in ipairs(pickup.ns.Route().steps) do
	for _, id in ipairs(each.handins or {}) do
		assert(id ~= QUEST, "collecting the source item does not make the quest ready to hand in")
	end
end
pickup.bags[ITEM] = 1
pickup.fire("BAG_UPDATE_DELAYED")
pickup.flush()
Place(pickup, QUEST, 0.30, "lap after pickup points at the use place when the item is held")

local floodgate, id = Load(true, "placed")
local _, key = Place(floodgate, id, 0.36, "the floodgate quest points at the box containing the key")
assert(key.type == "item" and key.text == "Floodgate Key" and not key.index)
floodgate.bags[700002] = 1
floodgate.fire("BAG_UPDATE_DELAYED")
floodgate.flush()
local _, gate = Place(floodgate, id, 0.30, "looting the key sends the guide to the floodgate")
assert(gate.index == 1)

for _, variant in ipairs({ "two items", "two slots", "unplaced" }) do
	local unchanged, quest = Load(true, variant)
	assert(not unchanged.ns.Data.quests[quest].sourceItem, variant .. " has no source item dependency")
	local _, objective = Place(unchanged, quest, 0.30, variant .. " keeps the use place")
	assert(objective.index == 1)
end

local failures = {}
local function Check(ok, message)
	if not ok then
		failures[#failures + 1] = message
	end
end

do
	local ns = {}
	harness.model(ns)
	local function Town(x)
		return { map = 1, x = x, y = 0.5, hub = "1", name = "Giver" }
	end
	local function Quest()
		return {
			title = "Quest",
			level = 20,
			min = 10,
			side = 1,
			zone = 1,
			start = Town(0.48),
			finish = Town(0.52),
			need = { [0] = 1 },
			kinds = { [0] = "object" },
			obj = { { 0, 510, 500, 0, 1 } },
		}
	end
	local data = {
		build = "test",
		source = "fixture",
		quests = { [100] = Quest() },
		zones = { [1] = { name = "Zone", min = 10, max = 30 } },
		maps = { [1] = { name = "Zone", continent = 1, cx = 0, cy = 0, sx = 10000, sy = 10000 } },
		continents = { [1] = { x = 0, y = 0 } },
		hubs = { ["1"] = { name = "Town" } },
		towns = { [1] = {} },
	}
	local player = {
		level = 20,
		maxLevel = 60,
		logMax = 40,
		side = 1,
		raceBit = 1,
		classBit = 1,
		map = 1,
		x = 0.5,
		y = 0.5,
	}
	local log = { [100] = { id = 100, title = "Carried", level = 20, objectives = { { type = "object" } } } }
	local function Picked(quest)
		data.quests[QUEST] = quest
		local route = ns.Model.Plan(data, player, {}, log, { quests = true, dungeons = false, skipped = {} })
		for _, journey in ipairs(route.journeys) do
			if journey.kind == "carry" then
				for _, visit in ipairs(journey.steps) do
					for _, questID in ipairs(visit.pickups or {}) do
						if questID == QUEST then
							return true
						end
					end
				end
			end
		end
		return false
	end
	local quest = Quest()
	assert(Picked(quest), "carry offers the quest before adding its source item")
	quest.sourceItem = { id = ITEM, slot = 0, name = "Samuel's Remains" }
	quest.obj[2] = { -1, 490, 500, 0, 1 }
	Check(Picked(quest), "carry still offers the quest when all four stops are on the way")

	quest.obj[2][2] = 900
	Check(not Picked(quest), "carry includes a required item source in the detour")
	player.sourceItems = { [ITEM] = true }
	Check(Picked(quest), "carry ignores a distant source when the item is already held")
	player.sourceItems = nil
	quest.obj[2][2] = 490

	quest.start = Town(0.9)
	Check(not Picked(quest), "carry includes the pickup place in the detour")
	quest.start = Town(0.48)
	quest.finish = Town(0.9)
	Check(not Picked(quest), "carry includes the hand-in place in the detour")
	quest.finish = Town(0.52)
	quest.obj[1][2] = 900
	Check(not Picked(quest), "carry includes the use place in the detour")
	table.remove(quest.obj, 1)
	Check(not Picked(quest), "carry excludes the quest when its use place is unknown")

	local slow, quick = Quest(), Quest()
	slow.xp, quick.xp = 100, 100
	slow.sourceItem = { id = ITEM, slot = 0 }
	slow.obj = { { -1, 480, 500, 0, 1 }, { 0, 900, 500, 0, 1 } }
	quick.obj[1][2] = 480
	local lapData = {}
	for field, value in pairs(data) do
		lapData[field] = value
	end
	lapData.quests = { [QUEST] = slow, [700001] = quick }
	local function OptimisedPickups(held)
		player.sourceItems = held and { [ITEM] = true } or nil
		local candidates, ids = {}, {}
		ns.Planner.Steps.PickupSteps(lapData, { QUEST, 700001 }, function()
			return true
		end, candidates)
		local steps = ns.Planner.Laps.Laps(
			lapData,
			player,
			{},
			{},
			candidates,
			{ areas = {}, anchors = {} },
			{ optimisedRoute = true, skipped = {} }
		)
		for _, visit in ipairs(steps) do
			for _, questID in ipairs(visit.pickups or {}) do
				ids[#ids + 1] = questID
			end
		end
		table.sort(ids)
		return table.concat(ids, ",")
	end
	local missing, held = OptimisedPickups(false), OptimisedPickups(true)
	Check(
		held == "700001" and missing == held,
		("optimised pickups with the item missing (%s) or held (%s) should match"):format(missing, held)
	)
end

do
	local combat = Load(true, nil, nil, "v1")
	local journey = combat.ns.Route().journey
	local sourceStep = Place(combat, QUEST, 0.36, "the chosen zone starts at the source")
	assert(combat.ns.Route().chosen and journey == "zone:1420" and #combat.ns.Route().steps == 1)
	combat.ns.StartRoute()
	combat.flush()
	local prefs, shortestPath = combat.ns.Prefs(), combat.spfRoute
	local cancels = combat.spf.Cancel
	assert(prefs.journey == journey and prefs.guided == journey and combat.ns.Guidance.Owns())
	assert(shortestPath and shortestPath.stops[1].map == MAP and shortestPath.stops[1].x == 0.36)

	local function GuidancePersists()
		Check(prefs.journey == journey, "combat keeps the saved journey choice")
		Check(prefs.guided == journey, "combat keeps the saved guidance")
		Check(
			combat.spf.Cancel == cancels and combat.spfRoute == shortestPath,
			"combat leaves AGF's Shortest Path route running"
		)
	end
	combat.combat = true
	combat.fire("PLAYER_REGEN_DISABLED")
	combat.bags[ITEM] = 1
	combat.fire("BAG_UPDATE_DELAYED")
	combat.flush()
	for _, card in ipairs(combat.ns.Route().journeys) do
		for _, visit in ipairs(card.steps) do
			Check(visit.key ~= sourceStep.key, "combat removes the source stop from " .. card.key)
			for _, objective in ipairs(visit.objectives or {}) do
				Check(
					objective.id ~= QUEST or objective.slot >= 0,
					"combat removes the source objective from " .. card.key
				)
			end
		end
	end
	GuidancePersists()
	combat.ns.Invalidate()
	combat.flush()
	GuidancePersists()
	combat.combat = false
	combat.fire("PLAYER_REGEN_ENABLED")
	combat.flush()
	Check(combat.ns.Route().chosen and combat.ns.Route().journey == journey, "the same zone stays chosen after combat")
	local usePlace = Place(combat, QUEST, 0.30, "the full plan after combat leads to the use place")
	Check(prefs.guided == journey and combat.ns.Guidance.Owns(), "the same zone is still guided after combat")
	local stop = combat.spfRoute and combat.spfRoute.stops[1]
	Check(
		stop and stop.map == usePlace.map and stop.x == usePlace.x and stop.y == usePlace.y,
		"the last route handed to Shortest Path leads to the use place"
	)
	assert(#combat.errors == 0, table.concat(combat.errors, "\n"))
end

do
	local itemStep = Place(h, QUEST, 0.36, "the missing item has a step line to style")
	local text = "Collect Samuel's remains"
	local style = h.ns.StepStyle
	local expected = "Collect " .. style.Wrap(h.G.ITEM_QUALITY_COLORS[3].color, "Samuel's remains")
	Check(style.Step(itemStep, text) == expected, "the source item uses its quality colour regardless of case")
end

do
	local sound = Load(true)
	local _, item = Place(sound, QUEST, 0.36, "the item step is open before it can complete")
	local model, data = sound.ns.Model, sound.ns.Data
	assert(not model.ObjectiveDone(data, sound.ns.State.Log()[QUEST], item.slot))
	local before = #sound.sounds
	sound.bags[ITEM] = 1
	sound.fire("BAG_UPDATE_DELAYED")
	sound.flush()
	Place(sound, QUEST, 0.30, "the bag event completes the item step")
	Check(model.ObjectiveDone(data, sound.ns.State.Log()[QUEST], item.slot), "the held item completes its pseudo slot")
	Check(
		#sound.sounds == before + 1 and sound.sounds[before + 1] == sound.G.SOUNDKIT.UI_SCENARIO_STAGE_END,
		"obtaining the item plays the step-complete sound"
	)
end

for _, signal in ipairs({ "objective done", "quest complete" }) do
	local used = Load(true)
	used.bags[ITEM] = 1
	used.fire("BAG_UPDATE_DELAYED")
	used.flush()
	Place(used, QUEST, 0.30, "the item is held before using it")

	used.bags[ITEM] = nil
	if signal == "objective done" then
		used.log[1].objectives[1].done = true
	else
		used.log[1].complete = true
	end
	used.fire("BAG_UPDATE_DELAYED")
	used.fire("QUEST_LOG_UPDATE")
	used.flush()
	local handin = false
	for _, visit in ipairs(used.ns.Route().steps) do
		if visit.map == MAP and visit.x == 0.32 then
			handin = handin or visit.key == "turnin:" .. QUEST
			for _, questID in ipairs(visit.handins or {}) do
				handin = handin or questID == QUEST
			end
		end
		for _, objective in ipairs(visit.objectives or {}) do
			Check(objective.id ~= QUEST or objective.slot >= 0, signal .. " never routes back to the source")
		end
	end
	Check(handin, signal .. " sends the player to the hand-in after consuming the item")
	assert(#used.errors == 0, table.concat(used.errors, "\n"))
end

do
	local saved = h.G.AdventureGuideForeverCharDB
	assert(saved.catalogue, "the first login saved the catalogue")
	local reloaded = Load(true, nil, saved)
	Place(reloaded, QUEST, 0.36, "a login from the saved catalogue points at the item source")
	reloaded.bags[ITEM] = 1
	reloaded.fire("BAG_UPDATE_DELAYED")
	reloaded.flush()
	Place(reloaded, QUEST, 0.30, "the saved catalogue still watches the source item's bag count")
end

assert(#failures == 0, "\n" .. table.concat(failures, "\n"))
print("required_source_item_spec: passed")
