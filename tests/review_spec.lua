local harness = dofile("tests/harness.lua")
local characters = dofile("tests/fixtures/characters.lua")
local checks, failures = 0, {}
local function eq(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, run)
	local ok, err = pcall(run)
	if not ok then
		failures[#failures + 1] = name .. ": " .. err
	end
end
local function fixture(ns, name)
	for _, value in ipairs(characters.list) do
		if value.name == name then
			return characters.Resolve(ns.Data, value)
		end
	end
	error("Missing fixture: " .. name)
end

test("B1 rejected town offers", function()
	local ns = harness.load({}).ns
	local player, completed, log, prefs = fixture(ns, "human18_redridge")
	local route = ns.Model.Plan(ns.Data, player, completed, log, prefs)
	local town = route.steps[1]
	eq(town.key, "town:61", "Lakeshire visit")
	for _, id in ipairs(town.pickups) do
		eq(id == 92 or id == 116, false, "filtered work stays out of the town offers")
	end
	eq(#town.pickups, 5, "only filtered offers remain")
	player, completed, log, prefs = fixture(ns, "ne23_darkshore")
	route = ns.Model.Plan(ns.Data, player, completed, log, prefs)
	for _, step in ipairs(route.steps) do
		if step.key == "town:415" then
			eq(table.concat(step.pickups, ","), "1010", "scripted escort 976 stays rejected")
		end
	end
end)

test("A1 reload preserves the committed return", function()
	local h = harness.load({})
	local ns = h.ns
	local player, completed, log, prefs = fixture(ns, "human18_redridge")
	local data = {}
	for key, value in pairs(ns.Data) do
		data[key] = value
	end
	data.quests = { [3741] = ns.Data.quests[3741] }
	ns.Prefs = function()
		return prefs
	end
	ns.State.Player = function()
		return player
	end
	ns.State.Where = function()
		return player.map, player.x, player.y
	end
	prefs.sessionMinutes = 15
	local before = ns.Model.Plan(data, player, completed, log, prefs)
	eq(#ns.Session.Apply(before).steps, 3, "pickup, work and return fit")
	log[3741] = {
		id = 3741,
		title = "Hilary's Necklace",
		level = 15,
		complete = false,
		objectives = { { type = "item", numFulfilled = 0, numRequired = 1, finished = false, text = "Necklace" } },
	}
	local warm = ns.Model.Plan(data, player, completed, log, prefs, nil, nil, before)
	eq(#ns.Session.Apply(warm).steps, 2, "accepted pickup leaves work and return")
	-- A fresh Model has neither a previous route nor planner caches, as after /reload.
	assert(loadfile("Model.lua"))("AdventureGuideForever", ns)
	local cold = ns.Model.Plan(data, player, completed, log, prefs)
	local limited = ns.Session.Apply(cold)
	eq(#limited.steps, 2, "reload retains work and return")
	eq(limited.steps[2].orderKey, before.steps[3].orderKey, "return identity survives reload")
end)

test("A2 independent guidance survives an empty session", function()
	for _, spf in ipairs({ false, "ended" }) do
		local h = harness.load({
			spf = spf or nil,
			charDB = {
				journey = "zone:1413",
				sessionMinutes = 15,
				sessionCommit = { journey = "zone:1413", minutes = 15, keys = {} },
			},
			entrances = { [36] = { map = 1436, x = 0.42, y = 0.71 } },
		})
		eq(h.ns.Session.Info().empty, true, "empty limited session")
		eq(h.ns.Providers.GoToEntrance(36), true, "entrance guidance starts")
		h.fire("QUEST_LOG_UPDATE")
		h.flush()
		eq(h.ns.Integrations.Owns(), true, "unrelated destination remains owned")
		eq(#h.errors, 0, "no event errors")
	end
end)

test("A3 guidance resolves the live step", function()
	local h = harness.load({ spf = "ended" })
	local ns = h.ns
	local function town(count)
		local pickups = count == 2 and { 1, 2 } or { 2 }
		return {
			key = "town:test",
			kind = "town",
			quests = pickups,
			pickups = pickups,
			handins = {},
			title = "Pick up " .. count,
			reason = "Town",
			detail = "",
			map = 1413,
			x = 0.53,
			y = 0.3,
		}
	end
	local live = town(2)
	ns.Model.Plan = function()
		local steps = { live }
		return {
			chosen = true,
			journey = "test",
			steps = steps,
			journeys = {
				{ key = "test", kind = "story", title = "Town", subline = "", map = 1413, steps = steps },
			},
		}
	end
	ns.Choose("test", true)
	h.flush()
	local sent = ns.Integrations.CurrentStep()
	eq(sent, live, "initial snapshot")
	live = town(1)
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	eq(ns.Integrations.CurrentStep(), live, "SPF index resolves to the live route object")
	eq(h.tracker.liveBlocks[live.key].header, live.title, "tracker uses the refreshed title")
	eq(#h.errors, 0, "no refresh errors")
end)

test("A4 PvP progress refreshes with unchanged rewards", function()
	local h = harness.load({
		rank = {
			info = { renownLevel = 3, renownReputationEarned = 1200, renownLevelThreshold = 3000, maxLevel = 14 },
			rewards = { [6] = { { description = "Tabard" } } },
		},
	})
	h.ns.OpenWindow()
	h.flush()
	local window = h.G.AdventureGuideForeverWindow
	h.Click(window.Tabs[3])
	h.flush()
	for _, event in ipairs({ "PLAYER_PVP_RANK_CHANGED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION" }) do
		h.rank.info.renownReputationEarned = h.rank.info.renownReputationEarned + 100
		if event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
			h.rank.info.renownLevel = 4
		end
		h.fire(event, 2800)
		h.flush()
		local text = h.ns.L.PVP_RANK_POINTS:format(h.rank.info.renownReputationEarned, 3000)
		local found, rank = false, false
		for _, entry in ipairs(h.ns.DumpLayout(window, h.Describe)) do
			found = found or entry.text == text
			rank = rank or entry.text == h.ns.L.PVP_RANK:format(h.rank.info.renownLevel)
		end
		eq(found, true, event .. " updates points")
		eq(rank, true, event .. " updates rank")
	end
	window:Hide()
	for _, event in ipairs({ "PLAYER_PVP_RANK_CHANGED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION" }) do
		eq(window.events[event], nil, "hidden window releases " .. event)
	end
end)

test("B2 skipped giver can be shown again", function()
	local h = harness.load({
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	})
	local ns = h.ns
	local town = ns.Route().steps[1]
	local giver = town.checklist[1]
	eq(ns.Order.SkipGiver(town.key, giver.key), true, "giver skipped")
	h.flush()
	eq(#ns.Skipped(), 1, "skip is visible in Show again")
	ns.Unskip(ns.Skipped()[1].key)
	h.flush()
	eq(ns.Order.IsGiverSkipped(town.orderKey, giver.key), false, "Show again clears giver skip")
	for _, id in ipairs(giver.pickups) do
		eq(ns.Order.SkippedQuests()[id], nil, "Show again restores pickup eligibility")
	end
	eq(#ns.Skipped(), 0, "skip menu cleared")
	town = ns.Route().steps[1]
	local checkedHandin = false
	for _, row in ipairs(town.checklist) do
		if #row.handins > 0 then
			checkedHandin = true
			eq(ns.Order.SkipGiver(town.key, row.key), true, "hand-in giver skipped")
			h.flush()
			eq(#ns.Skipped(), 1, "hand-in skip is also visible")
			ns.Unskip(ns.Skipped()[1].key)
			h.flush()
			local restored = false
			for _, step in ipairs(ns.Route().steps) do
				for _, id in ipairs(ns.Model.Handins(step)) do
					restored = restored or id == row.handins[1]
				end
			end
			eq(restored, true, "Show again restores the hand-in")
			break
		end
	end
	eq(checkedHandin, true, "fixture has a hand-in giver")
end)

test("B3 rebuilds preserve absent custom positions", function()
	local ns = harness.load({}).ns
	local keys = { "b", "a", "c" }
	local prefs = { customOrders = { test = keys } }
	local function apply(names)
		local steps = {}
		for _, key in ipairs(names) do
			steps[#steps + 1] = { key = key, kind = "trainer", quests = {} }
		end
		local route = { journey = "test", journeys = { { key = "test", steps = steps } } }
		ns.Order.Apply(route, prefs)
		local result = {}
		for _, step in ipairs(route.steps) do
			result[#result + 1] = step.key
		end
		return table.concat(result, ",")
	end
	eq(apply({ "a", "c", "new1", "new2" }), "a,c,new1,new2", "absent step omitted")
	eq(apply({ "a", "b", "c", "new2", "new1" }), "b,a,c,new2,new1", "returning priority and fresh suggested order")
	eq(prefs.customOrders.test, keys, "rebuild does not write preferences")
end)

test("B4 malformed session members are rejected", function()
	for _, members in ipairs({ 1, true, "bad", { ["town:349"] = 1 }, { ["town:349"] = "bad" } }) do
		local h = harness.load({
			charDB = {
				journey = "zone:1413",
				sessionMinutes = 15,
				sessionCommit = {
					journey = "zone:1413",
					minutes = 15,
					keys = { ["town:349"] = true },
					members = members,
				},
			},
		})
		eq(#h.errors, 0, "invalid members cannot break the rebuild")
		eq(h.ns.Prefs().sessionCommit.members == members, false, "malformed commitment replaced")
	end
	for _, members in ipairs({ false, {}, { ["town:349"] = { ["845"] = true } } }) do
		local commit = { journey = "zone:1413", minutes = 15, keys = {}, members = members or nil }
		local h = harness.load({ charDB = { sessionCommit = commit } })
		eq(h.ns.Prefs().sessionCommit, commit, "valid and legacy commitments survive loading")
	end
end)

test("B5 story-end sound follows the documented fanfare", function()
	local h = harness.load({})
	local ns = h.ns
	local last
	for id in pairs(ns.Data.quests) do
		local story = ns.Model.Story(ns.Data, id)
		if story and story.total == story.chapter then
			last = math.min(last or id, id)
		end
	end
	h.fire("QUEST_TURNED_IN", assert(last))
	h.flush()
	eq(#h.sounds, 1, "story end plays over the stock turn-in sound")
	eq(h.sounds[1], h.G.SOUNDKIT.UI_SCENARIO_STAGE_END, "documented stage-end sound")
	h.fire("QUEST_TURNED_IN", last)
	h.flush()
	eq(#h.sounds, 1, "duplicate turn-in does not replay")
	ns.Sound.Complete("ordinary step")
	eq(#h.sounds, 1, "ordinary step sounds remain suppressed")
end)

test("B8 shared quest and faction helpers", function()
	local ns = harness.load({}).ns
	eq(ns.Model.HasBit(1, 0), false, "unknown faction cannot match a restricted NPC")
	eq(ns.Model.HasBit(0, 0), true, "neutral NPC needs no faction")
	local turnin = { kind = "turnin", quests = { 1 } }
	eq(ns.Model.Handins(turnin), turnin.quests, "standalone turn-in uses its quests")
	local town = { kind = "town", quests = { 1, 2 }, handins = { 1 } }
	eq(ns.Model.Handins(town), town.handins, "town pickups are not hand-ins")
	eq(#ns.Model.Handins({ kind = "area", quests = { 1 } }), 0, "objective work is not a hand-in")
end)

test("B9 town counts omit zeros", function()
	local ns = harness.load({}).ns
	local town = { kind = "town", place = "Town", quests = { 1, 2 }, pickups = { 1, 2 }, handins = {} }
	ns.Model.StepTitle({ quests = {} }, {}, town)
	eq(town.title, "Visit Town: Pick up 2", "pickup-only title")
	town.pickups, town.handins = {}, { 1, 2 }
	ns.Model.StepTitle({ quests = {} }, {}, town)
	eq(town.title, "Visit Town: Turn in 2", "hand-in-only title")
end)

assert(#failures == 0, table.concat(failures, "\n"))
print(("review_spec: %d checks passed"):format(checks))
