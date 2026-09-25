local harness = dofile("tests/harness.lua")
local checks = 0
local function eq(a, b, label)
	checks = checks + 1
	assert(a == b, (label or "check") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function clean(h)
	eq(#h.errors, 0, table.concat(h.errors, "\n"))
end
local function step(key, kind, ids)
	return {
		key = key,
		kind = kind or "area",
		title = key,
		quests = ids or {},
		reason = "Reason",
		detail = "",
		map = 1413,
		x = 0.5,
		y = 0.3,
	}
end

-- Providers preserve scope, disabled categories, unknown counts and detached copies.
do
	local summary = {
		map = 1413,
		name = "The Barrens",
		done = 1,
		total = 2,
		pending = 3,
		complete = false,
		questsStatus = "loading",
		categories = {
			{ key = "areas", scope = "character", done = 1, total = 2, pending = 0, complete = false },
			{ key = "legacy", scope = "account", done = 0, total = 0, pending = 3, complete = false },
		},
	}
	local target = { key = "opaque", text = "An objective", kind = "kill", achievementID = 1, criteriaID = 2 }
	local fake = { summaries = { [1413] = summary }, targets = { [1413] = { target } } }
	local h = harness.load({ legacy = fake, entrances = { [36] = { map = 1436, x = 0.42, y = 0.71 } } })
	local P = h.ns.Providers
	eq(P.LegacyState(), "ready")
	local result = P.Completion()
	eq(result.zones[1].map, 1413)
	eq(result.zones[1].summary.categories[2].scope, "account")
	eq(result.zones[1].summary.pending, 3)
	eq(result.zones[1].targets[1].place, nil)
	result.zones[1].summary.categories[2].scope = "character"
	eq(summary.categories[2].scope, "account", "fresh summary")
	result.zones[1].targets[1].text = "changed"
	eq(target.text, "An objective", "fresh target")
	local notifications = 0
	P.OnChange(function()
		notifications = notifications + 1
	end)
	eq(h.legacy.subscriptions, 0)
	P.SetShown(true)
	P.SetShown(true)
	eq(h.legacy.subscriptions, 1)
	h.legacyChanged()
	eq(notifications, 1)
	P.SetShown(false)
	h.legacyChanged()
	eq(notifications, 1)
	fake.navigateError = "stale"
	local ok, err = P.NavigateCompletion(1413, "opaque")
	eq(ok, false)
	eq(err, "stale")
	local point = P.DungeonEntrance(36)
	point.x = 0
	eq(P.DungeonEntrance(36).x, 0.42, "fresh entrance")
	eq(P.GoToEntrance(36), true)
	eq(h.waypoint.uiMapID, 1436, "entrance uses outdoor UiMapID")
	local _, missing = P.DungeonEntrance(999)
	eq(missing, "unknown")
	h.G.TweaksForever.API.version = 0
	_, missing = P.DungeonEntrance(36)
	eq(missing, "outdated")
	h.G.LegacyForever.API.version = 0
	eq(P.LegacyState(), "outdated")
	h.G.LegacyForever = nil
	eq(P.LegacyState(), "missing")
	clean(h)
end

-- PvP includes every unlocked battleground, including one without a known battlemaster.
do
	local rank = {
		info = { renownLevel = 0, renownReputationEarned = 0, renownLevelThreshold = 100, maxLevel = 14 },
		rewards = { [1] = { { description = "A title", icon = 134000 } } },
	}
	local h = harness.load({
		rank = rank,
		player = { level = 30 },
		battlegrounds = {
			[10] = { { id = 2, name = "Warsong Gulch" } },
			[20] = { { id = 3, name = "Arathi Basin" } },
			[30] = { { id = 1157, name = "Darkspear Islands" } },
			[31] = { { id = 999, name = "Later" } },
		},
	})
	local pvp = h.ns.PvP.Data()
	eq(#pvp.battlegrounds, 3)
	eq(pvp.battlegrounds[1].place, nil)
	eq(pvp.rank.state, "unranked")
	eq(pvp.rank.threshold, 100)
	eq(pvp.rank.reward.text, "A title")
	rank.info.renownLevel = 14
	eq(h.ns.PvP.Data().rank.state, "capped")
	eq(h.ns.PvP.Data().rank.reward, nil)
	rank.info = nil
	eq(h.ns.PvP.Data().rank.state, "unavailable")
	eq(h.ns.PvP.Go(999), false)
	eq(h.ns.PvP.Go(1157), false)
	clean(h)
end

local h = harness.load({})
local M, O, S = h.ns.Model, h.ns.Order, h.ns.Session
eq(O.CanMove(1, 2), false, "unchosen journey cannot move")
eq(O.Move(1, 2), false, "unchosen move is refused without changing preferences")
eq(h.ns.Prefs().customOrders, nil, "refused move does not persist an order")
local pick, work, hand, extra =
	step("pick", "town", { 1 }), step("work", "area", { 1 }), step("hand", "town", { 1 }), step("extra", "trainer")
pick.pickups, pick.handins = { 1 }, {}
work.objectives = { { id = 1, slot = 0, need = 2, have = 0 } }
hand.pickups, hand.handins = {}, { 1 }
local steps = { pick, work, hand, extra }
eq(O.Valid(steps), true)
eq(O.Valid({ work, pick, hand }), false, "pickup before work")
eq(O.Valid({ pick, hand, work }), false, "work before turn-in")
local merged = O.Merge(steps, { "hand", "extra", "pick", "work", "gone" })
eq(merged[1], extra, "unrelated custom priority kept")
eq(merged[2], pick)
eq(merged[3], work)
eq(merged[4], hand)
eq(O.Merge(steps, { "extra" })[2], pick, "new work appends in suggested order")
local n, seconds = S.Prefix(steps, { 10, 10, 10, 10 }, 30)
eq(n, 3, "exact budget")
eq(seconds, 30)
eq(S.Prefix(steps, { 10, 10, 10, 10 }, 29), 0, "pickup cannot outlive its work")
eq(S.Prefix({ extra, pick, work, hand }, { 10, 10, 10, 10 }, 30), 1, "earlier complete task survives")
eq(S.Prefix(steps, { nil, 1, 1, 1 }, 100), 0, "unknown leg is not free")
eq(S.Prefix(steps, { 1000, 1, 1, 1 }, 900), 0, "first task over budget")
eq(S.Work(step("d", "dungeon")), nil, "no dungeon duration")
work.objectives[1].slot = 16
eq(S.Work(work), nil, "no scripted duration")
work.objectives[1].slot = 0

-- Persistence, exact moves, reset and a committed session that never refills.
do
	local route = { journey = "test", chosen = true, journeys = {}, steps = steps, orders = {} }
	route.journeys = { { key = "test", steps = steps } }
	local originalRoute = h.ns.Route
	h.ns.Route = function()
		return route
	end
	h.ns.Prefs().journey = "test"
	eq(O.CanMove(2, 1), false)
	eq(O.CanMove(4, 1), true)
	eq(O.Move(4, 1), true)
	eq(O.IsCustom(), true)
	O.Apply(route, h.ns.Prefs())
	eq(route.steps[1], extra)
	O.Reset()
	eq(O.IsCustom(), false)
	h.ns.Prefs().sessionMinutes = 15
	local trimmed = S.Apply(route)
	eq(trimmed.chosen, true)
	local saved = h.ns.Prefs().sessionCommit
	eq(saved ~= nil, true)
	local added = step("added", "trainer")
	route.steps = { added }
	trimmed = S.Apply(route)
	eq(#trimmed.steps, 0, "new tasks do not refill")
	eq(trimmed.chosen, true, "empty keeps choice")
	eq(S.Info().empty, true)
	h.ns.Route = originalRoute
end

-- Givers tick independently and the real destination moves to the nearest remaining giver.
do
	local a = { map = 1, x = 0.2, y = 0.5, name = "A", hub = 1 }
	local b = { map = 1, x = 0.8, y = 0.5, name = "B", hub = 1 }
	local data = {
		quests = { [1] = { title = "One" }, [2] = { title = "Two" } },
		maps = { [1] = { continent = 1, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [1] = { x = 0, y = 0 } },
	}
	local player = { map = 1, x = 0.1, y = 0.5 }
	local town = step("town:1", "town", { 1, 2 })
	town.pickups, town.handins, town.spots, town.place = { 1 }, { 2 }, { [1] = a, [2] = b }, "Town"
	M.TownChecklist(data, player, {}, {}, town)
	eq(#town.checklist, 2)
	eq(town.x, 0.2)
	eq(town.complete, false)
	local nextTown = step("town:1", "town", { 2 })
	nextTown.pickups, nextTown.handins, nextTown.spots = {}, { 2 }, { [2] = b }
	M.TownChecklist(data, player, {}, { [1] = {} }, nextTown, town)
	eq(#nextTown.checklist, 2)
	eq(nextTown.checklist[1].done, true)
	eq(nextTown.x, 0.8)
	M.TownChecklist(data, player, { [2] = true }, { [1] = {} }, nextTown, nextTown)
	eq(nextTown.complete, true, "all givers complete")
	M.StepTitle(data, {}, town)
	eq(town.verb, "town")
	eq(town.title, "Visit Town: pick up 1, turn in 1")
	local area = step("a", "area", { 1 })
	area.objectives = { { id = 1, slot = 4, type = "item", text = "0/6 Gooey Spider Leg" } }
	M.StepTitle(data, {}, area)
	eq(area.title, "Collect 0/6 Gooey Spider Leg · One")
end

-- English bind names must resolve uniquely; locale mismatches or missing innkeepers suppress advice.
do
	local data = {
		hubs = { [1] = { name = "Home, Zone" }, [2] = { name = "Away, Zone" } },
		maps = { [1] = { continent = 1, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [1] = { x = 0, y = 0 } },
		npcs = {
			[1] = { inn = true, side = 1, place = { map = 1, x = 0.5, y = 0.5, hub = 2, name = "Innkeeper" } },
		},
		quests = {},
	}
	local player = { side = 1, map = 1, x = 0.2, y = 0.5 }
	local town = { hub = 2 }
	eq(h.ns.Hearth.Advice(data, player, { town }, "Home", "enUS").text, "Set your hearth in Away")
	eq(h.ns.Hearth.Advice(data, player, { town }, "Away", "enUS"), nil)
	eq(h.ns.Hearth.Advice(data, player, { town }, "Home", "frFR"), nil)
	data.hubs[3] = { name = "Home, Other" }
	eq(h.ns.Hearth.Advice(data, player, { town }, "Home", "enUS"), nil)
	data.hubs[3] = nil
	player.side = 2
	eq(h.ns.Hearth.Advice(data, player, { town }, "Home", "enUS"), nil)
end

-- One step, one sound; stock quest sounds suppress our tick for a second.
do
	local before = #h.sounds
	h.ns.Sound.Complete("one")
	h.ns.Sound.Complete("one")
	eq(#h.sounds, before + 1)
	h.ns.Sound.ClientEvent()
	h.ns.Sound.Complete("two")
	eq(#h.sounds, before + 1)
	h.time = h.time + 1.1
	h.ns.Sound.Complete("two")
	eq(#h.sounds, before + 1)
	h.ns.Sound.Complete("three")
	eq(#h.sounds, before + 2)
	h.ns.SetSetting("stepSound", false)
	h.ns.Sound.Complete("four")
	eq(#h.sounds, before + 2)
end

-- SPF's current stop is authoritative, and AGF contributes only one reason line.
do
	local t = harness.load({
		spf = "ended",
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	})
	t.ns.StartRoute()
	t.flush()
	local sent = t.ns.Integrations.Guided()
	if #sent > 1 then
		t.spfAdvance()
	end
	t.fire("SUPER_TRACKING_CHANGED")
	t.flush()
	local current = t.ns.Integrations.CurrentStep()
	eq(current.title, t.spfRoute.stops[t.spfRoute.index].title)
	local block = t.tracker.liveBlocks[current.key]
	eq(block.header, current.title)
	eq(#block.order, 1, "trimmed tracker")
	clean(t)
end
-- A skipped giver removes its pickups from subsequent plans and completes the visit once none remain.
do
	local t = harness.load({
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	})
	local original = t.ns.Route().steps[1]
	local giver = original.checklist[1]
	eq(t.ns.Order.SkipGiver(original.key, giver.key), true)
	t.flush()
	local current = t.ns.Route().steps[1]
	local ticked = false
	for _, row in ipairs(current.checklist) do
		if row.key == giver.key then
			ticked = row.done and row.skipped
		end
	end
	eq(ticked, true, "skipped giver remains ticked in town")
	for _, id in ipairs(giver.pickups) do
		for _, card in ipairs(t.ns.Route().journeys) do
			for _, planned in ipairs(card.steps) do
				for _, questID in ipairs(planned.quests) do
					eq(questID == id, false, "skipped pickup has no dependent work")
				end
			end
		end
	end
	clean(t)
end

-- Completion zones use their outdoor destination, not an off-zone starting giver, and never repeat a map.
do
	local t = harness.load({ legacy = { summaries = {} } })
	t.ns.Route = function()
		return {
			chosen = true,
			journey = "zone:1440",
			steps = {},
			journeys = {
				{ key = "zone:1440", kind = "story", map = 1413 },
				{ key = "zone:1440", kind = "nextzone", map = 1440 },
				{ key = "zone:1436", kind = "nextzone", map = 1436 },
				{ key = "zone:1437", kind = "nextzone", map = 1437 },
				{ key = "zone:1442", kind = "nextzone", map = 1442 },
			},
		}
	end
	local zones = t.ns.Providers.Completion().zones
	eq(#zones, 4)
	eq(zones[1].map, 1413)
	eq(zones[2].map, 1440)
	eq(zones[4].map, 1437)
	t.G.LegacyForever.API.ZoneSummary = function(map)
		return {
			map = map,
			name = "Zone",
			done = 0,
			total = 0,
			pending = 0,
			complete = true,
			categories = {},
			questsStatus = "disabled",
		}
	end
	eq(t.ns.Providers.Completion().zones[1].summary.complete, false, "disabled categories cannot prove completion")
end

-- A rebuild cannot extend a committed task by merging new quest work into its old stable key.
do
	local route = { chosen = true, journey = "test", journeys = {}, steps = { work } }
	route.journeys = { { key = "test", steps = route.steps } }
	h.ns.Prefs().sessionMinutes, h.ns.Prefs().sessionCommit = 15, nil
	local trimmed = S.Apply(route)
	eq(#trimmed.steps, 1, "existing carried work fits")
	work.quests = { 1, 2 }
	work.objectives[2] = { id = 2, slot = 0, need = 1, have = 0 }
	eq(#S.Apply(route).steps, 0, "new merged quest does not refill the session")
	work.quests, work.objectives[2] = { 1 }, nil
	route.steps = { pick, work, hand }
	eq(#S.Apply(route).steps, 0, "a new prerequisite cannot be omitted")
end

-- Completion is evidenced by objectives, not merely by a vanished route row.
do
	h.ns.SetSetting("stepSound", true)
	h.ns.Prefs().journey = "sound-test"
	local data = h.ns.Data
	h.ns.Data = { quests = { [1] = { need = { [0] = 1, [4] = 1 } } } }
	local previous = { chosen = true, journey = "sound-test", steps = { work } }
	local current = { chosen = true, journey = "sound-test", steps = {} }
	local before = #h.sounds
	h.ns.Sound.Observe(previous, current, {}, {})
	eq(#h.sounds, before, "abandoning does not play completion")
	local log = {
		[1] = {
			id = 1,
			complete = false,
			objectives = {
				{ type = "monster", done = true },
				{ type = "item", done = false },
			},
		},
	}
	h.ns.Sound.Observe(previous, current, {}, log)
	h.ns.Sound.Observe(previous, current, {}, log)
	eq(#h.sounds, before + 1, "completed area sounds once while another objective remains")
	h.ns.Data = data
end

-- A full log requires its hand-in before another pickup, even when quests are otherwise independent.
do
	local turn = step("turn", "turnin", { 99 })
	local pickup = step("new", "town", { 100 })
	pickup.pickups, pickup.handins = { 100 }, {}
	eq(O.Valid({ pickup, turn }, 1, { [99] = {} }), false, "log capacity blocks an otherwise valid move")
	eq(O.Merge({ turn, pickup }, { "new", "turn" }, 1, { [99] = {} })[1], turn, "capacity repairs saved order")
end

clean(h)
print(("batch4_spec: %d checks passed"):format(checks))
