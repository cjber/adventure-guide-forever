-- Run from the repository root: luajit tests/party_spec.lua
-- Party quests (docs/design.md §4.5, Core/Party.lua): in a party, a step for a quest someone in the party also has
-- counts as nearer (Model.PartyCost), never a fixed order; a pickup the party has says so. The party's quests come
-- from what the client shows (C_QuestLog.IsUnitOnQuest) alone. Nothing is ever sent to another player: no addon
-- message, no prefix registered, whatever the party or the setting.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(condition, label)
	checks = checks + 1
	if not condition then
		error(label, 2)
	end
end
local function equal(actual, expected, label)
	check(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end

--[[ The planner: Model.PartyCost and the route it leans ]]

do
	local ns = {}
	harness.model(ns)
	local Model = ns.Model

	equal(Model.PartyCost(nil, { 1 }, 400), 400, "cost: out of a party nothing changes")
	equal(Model.PartyCost({ [2] = 1 }, { 1 }, 400), 400, "cost: a step the party doesn't share keeps its cost")
	equal(Model.PartyCost({ [1] = 1 }, { 1 }, 400), 200, "cost: a shared step costs half")
	equal(Model.PartyCost({ [1] = 2 }, { 3, 1 }, 2000), 1700, "cost: but never more than 300 yards less")
	equal(Model.PartyCost({ [1] = 1 }, nil, 400), 400, "cost: a step with no quests keeps its cost")

	-- Model.Nearest takes the party too: the shared stop leads while it is within reach of the nearest.
	local function Stop(key, x, quest)
		return { key = key, x = x, y = 0, continent = 1, known = true, r = 0, quests = { quest } }
	end
	local from = { x = 0, y = 0, continent = 1, known = true }
	local function At(step)
		return step
	end
	local function Keys(path)
		local keys = {}
		for _, step in ipairs(path) do
			keys[#keys + 1] = step.key
		end
		return table.concat(keys, " ")
	end
	equal(Keys(Model.Nearest(from, { Stop("a", 100, 1), Stop("b", 180, 2) }, At)), "a b", "nearest: alone, a leads")
	equal(
		Keys(Model.Nearest(from, { Stop("a", 100, 1), Stop("b", 180, 2) }, At, nil, { [2] = 1 })),
		"b a",
		"nearest: the party's stop leads when it is not much farther"
	)
	equal(
		Keys(Model.Nearest(from, { Stop("a", 100, 1), Stop("b", 900, 2) }, At, nil, { [2] = 1 })),
		"a b",
		"nearest: a party stop far beyond the nearest still waits"
	)

	-- Model.Plan over two carried quests' areas and one pickup.
	local data = {
		quests = {},
		zones = { [1] = { name = "Zone", min = 10, max = 25 } },
		maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [0] = { x = 0, y = 0 } },
	}
	for id, x in ipairs({ 0.3, 0.7, 0.5 }) do
		data.quests[id] = {
			title = "Quest " .. id,
			level = 17,
			min = 10,
			side = 1,
			zone = 1,
			start = { map = 1, x = x, y = 0.2, name = "Giver " .. id, hub = id },
			finish = { map = 1, x = x, y = 0.2, name = "Giver " .. id, hub = id },
			need = { [0] = 10 },
			obj = { { 0, x * 1000, 500, 10 } },
			xp = 1000,
		}
	end
	local log = {}
	for id = 1, 2 do
		log[id] = {
			id = id,
			title = "Quest " .. id,
			level = 17,
			complete = false,
			objectives = { { type = "monster", done = false, have = 0, need = 10 } },
		}
	end
	local player = { level = 19, maxLevel = 60, side = 1, raceBit = 1, classBit = 2, map = 1, x = 0.45, y = 0.5 }
	local prefs = { quests = true, dungeons = false, skipped = {}, journey = "zone:1" }
	local function Route()
		return Model.Plan(data, player, {}, log, prefs).steps
	end
	local function FirstArea()
		for _, step in ipairs(Route()) do
			if step.kind == "area" then
				return step.quests[1]
			end
		end
	end
	equal(FirstArea(), 1, "plan: alone, the nearer area leads")
	player.party = { [2] = 1 }
	equal(FirstArea(), 2, "plan: the area of a quest the party shares leads when it is a little farther")
	player.x = 0.32
	equal(FirstArea(), 1, "plan: standing beside the other area, the nearest still leads (never a fixed order)")
	player.x, player.party = 0.45, nil
	equal(FirstArea(), 1, "plan: the party gone, the order is the plain nearest again")

	-- A pickup someone in the party has says so; the same pickup alone keeps its own reason.
	local function PickupReason()
		for _, step in ipairs(Route()) do
			if step.kind == "town" and step.pickups and step.pickups[1] == 3 and #step.quests == 1 then
				return step.reason
			end
		end
	end
	local alone = PickupReason()
	check(alone ~= nil and alone ~= ns.L.PARTY_HAS, "plan: the pickup alone gives its usual reason")
	player.party = { [3] = 1 }
	equal(PickupReason(), ns.L.PARTY_HAS, "plan: a pickup the party has says someone in the party has it")
	player.party = nil
end

--[[ The client: what is read, and that nothing is ever sent ]]

local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	{ id = 870, title = "The Forgotten Pools", level = 14, complete = false },
}

