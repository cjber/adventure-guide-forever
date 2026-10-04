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
print(("questie_spec: %d checks passed"):format(checks))
