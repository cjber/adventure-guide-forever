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
				objectives = { { { 800, nil, 5 } } },
			},
			[900002] = {
				name = "Collect",
				questLevel = 19,
				requiredLevel = 17,
				startedBy = { { 197 } },
				zoneOrSort = 12,
				objectives = { nil, nil, { { 700, nil, 3 } } },
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
equal(q.need[0], 5, "objective count")
equal(q.obj[1][5], 1429, "provider objective map")
equal(q.obj[1][2], 500, "provider spawn")
equal(h.ns.Data.quests[900002].need[4], 3, "item count")
equal(h.ns.Data.quests[900002].obj[1][2], 500, "item drop location")
local player = h.ns.State.Player()
player.level = 20
local Model = h.ns.Model
equal(Model.Eligible(h.ns.Data, player, {}, {}, 900001), true, "canonical quest eligible")
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
local ready
local delayed = harness.load({
	questiedb = Fake(),
	setup = function(h2)
		Policy(h2)
		h2.G.Questie.API.isReady = false
		h2.G.Questie.API.RegisterOnReady = function(fn)
			ready = fn
		end
	end,
})
equal(next(delayed.ns.Data.quests), nil, "empty until provider ready")
delayed.G.LibQuestieDB.Quest.GetAllIds = function()
	return { 900002 }
end
delayed.G.Questie.API.isReady = true
ready()
delayed.flush()
equal(delayed.ns.Data.quests[900001], nil, "snapshot taken after policy corrections")
equal(delayed.ns.Data.quests[900002].title, "Collect", "ready callback publishes composed catalogue")
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
	equal(most <= 201, true, "quest reads within slice")
end
print(("questie_spec: %d checks passed"):format(checks))