-- A party of the player and Ana (or nobody), a client that answers IsUnitOnQuest from `on`, and a chat that records
-- any addon message or prefix the addon would send or register.
local function Load(options)
	options = options or {}
	local party = { grouped = options.grouped ~= false, raid = false, members = { party1 = "Ana" }, on = {} }
	local sent, prefixes = {}, {}
	local h = harness.load({
		log = LOG,
		db = options.db,
		charDB = options.charDB,
		setup = function(h)
			local G = h.G
			G.LE_PARTY_CATEGORY_HOME = 1
			G.IsInGroup = function(category)
				if category == 1 then
					return party.grouped
				end
				return party.grouped or party.instance == true
			end
			G.IsInRaid = function()
				return party.raid
			end
			G.UnitExists = function(unit)
				return party.grouped and party.members[unit] ~= nil
			end
			G.C_QuestLog.IsUnitOnQuest = function(unit, questID)
				return party.on[unit] ~= nil and party.on[unit][questID] == true
			end
			G.C_ChatInfo = {
				RegisterAddonMessagePrefix = function(prefix)
					prefixes[#prefixes + 1] = prefix
					return 0
				end,
				SendAddonMessage = function(prefix, text, channel)
					sent[#sent + 1] = { prefix = prefix, text = text, channel = channel }
					return 0
				end,
			}
			if options.setup then
				options.setup(h)
			end
		end,
	})
	h.party, h.sent, h.prefixes = party, sent, prefixes
	return h
end

-- Every event the party module once answered with a message, fired in and out of a party.
local function Everything(h)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_QUEST_LOG_CHANGED" }) do
		h.fire(event)
	end
	h.fire("QUEST_ACCEPTED", 870)
	h.fire("QUEST_REMOVED", 845)
	h.fire("QUEST_TURNED_IN", 845)
	h.fire("CHAT_MSG_ADDON", "AGFParty", "2?001:01/01:nh|", "PARTY", "Ana-Realm")
	h.flush()
end

-- Not in a party: nothing is read or sent, and the planner favours nothing.
do
	local h = Load({ grouped = false })
	Everything(h)
	equal(h.ns.Party.Quests(), nil, "alone: no party quests")
	equal(h.ns.State.Player().party, nil, "alone: the planner sees no party")
	equal(#h.sent, 0, "alone: no message is sent")
	equal(#h.prefixes, 0, "alone: no addon message prefix is registered")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- In a party: Ana's log, as the client shows it, makes a shared quest; nothing goes to her.
do
	local h = Load()
	h.party.on.party1 = { [870] = true }
	Everything(h)
	local quests = h.ns.Party.Quests()
	check(quests and quests[870] == 1 and quests[845] == nil, "party: the quest Ana has too is shared")
	equal(h.ns.State.Player().party, quests, "party: the planner reads the same answer")
	check(table.concat(h.ns.ReportLines(), "\n"):find("Party quests shared: 1", 1, true), "party: /agf report says so")
	equal(#h.sent, 0, "party: no message is sent")
	equal(#h.prefixes, 0, "party: no addon message prefix is registered")

	-- Combat: the read waits for the fight's end.
	h.party.on.party1 = { [870] = true, [845] = true }
	h.SetCombat(true)
	h.fire("UNIT_QUEST_LOG_CHANGED", "party1")
	h.flush()
	equal(h.ns.Party.Quests()[845], nil, "combat: the party is not read in a fight")
	h.SetCombat(false)
	h.flush()
	equal(h.ns.Party.Quests()[845], 1, "combat: it is read once the fight ends")

	-- Ana leaves: her quests go with her.
	h.party.members.party1 = nil
	h.party.grouped = false
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	equal(h.ns.Party.Quests(), nil, "left: no party quests once the party is gone")
	equal(#h.sent, 0, "left: still nothing sent")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- An instance group of strangers is not a party: nothing is read.
do
	local h = Load({ grouped = false })
	h.party.instance = true
	h.party.on.party1 = { [870] = true }
	Everything(h)
	equal(h.ns.Party.Quests(), nil, "instance group: nothing is favoured")
	equal(#h.sent, 0, "instance group: no message is sent")
end

-- Two members on one quest count as two.
do
	local h = Load()
	h.party.members.party2 = "Bo"
	h.party.on = { party1 = { [870] = true }, party2 = { [870] = true } }
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	equal(h.ns.Party.Quests()[870], 2, "two members: counted twice")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A turn-in on its own reads the party again.
do
	local h = Load()
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	equal(h.ns.Party.Quests(), nil, "turn-in: nothing shared before")
	h.party.on.party1 = { [845] = true }
	h.fire("QUEST_TURNED_IN", 869)
	h.flush()
	check(h.ns.Party.Quests() and h.ns.Party.Quests()[845] == 1, "turn-in: the party is read again")
	equal(#h.sent, 0, "turn-in: no message is sent")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The setting off: nothing is read; turning it on reads at once, and off again drops the answer.
do
	local h = Load({ db = { partyQuests = false } })
	h.party.on.party1 = { [870] = true }
	Everything(h)
	equal(h.ns.Party.Quests(), nil, "off: no party quests")
	h.ns.SetSetting("partyQuests", true)
	h.flush()
	check(h.ns.Party.Quests() and h.ns.Party.Quests()[870] == 1, "on: the party is read at once")
	h.ns.SetSetting("partyQuests", false)
	h.flush()
	equal(h.ns.Party.Quests(), nil, "off again: the party's quests are dropped")
	equal(#h.sent, 0, "toggled: no message is ever sent")
	equal(#h.prefixes, 0, "toggled: no prefix is ever registered")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- Members once ticked under the old Sync with are cleared from the saved preferences on load.
do
	local db = { sync = { ["Ana-Realm"] = true } }
	local h = Load({ charDB = db })
	equal(db.sync, nil, "saved: the old sync ticks are gone")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print(("party_spec: %d checks passed"):format(checks))
