-- Integration contract: canonical provider catalogue, live policy and startup/failure behaviour.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Fake()
	return {
		quests = {
			[900001] = {
				name = "Provider-only quest",
				questLevel = 20,
				requiredLevel = 18,
				startedBy = { { 197 } },
				finishedBy = { { 197 } },
				zoneOrSort = 12,
				objectives = { { { 800, nil, 0 } } },
			},
			[900002] = {
				name = "Collect",
				questLevel = 19,
				requiredLevel = 17,
				startedBy = { { 197 } },
				zoneOrSort = 12,
				objectives = { nil, nil, { { 700, nil, 4 } } },
			},
		},
		npcs = {
			[197] = { name = "Giver", spawns = { [12] = { { 49, 42 } } }, zoneID = 12 },
			[800] = { name = "Enemy", spawns = { [12] = { { 50, 50 }, { 50.1, 50.1 } } } },
		},
		items = { [700] = { npcDrops = { 800 } } },
		objects = {},
		zones = { area = { [12] = 1429 } },
	}
end
local function Policy(h, available)
	h.G.Questie = { API = {
		isReady = true,
		RegisterOnReady = function(fn)
			fn()
		end,
	} }
	h.G.QuestieLoader = {
		ImportModule = function()
			return { IsDoable = available or function()
				return true
			end }
		end,
	}
end
for _, case in ipairs({
	{ false, "QUESTIE_ABSENT" },
	{ { contract = 1 }, "QUESTIE_CONTRACT" },
	{ { flavor = "Vanilla" }, "QUESTIE_FLAVOUR" },
	{ { missing = "questLevel" }, "QUESTIE_FIELD" },
	{ { noZones = true }, "QUESTIE_ZONES" },
}) do
	local h = harness.load({ questiedb = case[1] })
	equal(#h.errors, 0, case[2] .. " errors")
	equal(h.ns.QuestieStatus.state, "unavailable", case[2] .. " state")
	equal(next(h.ns.Data.quests), nil, case[2] .. " no stale fallback")
end
local h = harness.load({ questiedb = Fake(), setup = Policy })
equal(#h.errors, 0, "build errors")
equal(h.ns.QuestieStatus.state, "questie", "provider ready")
equal(h.ns.Data.quests[7], nil, "bundled-only quest absent")
local q = h.ns.Data.quests[900001]
equal(q.title, "Provider-only quest", "new quest imported")
equal(q.start.npc, 197, "new quest giver")
equal(q.need[0], 0, "zero icon does not erase an objective")
equal(q.obj[1][5], 1429, "provider objective map")
equal(q.obj[1][2], 500, "provider spawn")
equal(h.ns.Data.quests[900002].need[4], 0, "icon override is not an item count")
equal(h.ns.Data.quests[900002].obj[1][2], 500, "item drop location")
local player = h.ns.State.Player()
player.level = 20
local Model = h.ns.Model
equal(Model.Eligible(h.ns.Data, player, {}, {}, 900001), true, "canonical quest eligible")
-- The provider's zero icon must produce pickup -> work -> hand-in, never a delivery shortcut.
local replay = harness.load({
	questiedb = Fake(),
	setup = Policy,
	player = { level = 20, map = 1429, x = 0.49, y = 0.42 },
})
local picked, worked, returned
for index, step in ipairs(replay.ns.Route().steps) do
	for _, id in ipairs(step.pickups or {}) do
		if id == 900001 then
			picked = index
		end
	end
	for _, objective in ipairs(step.objectives or {}) do
		if objective.id == 900001 then
			worked = index
		end
	end
	for _, id in ipairs(step.handins or {}) do
		if id == 900001 then
			returned = index
		end
	end
end
equal(picked ~= nil and worked ~= nil and returned ~= nil, true, "provider route includes all three actions")
equal(picked < worked and worked < returned, true, "provider route cannot hand in before doing the work")
-- Two quests need the same creature: one kills it, one loots it. One build asks QuestieDB for its spawns once, and
-- for the looted item's droppers once, however many quests share them.
local shared = Fake()
shared.quests[900003] = {
	name = "Collect again",
	questLevel = 19,
	requiredLevel = 17,
	startedBy = { { 197 } },
	zoneOrSort = 12,
	objectives = { nil, nil, { { 700, nil, 2 } } },
}
local spawnReads, dropReads = 0, 0
local once = harness.load({
	questiedb = shared,
	setup = function(loaded)
		Policy(loaded)
		local lib = loaded.G.LibQuestieDB
		local npc, item = lib.Npc.GetAll, lib.Item.GetAll
		lib.Npc.GetAll = function(id, keys)
			spawnReads = spawnReads + (id == 800 and keys[1] == "spawns" and 1 or 0)
			return npc(id, keys)
		end
		lib.Item.GetAll = function(id, keys)
			dropReads = dropReads + (id == 700 and 1 or 0)
			return item(id, keys)
		end
	end,
})
equal(once.ns.QuestieStatus.state, "questie", "shared build ready")
equal(spawnReads, 1, "a creature three quests share is read once a build")
equal(dropReads, 1, "an item two quests collect is read once a build")
for _, id in ipairs({ 900001, 900002, 900003 }) do
	equal(once.ns.Data.quests[id].obj[1][2], 500, "shared spawn still places quest " .. id)
end
-- A quest giver's place and its service flags are one NPC read, and the objective pass takes the giver's spawns
-- rather than asking again: the same creature gives 900014 and is 900014's own objective. A giver tested for the
-- trainer bit shares that same read.
local service = Fake()
service.npcs[900199] = { name = "Giver objective", spawns = { [12] = { { 49, 42 } } }, zoneID = 12 }
service.npcs[900200] = { name = "Class trainer", spawns = { [12] = { { 48, 42 } } }, zoneID = 12, npcFlags = 16 }
service.quests[900014] = {
	name = "Kill the giver",
	questLevel = 20,
	requiredLevel = 18,
	startedBy = { { 900199 } },
	zoneOrSort = 12,
	objectives = { { { 900199, nil, 0 } } },
}
service.quests[900015] = {
	name = "Trainer's task",
	questLevel = 20,
	requiredLevel = 18,
	requiredClasses = 64,
	startedBy = { { 900200 } },
	zoneOrSort = 12,
}
local giverReads, sharedSpawns, trainerReads = 0, 0, 0
local readOnce = harness.load({
	questiedb = service,
	setup = function(loaded)
		Policy(loaded)
		local lib = loaded.G.LibQuestieDB
		local npc = lib.Npc.GetAll
		lib.Npc.GetAll = function(id, keys)
			if id == 900199 then
				giverReads = giverReads + 1
				for _, key in ipairs(keys) do
					sharedSpawns = sharedSpawns + (key == "spawns" and 1 or 0)
				end
			elseif id == 900200 then
				trainerReads = trainerReads + 1
			end
			return npc(id, keys)
		end
	end,
})
equal(readOnce.ns.QuestieStatus.state, "questie", "one-read build ready")
equal(giverReads, 1, "a quest giver's place and service flags are one read")
equal(sharedSpawns, 1, "the objective pass takes the giver's spawns, not a second read")
equal(trainerReads, 1, "a giver tested for the trainer bit is read once")
equal(readOnce.ns.Data.quests[900015].start.trainer, 7, "the shared read still names the class")
-- QuestieDB's own skill, reputation and exclusive gates become the model's fields.
local gated = Fake()
gated.quests[900004] = {
	name = "Gated",
	questLevel = 20,
	requiredLevel = 18,
	startedBy = { { 197 } },
	finishedBy = { { 197 } },
	zoneOrSort = 12,
	requiredSkill = { 197, 230 },
	requiredMinRep = { 576, 3000 },
	exclusiveTo = { 900005 },
}
gated.quests[900005] = {
	name = "Sibling",
	questLevel = 20,
	requiredLevel = 18,
	startedBy = { { 197 } },
	zoneOrSort = 12,
	requiredMaxRep = { 576, 9000 },
	exclusiveTo = { 900004 },
}
gated.quests[900006] = {
	name = "Two factions",
	questLevel = 20,
	requiredLevel = 18,
	startedBy = { { 197 } },
	zoneOrSort = 12,
	requiredMinRep = { 576, 3000 },
	requiredMaxRep = { 21, -6000 },
}
local gates = harness.load({ questiedb = gated, setup = Policy })
equal(gates.ns.QuestieStatus.state, "questie", "gated build ready")
local locked = gates.ns.Data.quests[900004]
equal(locked.skill.id, 197, "requiredSkill: the line")
equal(locked.skill.value, 230, "requiredSkill: the rank")
equal(locked.rep.faction, 576, "requiredMinRep: the faction")
equal(locked.rep.min, 3000, "requiredMinRep: the value")
equal(locked.rep.max, nil, "a minimum alone leaves no maximum")
equal(gates.ns.Data.quests[900005].rep.max, 9000, "requiredMaxRep: the value")
equal(locked.group, gates.ns.Data.quests[900005].group, "exclusiveTo: one group holds both")
equal(locked.group ~= nil, true, "exclusiveTo: a group id")
equal(gates.ns.Data.quests[900006].start, nil, "two reputation factions leave no pickup")
-- A class quest's giver is its class's trainer only when QuestieDB's flags say it trains. A plain giver of the same
-- class quest is never called a trainer, and a flagged trainer still names the quest's single class.
local classes = Fake()
classes.quests[900007] = {
	name = "Plain giver",
	questLevel = 20,
	requiredLevel = 18,
	requiredClasses = 64,
	startedBy = { { 900197 } },
	zoneOrSort = 12,
}
classes.quests[900008] = {
	name = "Flagged trainer",
	questLevel = 20,
	requiredLevel = 18,
	requiredClasses = 64,
	startedBy = { { 900198 } },
	zoneOrSort = 12,
}
classes.npcs[900197] = { name = "Plain giver", spawns = { [12] = { { 48, 42 } } }, zoneID = 12 }
classes.npcs[900198] = { name = "Class trainer", spawns = { [12] = { { 49, 42 } } }, zoneID = 12, npcFlags = 16 }
local classed = harness.load({ questiedb = classes, setup = Policy })
equal(classed.ns.QuestieStatus.state, "questie", "class quest build ready")
equal(classed.ns.Data.quests[900007].start.trainer, nil, "a plain giver is no class trainer")
equal(classed.ns.Data.quests[900008].start.trainer, 7, "QuestieDB's trainer flag names the quest's class")
-- QuestieDB puts a lone prerequisite in preQuestSingle; it is exactly that quest, so the model gets `pre` and can
-- prove the chain's total. Several alternatives stay `preAny`, a group stays `pre`, and both together keep their two
-- meanings: the group all-of and the single any-of.
local prereqs = Fake()
local function Linked(id, single, group)
	prereqs.quests[id] = {
		name = "Linked " .. id,
		questLevel = 20,
		requiredLevel = 18,
		startedBy = { { 197 } },
		zoneOrSort = 12,
		preQuestSingle = single,
		preQuestGroup = group,
	}
end
Linked(900010, { 900001 })
Linked(900011, { 900001, 900002 })
Linked(900012, nil, { 900001 })
Linked(900013, { 900001 }, { 900002 })
local linked = harness.load({ questiedb = prereqs, setup = Policy })
equal(linked.ns.QuestieStatus.state, "questie", "prerequisite build ready")
local lone = linked.ns.Data.quests[900010]
equal(lone.pre and lone.pre[1], 900001, "a lone preQuestSingle is the required quest")
equal(lone.preAny, nil, "a lone preQuestSingle leaves no any-of set")
equal(#linked.ns.Data.quests[900011].preAny, 2, "several preQuestSingle stay alternatives")
equal(linked.ns.Data.quests[900011].pre, nil, "several preQuestSingle leave no all-of set")
equal(linked.ns.Data.quests[900012].pre[1], 900001, "a preQuestGroup stays the all-of set")
equal(linked.ns.Data.quests[900012].preAny, nil, "a preQuestGroup alone leaves no any-of set")
equal(linked.ns.Data.quests[900013].pre[1], 900002, "both fields: the group is the all-of set")
equal(linked.ns.Data.quests[900013].preAny[1], 900001, "both fields: the single is the any-of set")
local unsupported = Fake()
unsupported.quests[900001].objectives = { nil, nil, nil, { { 72, 3000 } } }
local unknown =
	harness.load({ questiedb = unsupported, setup = Policy, player = { level = 20, map = 1429, x = 0.49, y = 0.42 } })
equal(unknown.ns.Data.quests[900001].objectivesUnknown, true, "unsupported objective stays explicit")
for _, step in ipairs(unknown.ns.Route().steps) do
	for _, id in ipairs(step.pickups or {}) do
		equal(id == 900001, false, "unsupported objective is never offered as delivery")
	end
end
local calls = 0
Policy(h, function()
	calls = calls + 1
	return false
end)
player = h.ns.State.Player()
player.level = 20
equal(Model.Eligible(h.ns.Data, player, {}, {}, 900001), false, "provider policy rejects unavailable quest")
Model.Eligible(h.ns.Data, player, {}, {}, 900001)
equal(calls, 1, "policy cached per snapshot")
Policy(h, function()
	error("provider failure")
end)
player = h.ns.State.Player()
player.level = 20
equal(Model.Eligible(h.ns.Data, player, {}, {}, 900001), false, "policy failure is closed")
equal(#h.errors, 0, "policy error contained")
local alone = harness.load({ questiedb = Fake() })
player = alone.ns.State.Player()
player.level = 20
equal(
	Model.Eligible(alone.ns.Data, player, {}, {}, 900001),
	false,
	"database alone cannot prove live event availability"
)
equal(alone.ns.Data.quests[900001].finish.npc, 197, "logged quest still has finish without policy")
-- Questie initializes policy corrections asynchronously. Publish no old quest data while waiting.
local ready, deadline
-- Questie loaded but not ready. The harness runs every timer at once, so the wait for Questie is held back in
-- `deadline` and runs only when a test says the wait is over.
local function NotReady(h2)
	Policy(h2)
	h2.G.Questie.API.isReady = false
	h2.G.Questie.API.RegisterOnReady = function(fn)
		ready = fn
	end
	local after = h2.G.C_Timer.After
	h2.G.C_Timer.After = function(delay, fn)
		if delay >= 60 then
			deadline = fn
		else
			after(delay, fn)
		end
	end
end
local delayed = harness.load({
	questiedb = Fake(),
	spf = "v1",
	charDB = { journey = "zone:1429", guided = "zone:1429" },
	setup = NotReady,
})
equal(next(delayed.ns.Data.quests), nil, "empty until provider ready")
equal(delayed.ns.QuestieStatus.settled, false, "provider startup remains provisional before ready")
equal(delayed.ns.QuestieBuilding(), true, "deferred provider blocks provisional route builds")
delayed.ns.Route()
equal(delayed.ns.Prefs().journey, "zone:1429", "saved story survives an initial route read")
equal(delayed.spf.NavigateRoute, 0, "Questie loading does not start a provisional route")
delayed.G.LibQuestieDB.Quest.GetAllIds = function()
	return { 900002 }
end
delayed.G.Questie.API.isReady = true
equal(delayed.ns.QuestieBuilding(), true, "provider remains blocked until its queued build starts")
ready()
delayed.flush()
equal(delayed.ns.QuestieStatus.settled, true, "provider marks startup settled after ready")
equal(delayed.ns.Route().journey, "zone:1429", "provider rebuild restores the saved story identity")
equal(delayed.spf.NavigateRoute, 1, "restored story commits guidance once")
equal(delayed.ns.Data.quests[900001], nil, "snapshot taken after policy corrections")
equal(delayed.ns.Data.quests[900002].title, "Collect", "ready callback publishes composed catalogue")
deadline()
delayed.flush()
equal(delayed.ns.Data.quests[900002].title, "Collect", "the wait ending after ready changes nothing")
-- Questie that never reports ready does not hold the guide for the whole session.
local stuck = harness.load({ questiedb = Fake(), setup = NotReady })
equal(stuck.ns.QuestieBuilding(), true, "the guide waits for Questie at first")
deadline()
stuck.flush()
equal(stuck.ns.QuestieBuilding(), false, "the wait for Questie ends")
equal(stuck.ns.QuestieStatus.state, "questie", "the catalogue is read without Questie's policy")
equal(stuck.ns.Data.quests[900001].title, "Provider-only quest", "the catalogue lands without Questie ready")
equal(stuck.ns.SourceHint(), stuck.ns.L.QUESTIE_POLICY, "the guide says recommendations need Questie")
stuck.G.LibQuestieDB.Quest.GetAllIds = function()
	return { 900002 }
end
stuck.G.Questie.API.isReady = true
ready()
stuck.flush()
equal(stuck.ns.Data.quests[900001], nil, "a late ready callback reads the catalogue again")
equal(stuck.ns.Data.quests[900002].title, "Collect", "the late read publishes the corrected catalogue")
-- A missing coordinate never inherits the bundled location for the same NPC/quest.
local fake = Fake()
fake.quests[7] = fake.quests[900001]
fake.npcs[197].spawns = {}
local unplaced = harness.load({ questiedb = fake, setup = Policy })
equal(unplaced.ns.Data.quests[7].start, nil, "no stale coordinates")
-- An exception leaves no partial catalogue.
local failed = harness.load({
	questiedb = Fake(),
	setup = function(h2)
		h2.G.LibQuestieDB.Quest.GetAll = function()
			error("unreadable")
		end
	end,
})
equal(failed.ns.QuestieStatus.state, "unavailable", "failed build")
equal(next(failed.ns.Data.quests), nil, "failed build never publishes partial records")
-- The full catalogue is time sliced, including provider-only IDs.
do
	local many = Fake()
	for id = 910000, 913000 do
		many.quests[id] = many.quests[900001]
	end
	local frames, reads, most = 0, 0, 0
	local sliced = harness.load({
		questiedb = many,
		setup = function(h2)
			h2.clockStep = 0.01
			local after = h2.G.C_Timer.After
			h2.G.C_Timer.After = function(delay, fn)
				frames = frames + 1
				most = math.max(most, reads)
				reads = 0
				return after(delay, fn)
			end
			local get = h2.G.LibQuestieDB.Quest.GetAll
			h2.G.LibQuestieDB.Quest.GetAll = function(...)
				reads = reads + 1
				return get(...)
			end -- multi-value: transparent wrapper
		end,
	})
	equal(#sliced.errors, 0, "sliced errors")
	equal(sliced.ns.QuestieStatus.questCount, 3003, "full catalogue count")
	equal(sliced.ns.QuestieStatus.catalogueCount, 3003, "provider count")
	equal(frames > 10, true, "build yields across frames")
	equal(most <= 501, true, "quest reads within slice")
end
-- The composed catalogue is saved per character and reloaded in place of the build. These checks drive the
-- production save path through tests/harness.lua: a save is only adopted for the exact inputs that produced it
-- (addon version, QuestieDB version and flavour, client build, locale, class, faction), a save that fails the
-- shape check rebuilds, and an adopted save is the built catalogue, value for value.
-- Counts Questie's quest id reads: a build asks, an adopted save never does.
local function Cat(version, charDB, change)
	local reads = 0
	local built = harness.load({
		version = version,
		questiedb = Fake(),
		charDB = charDB,
		setup = function(loaded)
			local ids = loaded.G.LibQuestieDB.Quest.GetAllIds
			loaded.G.LibQuestieDB.Quest.GetAllIds = function()
				reads = reads + 1
				return ids()
			end
			if change then
				change(loaded)
			end
			Policy(loaded)
		end,
	})
	return built, reads
end

-- The saved variables of one build, for a spec to reload.
local function SavedOnce(version)
	local built, reads = Cat(version)
	equal(reads > 0, true, "the first login builds")
	equal(built.ns.QuestieStatus.state, "questie", "the first login is ready")
	return built.G.AdventureGuideForeverCharDB
end

-- A saved catalogue is adopted the moment the saved variables and the character's class and faction are known, not
-- when Questie reports ready: the tracker shows the planned route, not the loading line. Questie's late ready joins
-- the live policy with one route rebuild and never rebuilds the catalogue.
do
	local charDB = SavedOnce("0.8.0")
	local log = {
		{ id = 900001, title = "Provider-only quest", level = 20, complete = false, map = 1429, x = 0.5, y = 0.5 },
	}
	local adopted = harness.load({
		version = "0.8.0",
		questiedb = Fake(),
		charDB = charDB,
		log = log,
		setup = NotReady,
	})
	equal(adopted.ns.QuestieStatus.state, "questie", "a saved catalogue is ready before Questie")
	equal(adopted.ns.QuestieStatus.settled, true, "an adopted save is settled, so no route is held")
	equal(adopted.ns.QuestieBuilding(), false, "the guide does not wait for Questie")
	equal(adopted.ns.Data.quests[900001].title, "Provider-only quest", "the saved records are the route's records")
	equal(#adopted.ns.Route().steps > 0, true, "an adopted save shows a planned route at once")
	equal(
		adopted.tracker.liveBlocks.loading == nil or not adopted.tracker.liveBlocks.loading.used,
		true,
		"the tracker shows no loading line"
	)
	equal(#adopted.errors, 0, "adoption raises no error")
	-- Questie ready afterwards: one route rebuild for the live policy, no catalogue read.
	local reads = 0
	local ids = adopted.G.LibQuestieDB.Quest.GetAllIds
	adopted.G.LibQuestieDB.Quest.GetAllIds = function()
		reads = reads + 1
		return ids()
	end
	local plans = adopted.modelCalls.Plan
	adopted.G.Questie.API.isReady = true
	ready()
	adopted.flush()
	equal(reads, 0, "Questie becoming ready never rebuilds the catalogue")
	equal(adopted.modelCalls.Plan - plans, 1, "Questie becoming ready costs exactly one route rebuild")
	equal(adopted.ns.Data.quests[900001].title, "Provider-only quest", "the adopted records stand after ready")
	equal(#adopted.errors, 0, "the late ready raises no error")
end
-- A key that no longer matches neither adopts nor waits forever: Questie's ready callback builds the catalogue.
do
	local charDB = SavedOnce("0.8.0")
	local changed = harness.load({
		version = "0.8.1",
		questiedb = Fake(),
		charDB = charDB,
		setup = NotReady,
	})
	equal(changed.ns.QuestieStatus.settled, false, "a changed key waits for Questie")
	equal(changed.ns.QuestieBuilding(), true, "and holds the route")
	equal(next(changed.ns.Data.quests), nil, "no saved records are adopted")
	changed.G.LibQuestieDB.Quest.GetAllIds = function()
		return { 900002 }
	end
	changed.G.Questie.API.isReady = true
	ready()
	changed.flush()
	equal(changed.ns.QuestieStatus.state, "questie", "the build lands")
	equal(changed.ns.Data.quests[900002].title, "Collect", "a changed key builds the catalogue")
	equal(changed.ns.Data.quests[900001], nil, "the build replaces the saved records")
	equal(#changed.errors, 0, "the rebuild raises no error")
end

-- One Lua literal per value, as the client writes saved variables: the round trip proves the save is plain data
-- (no cycles, functions or userdata) as much as it proves the two loads agree.
local function Write(value)
	local kind = type(value)
	if kind == "string" then
		return ("%q"):format(value)
	end
	if kind == "number" or kind == "boolean" then
		return tostring(value)
	end
	assert(kind == "table", "a saved catalogue value is savable data, got " .. kind)
	local parts, n = {}, #value
	for index = 1, n do
		parts[#parts + 1] = "[" .. index .. "]=" .. Write(value[index])
	end
	for key, item in pairs(value) do
		if type(key) ~= "number" or key < 1 or key > n then
			parts[#parts + 1] = "[" .. Write(key) .. "]=" .. Write(item)
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- Deep equality, so a reloaded catalogue is compared value for value, not by identity.
local function Same(a, b, path)
	if type(a) ~= type(b) then
		return false, path .. ": " .. type(a) .. " vs " .. type(b)
	end
	if type(a) ~= "table" then
		return a == b, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
	end
	for key, value in pairs(a) do
		local ok, why = Same(value, b[key], path .. "." .. tostring(key))
		if not ok then
			return false, why
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false, path .. "." .. tostring(key) .. ": absent from the build"
		end
	end
	return true
end

-- A build, a client-side save and a reload: the two catalogues are deeply the same and the reload reads no
-- QuestieDB, so the saved catalogue has completely replaced the build.
do
	local build, firstReads = Cat("0.8.0")
	equal(firstReads > 0, true, "the cache source build reads QuestieDB")
	local charDB = build.G.AdventureGuideForeverCharDB
	local reloaded = assert(loadstring("return " .. Write(charDB)))()
	local again, reads = Cat("0.8.0", reloaded)
	equal(reads, 0, "an unchanged save is adopted without a QuestieDB read")
	equal(again.ns.QuestieStatus.state, "questie", "an adopted save is ready")
	local same, why = Same(build.ns.Data.quests, again.ns.Data.quests, "quests")
	equal(same, true, "saved quests equal the built ones: " .. tostring(why))
	same, why = Same(build.ns.Data.hubs, again.ns.Data.hubs, "hubs")
	equal(same, true, "saved hubs equal the built ones: " .. tostring(why))
	same, why = Same(build.ns.Data.npcs, again.ns.Data.npcs, "npcs")
	equal(same, true, "saved npcs equal the built ones: " .. tostring(why))
	equal(#build.errors, 0, "the build raises no error")
	equal(#again.errors, 0, "the adopted save raises no error")
end

-- Every input in the key invalidates the save on its own: a changed value rebuilds rather than adopting.
for _, case in ipairs({
	{
		"addon version",
		function()
			return "0.8.1"
		end,
	},
	{
		"QuestieDB version",
		nil,
		function(loaded)
			loaded.metadata.QuestieDB.Version = "0.0-other"
		end,
	},
	{
		"client build",
		nil,
		function(loaded)
			loaded.G.GetBuildInfo = function()
				return "1.60.2", "69914", "Sep 2 2026", 16002
			end
		end,
	},
	{
		"locale",
		nil,
		function(loaded)
			loaded.G.GetLocale = function()
				return "deDE"
			end
		end,
	},
	{
		"class",
		nil,
		function(loaded)
			loaded.G.UnitClassBase = function()
				return "MAGE"
			end
		end,
	},
	{
		"faction",
		nil,
		function(loaded)
			loaded.G.UnitFactionGroup = function()
				return "Alliance"
			end
		end,
	},
}) do
	local charDB = SavedOnce("0.8.0")
	local version = case[2] and case[2]() or "0.8.0"
	local rebuilt, reads = Cat(version, charDB, case[3])
	equal(reads > 0, true, "a changed " .. case[1] .. " rebuilds")
	equal(rebuilt.ns.QuestieStatus.state, "questie", "a changed " .. case[1] .. " still lands")
	equal(#rebuilt.errors, 0, "a changed " .. case[1] .. " raises no error")
end

-- A QuestieDB flavour this addon cannot read is never matched against a saved catalogue: the catalogue is
-- unavailable, not stale.
do
	local charDB = SavedOnce("0.8.0")
	local rebuilt, reads = Cat("0.8.0", charDB, function(loaded)
		loaded.metadata.QuestieDB["X-Flavor"] = "Camelot"
	end)
	equal(reads, 0, "a foreign flavour never reads the provider")
	equal(rebuilt.ns.QuestieStatus.state, "unavailable", "a foreign flavour is unavailable")
	equal(next(rebuilt.ns.Data.quests), nil, "a foreign flavour uses no saved quests")
end

-- A save that fails the shape check is rebuilt, never trusted and never an error.
for _, damage in ipairs({
	function(save)
		save.quests = "nope"
	end,
	function(save)
		save.quests = {}
	end,
	function(save)
		save.quests = { [7] = "not a quest" }
	end,
	function(save)
		save.hubs = nil
	end,
	function(save)
		save.npcs = 5
	end,
}) do
	local charDB = SavedOnce("0.8.0")
	damage(charDB.catalogue)
	local rebuilt, reads = Cat("0.8.0", charDB)
	equal(reads > 0, true, "a damaged save rebuilds")
	equal(rebuilt.ns.QuestieStatus.state, "questie", "a damaged save still lands")
	equal(#rebuilt.errors, 0, "a damaged save raises no error")
end
do
	local charDB = SavedOnce("0.8.0")
	charDB.catalogue = 5
	local rebuilt, reads = Cat("0.8.0", charDB)
	equal(reads > 0, true, "a foreign catalogue rebuilds")
	equal(#rebuilt.errors, 0, "a foreign catalogue raises no error")
end
-- A Questie update that leaves the quest's availability where the last plan found it buys no rebuild, however many
-- objectives it carries; one that moves it buys exactly one, and the client event it accompanies shares that plan.
do
	local availability = { [900001] = true }
	local update
	local both = harness.load({
		questiedb = Fake(),
		setup = function(loaded)
			loaded.G.Questie = {
				API = {
					isReady = true,
					RegisterOnReady = function(fn)
						fn()
					end,
					RegisterForQuestUpdates = function(fn)
						update = fn
					end,
				},
			}
			loaded.G.QuestieLoader = {
				ImportModule = function()
					return {
						IsDoable = function(id)
							return availability[id] == true
						end,
					}
				end,
			}
		end,
	})
	equal(type(update), "function", "Questie update callbacks are registered")
	local base = both.modelCalls.Plan
	for _ = 1, 13 do
		update(900001, 1, 2)
		both.tick()
	end
	both.flush()
	equal(both.modelCalls.Plan, base, "an unchanged availability costs no rebuild")
	availability[900001] = false
	update(900001, 1, 2)
	both.tick()
	both.flush()
	equal(both.modelCalls.Plan, base + 1, "a moved availability rebuilds once")
	-- Both handlers in the same frame cost one plan, whatever order they run in.
	for _, order in ipairs({ "questie first", "client first" }) do
		local mark = both.modelCalls.Plan
		for _ = 1, 3 do
			if order == "questie first" then
				update(900001, 1, 2)
				both.fire("QUEST_LOG_UPDATE")
			else
				both.fire("QUEST_LOG_UPDATE")
				update(900001, 1, 2)
			end
			both.tick()
			both.flush()
		end
		equal(both.modelCalls.Plan - mark, 3, order .. ": one plan per frame, not one per handler")
	end
	equal(#both.errors, 0, "the update coalescing raises no error")
end
print(("questie_spec: %d checks passed"):format(checks))
